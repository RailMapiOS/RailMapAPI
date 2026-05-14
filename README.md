# RailMapAPI

![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange)
![Vapor 4](https://img.shields.io/badge/Vapor-4-blue)
![Linux](https://img.shields.io/badge/Linux-x86__64%20%7C%20ARM64-lightgrey)
![Docker](https://img.shields.io/badge/Docker-ready-2496ED)
![License](https://img.shields.io/badge/License-MIT-lightgrey)

Backend HTTP service that aggregates **GTFS Static** and **GTFS Realtime v2.0** feeds from European transit operators and exposes a unified, JSON-friendly API for the [RailMap iOS app](https://github.com/RailMapiOS).

Built on **Vapor 4**, powered by [LocomoSwift](https://github.com/RailMapiOS/LocomoSwift), runs on Linux (x86_64 and ARM64) in Docker.

## What it does

- **Aggregates multiple operators** — SNCF (TER, TGV, Intercités), Breizhgo, SBB/CFF/FFS, TaM Montpellier — all behind a single `?source=…` query parameter.
- **Caches static feeds** — GTFS ZIPs are downloaded once per refresh window, persisted in SQLite, and shared across requests via `FeedManager`.
- **Streams realtime updates** — TripUpdates, VehiclePositions, ServiceAlerts, and realtime Shapes are decoded on the fly with TTL-based caching.
- **Resolves trips by train number** — Looks up `trip_short_name` across one or many sources to map a train number to its route, agency, headsign, and shape.
- **Builds shapes with fallback chain** — GTFS `shapes.txt` → signal.eu.org OSRM (European rail) → Overpass API → straight stop-to-stop lines.
- **Exposes the full GTFS-RT v2.0 payload** — TranslatedString (locale-resolved), TranslatedImage, multi-carriage details, severity levels, modified-trip selectors, and forward-compatible enums.

## Endpoints

All endpoints (except `/hello`) require `Authorization: Bearer <token>` — see [Authentication](#authentication).

### Discovery

| Method | Path                     | Description                                       |
|--------|--------------------------|---------------------------------------------------|
| GET    | `/hello`                 | Public liveness probe.                            |
| GET    | `/sources`               | Lists every configured DataSource.                |
| GET    | `/realtime/sources`      | Lists sources that have at least one RT feed.     |

### Static GTFS

| Method | Path                              | Description                                                           |
|--------|-----------------------------------|-----------------------------------------------------------------------|
| GET    | `/stop/:headsign?source=…`        | All vehicle journeys serving the given headsign.                      |
| GET    | `/train/:trainNumber?source=…`    | Resolves a train number (`trip_short_name`) to its route, agency, headsign. Searches every source if `source` is omitted. |
| GET    | `/train/:trainNumber/shape?source=…` | Polyline (GeoJSON `LineString`) for a train trip, with fallback chain. |

### Realtime GTFS-RT

| Method | Path                                | Description                                                              |
|--------|-------------------------------------|--------------------------------------------------------------------------|
| GET    | `/realtime/trip-updates?source=…`   | All trip updates for the source.                                         |
| GET    | `/realtime/trip-updates/:tripID?source=…` | Single trip update, with `trip_short_name` fallback for daily-rolled IDs. |
| GET    | `/realtime/vehicle-positions?source=…` | All vehicle positions.                                                |
| GET    | `/realtime/alerts?source=…&lang=fr` | All service alerts, with `TranslatedString` resolved for the request locale. |
| GET    | `/realtime/shapes?source=…`         | Realtime-only shapes (detours not in static GTFS). Often empty.          |
| GET    | `/realtime/feed?source=…&type=…&lang=fr` | Full `RealtimeFeed` (header + every entity kind) in one round-trip.   |

`type` accepts `trip-updates` (default), `vehicle-positions`, `service-alerts` (alias `alerts`).

### Locale resolution

`TranslatedString` payloads ship the resolved-for-locale text **plus** the full translations dict. Locale is resolved in this order:

1. `?lang=fr` query parameter (or `fr-FR`).
2. First tag of the `Accept-Language` HTTP header.
3. Fallback: `en`.

## Quick Start

### Local dev

```sh
git clone https://github.com/RailMapiOS/RailMapAPI.git
cd RailMapAPI
cp .env.example .env

# Generate an API token
echo "API_AUTH_TOKENS=$(openssl rand -base64 32)" >> .env

swift run App serve --hostname 0.0.0.0 --port 8080
```

### Docker

```sh
docker compose build
docker compose up app
```

Then hit it:

```sh
TOKEN=$(grep ^API_AUTH_TOKENS= .env | head -1 | cut -d= -f2-)
curl -H "Authorization: Bearer $TOKEN" http://localhost:8080/sources | jq
curl -H "Authorization: Bearer $TOKEN" "http://localhost:8080/realtime/alerts?source=sncf-tgv&lang=fr" | jq
```

## Configuration

Environment variables are read from `.env` (see `.env.example`):

| Variable           | Required | Description                                                                 |
|--------------------|----------|-----------------------------------------------------------------------------|
| `API_AUTH_TOKENS`  | Yes      | Comma-separated list of valid Bearer tokens. Multiple tokens enable zero-downtime rotation. |
| `LOG_LEVEL`        | No       | Vapor log level (`trace`, `debug`, `info`, `notice`, `warning`, `error`). Defaults to `debug`. |

If `API_AUTH_TOKENS` is empty or unset, the API **refuses all traffic** (fail-closed) so an unauthenticated server can never accidentally ship.

## Authentication

Every request (except `/hello`) must carry a `Bearer` token:

```
Authorization: Bearer <token>
```

Tokens are compared in **constant time** against the allowlist to avoid timing-attack leaks. To rotate:

1. Add the new token to `API_AUTH_TOKENS` (comma-separated) and redeploy.
2. Ship a new client build that uses the new token.
3. Remove the old token from `API_AUTH_TOKENS` and redeploy.

Generate tokens with `openssl rand -base64 32` or `uuidgen`.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                       Vapor App                         │
│                                                         │
│   /stop, /train, /sources              /realtime/*      │
│        │                                    │           │
│   ┌────▼─────────┐                ┌─────────▼────────┐  │
│   │  FeedManager │                │ RealtimeManager  │  │
│   │  (cache GTFS)│                │ (cache GTFS-RT)  │  │
│   └────┬─────────┘                └─────────┬────────┘  │
│        │                                    │           │
│        └─────────────┬──────────────────────┘           │
│                      │                                  │
│              ┌───────▼────────┐                         │
│              │  LocomoSwift   │  (Swift package)        │
│              │ GTFS + GTFS-RT │                         │
│              └───────┬────────┘                         │
└──────────────────────┼──────────────────────────────────┘
                       │
              ┌────────▼────────┐
              │ DataSourceRegistry: SNCF, SBB, TaM, …
              └─────────────────┘
```

- **`FeedManager`** — Coalesces concurrent requests for the same static feed; persists parsed GTFS records in SQLite via Fluent migrations.
- **`RealtimeManager`** — Decodes protobuf payloads with the configured `FeedMessageDecoding`, caches by `(source, feedType)` with the source's `realtimeCacheTTL`.
- **`DataSourceRegistry`** — Holds the catalogue of operators. Defaults ship from LocomoSwift (`DataSource.sncfTER`, `.sncfTGV`, `.sncfIntercites`, `.breizhgoTER`, `.sbb`, `.tamMontpellier`).
- **`APIKeyMiddleware`** — Bearer-token gate on every non-public route.
- **`ShapeFallbackProvider`** — When a trip has no GTFS shape, queries OSRM (signal.eu.org) and Overpass to synthesize a realistic polyline.

### Adding a new DataSource

DataSources are defined in LocomoSwift, but you can register custom ones at startup. Edit `Sources/App/configure.swift`:

```swift
let myOperator = DataSource(
    identifier: "my-operator",
    displayName: "My Operator",
    staticFeedURL: URL(string: "https://example.com/gtfs.zip"),
    staticRefreshInterval: 86_400,
    realtimeFeeds: [
        .tripUpdates: URL(string: "https://example.com/rt/trip-updates.pb")!
    ],
    authentication: .bearerToken("…"),
    realtimeCacheTTL: 60
)

let registry = DataSourceRegistry(sources: DataSourceRegistry.default.allSources + [myOperator])
```

See LocomoSwift's [DataSourceConfiguration](https://swiftpackageindex.com/RailMapiOS/LocomoSwift/documentation/locomoswiftgtfs) docs for authentication helpers and refresh strategies.

## Deployment

### Docker (recommended)

The shipped `Dockerfile` is a multi-stage build:

- **Build stage** — `swift:6.2-jammy`, statically links the Swift runtime, links jemalloc.
- **Runtime stage** — `ubuntu:jammy` with `libcurl4` (required by `FoundationNetworking` for GTFS-RT fetches), runs as non-root `vapor` user.

Both x86_64 and ARM64 are supported natively — no QEMU emulation needed.

### docker-compose

`docker-compose.yml` reads `.env`, fails fast if `API_AUTH_TOKENS` is missing, and serves on port `8080`.

```sh
docker compose build && docker compose up -d app
```

For production, terminate TLS with a reverse proxy (Caddy, nginx, Traefik) in front of port `8080`.

## Documentation

- **DocC** — `Sources/App/App.docc/` — open in Xcode (Product → Build Documentation) or browse online via [Swift Package Index](https://swiftpackageindex.com).
- **OpenAPI** — see `Sources/App/App.docc/Resources/openapi.yaml` (if present).
- **LocomoSwift** — Underlying GTFS/GTFS-RT package: [docs](https://swiftpackageindex.com/RailMapiOS/LocomoSwift/documentation/locomoswift).

## Stack

- **Swift** 6.2 with strict concurrency
- **Vapor** 4
- **Fluent** + **FluentSQLite** (persistent feed cache)
- **LocomoSwift** ≥ 1.3.1 (GTFS Static + GTFS-RT v2.0 parser)
- **SwiftProtobuf** (realtime decoding)
- **ZIPFoundation** (GTFS ZIP extraction)
- **swift-nio** (custom executors)

## License

MIT.
