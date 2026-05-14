# Deployment

Build and run RailMapAPI in production with Docker.

## Overview

The shipped `Dockerfile` is a multi-stage build:

- **Build stage** — `swift:6.2-jammy`. Resolves dependencies, statically links the Swift stdlib, links jemalloc.
- **Runtime stage** — `ubuntu:jammy` with `libjemalloc2`, `ca-certificates`, `tzdata`, and `libcurl4` (required by `FoundationNetworking` for GTFS-RT fetches on Linux). Runs as non-root user `vapor`.

Both **x86_64** and **ARM64** are supported natively — no QEMU emulation needed.

## Build & run

```sh
docker compose build
docker compose up -d app
```

`docker-compose.yml`:

- Reads `.env` and **fails fast** if `API_AUTH_TOKENS` is missing.
- Exposes port `8080`.
- Defaults to `--env production`.

## Reverse proxy

For production, terminate TLS in front of the app — the API itself listens on plain HTTP. Common choices:

- **Caddy** — Auto-cert via Let's Encrypt, single-file config.
- **Nginx** — `proxy_pass http://app:8080;` after standard TLS setup.
- **Traefik** — Useful when you're already on a Docker Swarm or k8s.

Caddyfile snippet:

```
api.example.com {
    reverse_proxy app:8080
}
```

## Persistence

The SQLite database (`db.sqlite`) lives inside the container by default. To persist across rebuilds, mount a volume:

```yaml
services:
  app:
    volumes:
      - railmap-data:/app/db.sqlite

volumes:
  railmap-data:
```

For multi-instance deployments, swap SQLite for Postgres in `configure.swift` (Fluent already supports it via `FluentPostgresDriver`). Note: the cache layer is per-process — running multiple replicas means duplicated upstream fetches.

## Container registry

Images are intended to ship via **GitHub Container Registry** (ghcr.io). Tag and push:

```sh
docker tag rail-map-a-p-i:latest ghcr.io/railmapios/railmapapi:latest
docker push ghcr.io/railmapios/railmapapi:latest
```

## Health checks

`GET /hello` is intentionally public — wire it up as your liveness probe:

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/hello"]
  interval: 30s
  timeout: 5s
  retries: 3
```

Add `curl` to the runtime image if you want this to work as-is, or replace with `wget --spider`.

## Resource sizing

Per-source memory footprint scales with the static GTFS catalogue size. SNCF's national export (~200 MB unzipped) dominates — budget **512 MB** of RAM minimum, **1 GB** comfortably. CPU is only loaded during cold-start parses; steady-state requests are cheap.

## Logs

Vapor writes structured logs to stdout. Set `LOG_LEVEL=info` in production to suppress noisy debug output.
