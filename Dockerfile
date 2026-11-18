# syntax=docker/dockerfile:1

# Build the static Next.js export separately so the Go binary can embed it.
FROM node:22-bookworm AS frontend
WORKDIR /src
COPY web/package.json web/package-lock.json ./web/
RUN cd web && npm ci
COPY web/ ./web/
RUN cd web && npm run build:static

# Compile the backend with the exported UI embedded in the binary.
FROM golang:1.26.3-bookworm AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
COPY --from=frontend /src/web/out ./web/out
RUN rm -rf server/webui/dist \
    && mkdir -p server/webui/dist \
    && cp -a web/out/. server/webui/dist/ \
    && CGO_ENABLED=0 go build -tags embedui -trimpath -ldflags="-s -w" -o /out/artex ./cmd/artex

# Runtime image: ARTEX needs PostgreSQL, recon utilities, Python-based skills,
# and Node for optional browser/MCP tools. The internal PostgreSQL instance is
# started by start.sh only when ARTEX_PG_DSN is not supplied.
FROM node:22-bookworm
ENV ARTEX_BIND=0.0.0.0
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates python3 postgresql postgresql-client \
      ripgrep curl wget vim git jq unzip \
      dnsutils iputils-ping netcat-openbsd inetutils-telnet whois nmap \
    && rm -rf /var/lib/apt/lists/*
# Preinstall the browser MCP and Chromium so enabling ARTEX's built-in browser
# tool does not require a first-request network download.
RUN npm install -g @playwright/mcp@latest @playwright/cli@latest playwright@latest \
    && playwright-cli --help \
    && playwright install --with-deps chromium \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /out/artex /app/artex
COPY start.sh /app/start.sh
COPY skills/ /app/skills/
RUN chmod +x /app/artex /app/start.sh \
    && mkdir -p /app/data \
    && chown -R postgres:postgres /app/data
VOLUME ["/app/data"]
EXPOSE 3000
ENTRYPOINT ["/app/start.sh"]
CMD ["-proxy", ""]
