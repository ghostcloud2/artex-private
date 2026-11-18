#!/bin/sh
# ARTEX daemon supervisor (Linux / Docker ENTRYPOINT).
#
# In managed cloud containers ARTEX starts a private PostgreSQL instance on a
# Unix socket when ARTEX_PG_DSN is not supplied. This keeps the PostgreSQL-only
# backend self-contained; an explicitly supplied ARTEX_PG_DSN still wins.
set -u

cd "$(dirname "$0")" || exit 1

BIN=./artex
[ -x "$BIN" ] || { echo "[artex] executable not found: $BIN" >&2; exit 1; }

RESTART_CODE=75
MAX_DELAY=60
DATA_DIR="${ARTEX_DATA_DIR:-/app/data}"
PGDATA="${ARTEX_PGDATA:-$DATA_DIR/postgres}"
PGSOCKET="${ARTEX_PGSOCKET:-/tmp/artex-pg}"
PG_BIN="${PG_BIN:-$(pg_config --bindir 2>/dev/null || true)}"
[ -n "$PG_BIN" ] || PG_BIN="$(find /usr/lib/postgresql -mindepth 2 -maxdepth 2 -type f -name pg_ctl -printf '%h' -quit 2>/dev/null || true)"
started_pg=0

prepare_internal_postgres() {
	if [ -n "${ARTEX_PG_DSN:-}" ]; then
		echo "[pg] using supplied ARTEX_PG_DSN"
		return 0
	fi
	if [ "${ARTEX_INTERNAL_POSTGRES:-1}" = "0" ]; then
		echo "[pg] internal PostgreSQL disabled; ARTEX_PG_DSN must be supplied" >&2
		return 0
	fi
	if [ -z "$PG_BIN" ] || [ ! -x "$PG_BIN/initdb" ]; then
		echo "[pg] PostgreSQL server binaries are not installed" >&2
		return 1
	fi
	mkdir -p "$DATA_DIR" "$PGSOCKET"
	chown -R postgres:postgres "$PGDATA" "$PGSOCKET" 2>/dev/null || true
	if [ ! -s "$PGDATA/PG_VERSION" ]; then
		su -s /bin/sh postgres -c "$PG_BIN/initdb -D '$PGDATA' --auth=trust --no-locale --encoding=UTF8 >/dev/null"
	fi
	if ! su -s /bin/sh postgres -c "$PG_BIN/pg_ctl -D '$PGDATA' status >/dev/null 2>&1"; then
		su -s /bin/sh postgres -c "$PG_BIN/pg_ctl -D '$PGDATA' -o \"-c listen_addresses='' -c unix_socket_directories='$PGSOCKET'\" -w start >/dev/null"
		started_pg=1
	fi
	if ! su -s /bin/sh postgres -c "$PG_BIN/psql -h '$PGSOCKET' -d postgres -tAc \"SELECT 1 FROM pg_database WHERE datname='artex'\"" | grep -q 1; then
		su -s /bin/sh postgres -c "$PG_BIN/createdb -h '$PGSOCKET' artex"
	fi
	export ARTEX_PG_DSN="${ARTEX_INTERNAL_PG_DSN:-postgresql:///artex?host=$PGSOCKET}"
	echo "[pg] internal PostgreSQL ready on private Unix socket $PGSOCKET"
}

stop_internal_postgres() {
	if [ "$started_pg" -eq 1 ] && [ -n "$PG_BIN" ] && [ -x "$PG_BIN/pg_ctl" ]; then
		su -s /bin/sh postgres -c "$PG_BIN/pg_ctl -D '$PGDATA' -m fast stop >/dev/null 2>&1" || true
	fi
}

prepare_internal_postgres || exit 1
trap stop_internal_postgres EXIT

child=0
stopping=0

forward() {
	stopping=1
	if [ "$child" -ne 0 ]; then
		kill -TERM "$child" 2>/dev/null || true
	fi
}
trap forward INT TERM

delay=1
while :; do
	"$BIN" "$@" &
	child=$!

	wait "$child"
	code=$?
	if [ "$code" -gt 128 ]; then
		wait "$child" || true
		code=$?
	fi
	child=0

	if [ "$stopping" -eq 1 ]; then
		echo "[artex] stopped"
		exit 0
	fi

	case "$code" in
		0)
			echo "[artex] exited normally"
			exit 0
			;;
		"$RESTART_CODE")
			echo "[artex] restart requested"
			delay=1
			;;
		*)
			echo "[artex] abnormal exit (code=$code), restarting in ${delay}s" >&2
			sleep "$delay"
			delay=$((delay * 2))
			[ "$delay" -gt "$MAX_DELAY" ] && delay=$MAX_DELAY
			;;
	esac
done
