# Static GTFS Endpoints

Routes serving static GTFS data — agencies, routes, trips, shapes.

## Overview

Every endpoint accepts a `?source=<identifier>` query parameter to pick a DataSource. When omitted, most endpoints default to `sncf-ter`. The exception is `/train/:trainNumber`, which searches every configured source if no `source` is given.

All routes (except `/hello`) require `Authorization: Bearer <token>`. See <doc:Authentication>.

## GET /hello

Public liveness probe. Returns `Hello, world!`. Useful for container health checks (no token needed).

## GET /sources

Lists every configured DataSource — both static and realtime — with metadata.

```json
{
  "sources": [
    {
      "identifier": "sncf-ter",
      "displayName": "SNCF TER",
      "hasStaticFeed": true,
      "staticRefreshInterval": 86400,
      "availableRealtimeFeeds": ["serviceAlerts", "tripUpdates"],
      "realtimeCacheTTL": 120
    }
  ]
}
```

## GET /stop/:headsign

Returns every vehicle journey serving the given headsign for the requested source.

**Query:** `?source=<id>` (default `sncf-ter`).

**Response:** `VehicleJourneys` — a list of journeys with their stop sequence, calendar dates, and agency info. Cached in-memory per `(source, headsign)` for the lifetime of the process.

**Errors:**

- `400` — Unknown or static-less source.
- `404` — No trips match the headsign.

## GET /train/:trainNumber

Resolves a train number (`trip_short_name`) to its route, agency, and headsign. If `source` is omitted, every source with a static feed is searched in parallel.

**Query:** `?source=<id>` (optional).

**Response:**

```json
{
  "train_number": "8501",
  "results": [
    {
      "train_number": "8501",
      "source": "sncf-ter",
      "source_display_name": "SNCF TER",
      "trip_id": "OCESN001234F0123…",
      "route_id": "OCE:SN:001",
      "route_short_name": "TER",
      "route_long_name": "Paris ↔ Bourges",
      "route_type": 2,
      "route_type_description": "Rail",
      "agency_id": "OCE:SA:000",
      "agency_name": "SNCF",
      "headsign": "Bourges",
      "direction": "0"
    }
  ]
}
```

Multiple results can come back when several operators publish the same train number (e.g. cross-border services).

**Errors:**

- `400` — `source` provided but unknown.
- `404` — No trip matches the number across the searched sources.

## GET /train/:trainNumber/shape

Returns a GeoJSON `LineString` for the train's geographic route, with a 4-tier fallback:

1. **GTFS `shapes.txt`** — When the static feed publishes one. `shape_source` is `"gtfs"`.
2. **signal.eu.org OSRM** — European rail-aware router. `shape_source` is `"signal-osrm"`.
3. **Overpass API** — OpenStreetMap railway data. `shape_source` is `"overpass"`.
4. **Stop-to-stop straight lines** — Always available. `shape_source` is `"stops-only"`.

**Query:** `?source=<id>` (default `sncf-ter`).

**Response:**

```json
{
  "train_number": "8501",
  "source": "sncf-ter",
  "shape_source": "gtfs",
  "geojson": {
    "type": "LineString",
    "coordinates": [[2.3522, 48.8566], [2.3, 47.0]]
  }
}
```

Coordinates are `[longitude, latitude]` per GeoJSON convention.

**Errors:**

- `404` — Trip not found, or fewer than 2 stops have coordinates.
