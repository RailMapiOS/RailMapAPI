# Realtime Endpoints

Routes serving the GTFS-RT v2.0 schema — trip updates, vehicle positions, alerts, and shapes.

## Overview

Every realtime endpoint accepts:

- `?source=<id>` — Required. Must reference a DataSource with at least one realtime feed.
- `?lang=<tag>` — Optional. Resolves `TranslatedString` payloads. See <doc:LocaleResolution>.

Responses ship the **full GTFS-RT v2.0 schema** — translated text, multi-carriage details, severity levels, modified-trip selectors. Older flat fields (`tripID`, `vehicleID`, `headerText`) are kept alongside the richer nested objects for backward compatibility.

All routes require `Authorization: Bearer <token>`. See <doc:Authentication>.

## GET /realtime/sources

Lists sources that have at least one realtime feed configured, with the available feed types.

```json
{
  "sources": [
    {
      "identifier": "tam-montpellier",
      "displayName": "TaM Montpellier",
      "availableFeeds": ["serviceAlerts", "tripUpdates", "vehiclePositions"]
    }
  ]
}
```

## GET /realtime/trip-updates

All trip updates for the source, in their RT-published order.

```json
{
  "source": "sncf-ter",
  "tripUpdates": [
    {
      "tripID": "OCESN001234F0123…",
      "routeID": "OCE:SN:001",
      "delay": 120,
      "trip": { "tripID": "…", "scheduleRelationship": "scheduled" },
      "vehicle": { "id": "ICE-407", "label": "TGV INOUI" },
      "stopTimeUpdates": [
        {
          "stopID": "StopPoint:OCETrain:87113001",
          "stopSequence": 4,
          "arrivalDelay": 60,
          "arrival": { "delay": 60, "time": 1715000000 },
          "departureDelay": 60,
          "platform": "5"
        }
      ]
    }
  ]
}
```

## GET /realtime/trip-updates/:tripID

Single trip update with a two-step lookup:

1. **Exact match** on the requested `tripID`.
2. **Fallback by `trip_short_name`** — When operators (notably SNCF TER) roll their RT `tripID`s daily, we extract the train number from the static feed and find any RT update carrying the same train number.

Returns `404` if neither step finds a match.

## GET /realtime/vehicle-positions

```json
{
  "source": "tam-montpellier",
  "vehiclePositions": [
    {
      "vehicleID": "1234",
      "tripID": "T-456",
      "latitude": 43.6,
      "longitude": 3.87,
      "bearing": 90,
      "speed": 8.3,
      "vehicle": { "id": "1234", "label": "Tram 4" },
      "occupancyStatus": "fewSeatsAvailable",
      "congestionLevel": "runningSmoothly",
      "multiCarriageDetails": [/* per-carriage breakdown when published */]
    }
  ]
}
```

## GET /realtime/alerts

Service alerts with translations resolved for the request locale (see <doc:LocaleResolution>).

```json
{
  "source": "sncf-tgv",
  "alerts": [
    {
      "headerText": "Travaux en gare",
      "headerTextTranslated": {
        "text": "Travaux en gare",
        "translations": { "fr": "Travaux en gare", "en": "Station works" }
      },
      "descriptionText": "…",
      "cause": "construction",
      "effect": "detour",
      "severityLevel": 2,
      "informedEntities": [/* GTFS-RT EntitySelector */]
    }
  ]
}
```

`severityLevel` maps to GTFS-RT severity: `0` unknown, `1` info, `2` warning, `3` severe.

## GET /realtime/shapes

Realtime-only shapes — encoded polylines for detours that aren't in the static GTFS. Most operators don't publish these, so the response is typically an empty array.

```json
{ "source": "sncf-ter", "shapes": [] }
```

## GET /realtime/feed

Returns the **entire `RealtimeFeed`** — header plus every entity kind — in one round-trip. Useful when a client needs the full picture for one feed type without making N separate calls.

**Query:**

- `?source=<id>` — Required.
- `?type=<feed-type>` — One of `trip-updates` (default), `vehicle-positions`, `service-alerts` (alias `alerts`).
- `?lang=<tag>` — Optional locale.

**Response:**

```json
{
  "source": "sncf-ter",
  "feedType": "Trip Updates",
  "header": {
    "gtfsRealtimeVersion": "2.0",
    "incrementality": "fullDataset",
    "timestamp": 1715000000
  },
  "tripUpdates": [/* … */],
  "vehiclePositions": [/* … */],
  "serviceAlerts": [/* … */],
  "shapes": [/* … */],
  "deletedEntityIDs": []
}
```

> Tip: SNCF still publishes GTFS-RT **v1.0**, so v2.0-only fields (multi-carriage, severity, modified-trip selectors) appear `null` for SNCF feeds. This is expected — the API exposes the full v2.0 schema; what's `null` is what the upstream source doesn't publish yet.
