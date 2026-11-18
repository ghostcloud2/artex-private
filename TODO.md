# Cloud delivery outcomes

- [x] Import `ghostcloud2/artex-private` into the managed ARTEX cloud project without replacing the Go, Next.js, or PostgreSQL stack.
- [x] Prefer the managed internal server-side LLM service (`MANUS_API_URL` and `MANUS_API_KEY`) so users do not need to provide an external provider API key; preserve explicit external-provider fallback support.
- [x] Add cloud `PORT`/bind-address handling and a production container build that embeds the frontend in the Go backend.
- [x] Keep the PostgreSQL-only backend runnable with an internal PostgreSQL Unix-socket service when no external `ARTEX_PG_DSN` is supplied.
- [ ] Complete cloud build, health verification, checkpoint, and publication.
