# Getting Started

Run the API locally and make your first authenticated request.

## Overview

RailMapAPI ships as a Vapor executable. You can run it directly with `swift run` for development, or via Docker for production-like environments.

## Prerequisites

- **Swift 6.2** (macOS) or **Docker** (any platform).
- An auth token. Generate one with `openssl rand -base64 32` or `uuidgen`.

## Configure

Copy the env template and add your token:

```sh
cp .env.example .env
echo "API_AUTH_TOKENS=$(openssl rand -base64 32)" >> .env
```

Multiple tokens are allowed (comma-separated) for zero-downtime rotation. See <doc:Authentication> for details.

## Run locally

```sh
swift run App serve --hostname 0.0.0.0 --port 8080
```

The first request to a given source will download and cache its GTFS Static feed in `db.sqlite` — expect a few seconds of latency on cold start.

## Run with Docker

```sh
docker compose build
docker compose up app
```

Compose reads `.env` at start time and refuses to launch if `API_AUTH_TOKENS` is unset.

## Make your first request

Health check (no auth):

```sh
curl http://localhost:8080/hello
```

List configured sources:

```sh
TOKEN=$(grep ^API_AUTH_TOKENS= .env | head -1 | cut -d= -f2-)
curl -H "Authorization: Bearer $TOKEN" http://localhost:8080/sources | jq
```

Fetch realtime trip updates from SNCF TER:

```sh
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8080/realtime/trip-updates?source=sncf-ter" | jq
```

Fetch service alerts in French:

```sh
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8080/realtime/alerts?source=sncf-tgv&lang=fr" | jq
```

## Next steps

- Browse every endpoint: <doc:Endpoints>, <doc:RealtimeEndpoints>.
- Learn how locale resolution works: <doc:LocaleResolution>.
- Register your own operator: <doc:AddingADataSource>.
