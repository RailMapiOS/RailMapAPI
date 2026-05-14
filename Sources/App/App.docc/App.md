# ``App``

Backend HTTP service that aggregates GTFS Static and GTFS Realtime v2.0 feeds from European transit operators.

## Overview

RailMapAPI is a [Vapor 4](https://vapor.codes) application that powers the [RailMap iOS app](https://github.com/RailMapiOS). It exposes a unified JSON API over multiple transit operators (SNCF, SBB, TaM Montpellier, …), caches their static GTFS catalogues in SQLite, and decodes realtime protobuf payloads on the fly.

The heavy lifting — CSV parsing, ZIP extraction, protobuf decoding, locale resolution — lives in [LocomoSwift](https://swiftpackageindex.com/RailMapiOS/LocomoSwift). RailMapAPI focuses on:

- **HTTP routing & DTOs** — Maps LocomoSwift's domain types to JSON shapes the iOS client can consume directly.
- **Cache coordination** — `FeedManager` deduplicates concurrent static-feed fetches; `RealtimeManager` caches RT decodings per `(source, feedType)`.
- **Authentication** — Bearer-token middleware with constant-time comparison and zero-downtime rotation support.
- **Shape synthesis** — Falls back from GTFS `shapes.txt` to OSRM and Overpass when a trip has no native polyline.

## Topics

### Getting Started

- <doc:GettingStarted>
- <doc:Configuration>

### Endpoints

- <doc:Endpoints>
- <doc:RealtimeEndpoints>
- <doc:LocaleResolution>

### Operations

- <doc:Authentication>
- <doc:Deployment>
- <doc:AddingADataSource>
