# Adding a Data Source

Register a new transit operator at startup.

## Overview

Data sources are defined as `DataSource` values in [LocomoSwift](https://swiftpackageindex.com/RailMapiOS/LocomoSwift). Six presets ship out of the box (`sncfTER`, `sncfTGV`, `sncfIntercites`, `breizhgoTER`, `sbb`, `tamMontpellier`). To add your own, build a `DataSource` and inject it into the `DataSourceRegistry` used by `configure(_:)`.

## Building a DataSource

```swift
import LocomoSwift

let myOperator = DataSource(
    identifier: "my-operator",
    displayName: "My Operator",
    staticFeedURL: URL(string: "https://example.com/gtfs.zip"),
    staticRefreshInterval: 86_400,            // 24h
    realtimeFeeds: [
        .tripUpdates:      URL(string: "https://example.com/rt/trip-updates.pb")!,
        .vehiclePositions: URL(string: "https://example.com/rt/vehicle-positions.pb")!,
        .serviceAlerts:    URL(string: "https://example.com/rt/alerts.pb")!,
    ],
    realtimeCacheTTL: 60                       // seconds
)
```

`identifier` is what clients pass via `?source=`. Keep it lowercase and hyphenated.

## Authentication

If the upstream feed needs an API key, attach it with ``DataSource/withAuthentication(_:)``:

```swift
let secured = DataSource.sbb.withAuthentication(
    .queryParam(name: "api_key", value: ProcessInfo.processInfo.environment["SBB_KEY"] ?? "")
)
```

Supported strategies (from LocomoSwift's `Authentication`):

- `.queryParam(name:value:)` — Appends `?name=value` to every fetch.
- `.header(name:value:)` — Adds an HTTP header.
- `.bearerToken(_:)` — Convenience for `Authorization: Bearer …`.

Read keys from environment variables — never commit them.

## Registering at startup

Edit `Sources/App/configure.swift`:

```swift
public func configure(_ app: Application) async throws {
    // ... existing migrations ...

    let myOperator = DataSource(
        identifier: "my-operator",
        displayName: "My Operator",
        staticFeedURL: URL(string: "https://example.com/gtfs.zip"),
        staticRefreshInterval: 86_400,
        realtimeFeeds: [.tripUpdates: URL(string: "https://example.com/rt.pb")!],
        realtimeCacheTTL: 60
    )

    let registry = DataSourceRegistry(
        sources: DataSourceRegistry.default.allSources + [myOperator]
    )

    let feedManager = FeedManager()
    let realtimeManager = RealtimeManager()

    try routes(app, feedManager: feedManager, realtimeManager: realtimeManager, registry: registry)
}
```

## Verifying

After redeploying:

```sh
TOKEN=$(grep ^API_AUTH_TOKENS= .env | head -1 | cut -d= -f2-)

# Source should appear here
curl -H "Authorization: Bearer $TOKEN" $API/sources | jq '.sources[] | .identifier'

# Realtime should respond
curl -H "Authorization: Bearer $TOKEN" "$API/realtime/trip-updates?source=my-operator" | jq
```

## When not to add a source here

If your operator is widely used and well-documented, contribute it as a **preset** to LocomoSwift instead — every consumer of the library benefits. Submit a PR adding a `public static let` to `DataSource+Presets.swift`.

Local-only or auth-restricted sources stay in this app's `configure.swift`.
