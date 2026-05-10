//
//  RealtimeRoutes.swift
//  RailMapAPI
//
//  Created by RailMapAPI on 2024.
//

import Vapor
import LocomoSwift

/// Registers GTFS Realtime routes on the given builder. We accept any
/// `RoutesBuilder` (instead of `Application`) so the caller can attach
/// middleware (e.g. `APIKeyMiddleware`) before passing the group in.
func realtimeRoutes(_ routes: any RoutesBuilder, feedManager: FeedManager, realtimeManager: RealtimeManager, registry: DataSourceRegistry) {
    let realtime = routes.grouped("realtime")

    // GET /realtime/trip-updates?source=sncf-ter
    realtime.get("trip-updates") { req async throws -> TripUpdatesResponse in
        let source = try resolveSource(req, registry: registry)

        async let updatesTask = realtimeManager.fetchTripUpdates(from: source)
        async let feedTask: Feed? = source.hasStaticFeed
            ? (try? await feedManager.getFeed(for: source, on: req.db))
            : nil
        let (updates, feed) = try await (updatesTask, feedTask)
        let resolver = platformResolver(feed: feed)

        return TripUpdatesResponse(
            source: source.identifier,
            tripUpdates: updates.map { TripUpdateDTO(from: $0, platformResolver: resolver) }
        )
    }

    // GET /realtime/trip-updates/:tripID?source=sncf-ter
    //
    // Two-step matching to handle SNCF TER (and other operators) that publish
    // RT updates with daily-rolled tripIDs different from the static GTFS
    // tripIDs we know:
    //   1. Exact match on the requested tripID.
    //   2. Fallback: extract `trip_short_name` (= train number) from the
    //      static feed for our tripID, then find any RT update whose static
    //      counterpart carries the same `trip_short_name`.
    realtime.get("trip-updates", ":tripID") { req async throws -> TripUpdateDTO in
        let source = try resolveSource(req, registry: registry)

        guard let tripID = req.parameters.get("tripID") else {
            throw Abort(.badRequest, reason: "tripID manquant")
        }

        async let updatesTask = realtimeManager.fetchTripUpdates(from: source)
        async let feedTask: Feed? = source.hasStaticFeed
            ? (try? await feedManager.getFeed(for: source, on: req.db))
            : nil
        let (updates, feed) = try await (updatesTask, feedTask)
        let resolver = platformResolver(feed: feed)

        // 1) Exact match
        if let exact = updates.first(where: { $0.tripID == tripID }) {
            return TripUpdateDTO(from: exact, platformResolver: resolver)
        }

        // 2) Fallback by `trip_short_name`
        if let feed,
           let staticTrips = feed.trips?.trips,
           let staticTrip = staticTrips.first(where: { $0.tripID == tripID }),
           let trainNumber = staticTrip.shortName,
           !trainNumber.isEmpty {
            let tripsByID = Dictionary(
                uniqueKeysWithValues: staticTrips.map { ($0.tripID, $0) }
            )
            if let fallback = updates.first(where: { rt in
                guard let id = rt.tripID else { return false }
                return tripsByID[id]?.shortName == trainNumber
            }) {
                req.logger.info("[trip-updates] Fallback match: \(tripID) → \(fallback.tripID ?? "?") via trip_short_name=\(trainNumber)")
                return TripUpdateDTO(from: fallback, platformResolver: resolver)
            }
        }

        throw Abort(.notFound, reason: "Aucune mise à jour temps réel pour le trip \(tripID)")
    }

    // GET /realtime/vehicle-positions?source=tam-montpellier
    realtime.get("vehicle-positions") { req async throws -> VehiclePositionsResponse in
        let source = try resolveSource(req, registry: registry)

        let positions = try await realtimeManager.fetchVehiclePositions(from: source)

        return VehiclePositionsResponse(
            source: source.identifier,
            vehiclePositions: positions.map { VehiclePositionDTO(from: $0) }
        )
    }

    // GET /realtime/alerts?source=sncf-tgv
    realtime.get("alerts") { req async throws -> AlertsResponse in
        let source = try resolveSource(req, registry: registry)

        let alerts = try await realtimeManager.fetchServiceAlerts(from: source)

        return AlertsResponse(
            source: source.identifier,
            alerts: alerts.map { AlertDTO(from: $0) }
        )
    }

    // GET /realtime/sources — Liste les sources qui ont des feeds RT disponibles
    realtime.get("sources") { req async throws -> SourcesResponse in
        let rtSources = registry.allSources
            .filter { !$0.realtimeFeeds.isEmpty }
            .map { source in
                SourceInfo(
                    identifier: source.identifier,
                    displayName: source.displayName,
                    availableFeeds: source.availableRealtimeFeedTypes.map(\.description).sorted()
                )
            }
            .sorted { $0.identifier < $1.identifier }

        return SourcesResponse(sources: rtSources)
    }
}

// MARK: - Helpers

/// Builds a closure that returns the static `platform_code` for any GTFS
/// stop ID — used to enrich `StopTimeUpdateDTO` with the announced platform.
///
/// SNCF (and most operators) don't publish a dedicated `platform` field in
/// GTFS-RT. They redirect `stop_id` from the parent `stop_area` to a child
/// stop carrying the platform_code. So a lookup by RT `stopID` against the
/// static stops table reveals the announced platform when one exists.
private func platformResolver(feed: Feed?) -> (String) -> String? {
    guard let stops = feed?.stops?.stops else { return { _ in nil } }
    let byID = Dictionary(
        stops.compactMap { stop -> (String, String)? in
            guard let code = stop.platformCode, !code.isEmpty else { return nil }
            return (stop.stopID, code)
        },
        uniquingKeysWith: { first, _ in first }
    )
    return { stopID in byID[stopID] }
}

/// Résout la DataSource depuis le query param `?source=`
private func resolveSource(_ req: Request, registry: DataSourceRegistry) throws -> DataSource {
    let sourceParam = req.query[String.self, at: "source"] ?? "sncf-ter"

    guard let source = registry.source(for: sourceParam) else {
        let available = registry.allSources
            .filter { !$0.realtimeFeeds.isEmpty }
            .map(\.identifier)
            .sorted()
        throw Abort(.badRequest, reason: "Source '\(sourceParam)' inconnue. Sources disponibles: \(available.joined(separator: ", "))")
    }

    guard !source.realtimeFeeds.isEmpty else {
        throw Abort(.badRequest, reason: "Source '\(sourceParam)' n'a pas de feeds Realtime configurés")
    }

    return source
}

// MARK: - Sources endpoint DTOs

struct SourcesResponse: Content {
    let sources: [SourceInfo]
}

struct SourceInfo: Content {
    let identifier: String
    let displayName: String
    let availableFeeds: [String]
}
