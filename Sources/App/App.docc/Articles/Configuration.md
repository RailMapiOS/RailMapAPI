# Configuration

Environment variables, persistence, and runtime settings.

## Environment

Configuration is read from `.env` at startup (see `.env.example`).

| Variable           | Required | Default | Description                                                                                          |
|--------------------|----------|---------|------------------------------------------------------------------------------------------------------|
| `API_AUTH_TOKENS`  | Yes      | —       | Comma-separated Bearer tokens. Whitespace around tokens is trimmed. Empty value fails closed.        |
| `LOG_LEVEL`        | No       | `debug` | Vapor log level — one of `trace`, `debug`, `info`, `notice`, `warning`, `error`, `critical`.         |

If `API_AUTH_TOKENS` is empty or unset, every authenticated route returns `503 Service Unavailable` — the API refuses to serve traffic without a valid allowlist.

## Persistence

Static GTFS feeds are persisted in **SQLite** (`db.sqlite`) via Fluent migrations. The schema covers:

- `feeds` — One row per (source, version) catalogue.
- `agencies`, `routes`, `trips`, `stops`, `stop_times`, `calendar_dates` — Foreign-keyed to `feeds.id`.

Migrations run automatically at boot via `app.autoMigrate()` in `configure(_:)`.

In Docker, the database lives inside the container by default. Mount a volume on `/app/db.sqlite` if you want persistence across rebuilds.

## Cache TTLs

Cache TTLs are set per-source in LocomoSwift, not in this API:

- **Static feeds** — Refresh interval defined by `DataSource.staticRefreshInterval` (24h for SNCF, ~6 months for SBB, etc.).
- **Realtime feeds** — TTL defined by `DataSource.realtimeCacheTTL` (30s for SBB, 60s for TaM, 120s for SNCF).

To override, register a custom `DataSource` — see <doc:AddingADataSource>.

## Logging

Vapor's `Logger` is wired to stdout. In production, pipe through your container runtime's log driver (Docker's `json-file`, journald, …).

Set `LOG_LEVEL=info` in production to suppress noisy debug output.
