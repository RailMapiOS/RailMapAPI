//
//  RealtimeRoutes.swift
//  RailMapAPI
//
//  Created by RailMapAPI on 2024.
//

import Vapor
import LocomoSwift

/// Registers GTFS Realtime routes on the Vapor application.
func realtimeRoutes(_ app: Application, realtimeManager: RealtimeManager) {
    let realtime = app.grouped("realtime")

    // GET /realtime/trip-updates?source=sncf
    realtime.get("trip-updates") { req async throws -> TripUpdatesResponse in
        let source = parseSource(req)

        let updates = try await realtimeManager.fetchTripUpdates(from: source)

        return TripUpdatesResponse(
            source: sourceLabel(source),
            tripUpdates: updates.map { TripUpdateDTO(from: $0) }
        )
    }

    // GET /realtime/trip-updates/:tripID?source=sncf
    realtime.get("trip-updates", ":tripID") { req async throws -> TripUpdateDTO in
        let source = parseSource(req)

        guard let tripID = req.parameters.get("tripID") else {
            throw Abort(.badRequest, reason: "tripID manquant")
        }

        let updates = try await realtimeManager.fetchTripUpdates(from: source)
        guard let update = updates.first(where: { $0.tripID == tripID }) else {
            throw Abort(.notFound, reason: "Aucune mise à jour temps réel pour le trip \(tripID)")
        }

        return TripUpdateDTO(from: update)
    }

    // GET /realtime/vehicle-positions?source=sncf
    realtime.get("vehicle-positions") { req async throws -> VehiclePositionsResponse in
        let source = parseSource(req)

        let positions = try await realtimeManager.fetchVehiclePositions(from: source)

        return VehiclePositionsResponse(
            source: sourceLabel(source),
            vehiclePositions: positions.map { VehiclePositionDTO(from: $0) }
        )
    }

    // GET /realtime/alerts?source=sncf
    realtime.get("alerts") { req async throws -> AlertsResponse in
        let source = parseSource(req)

        let alerts = try await realtimeManager.fetchServiceAlerts(from: source)

        return AlertsResponse(
            source: sourceLabel(source),
            alerts: alerts.map { AlertDTO(from: $0) }
        )
    }
}

// MARK: - Helpers

private func parseSource(_ req: Request) -> DataSource {
    let sourceParam = req.query[String.self, at: "source"]
    switch sourceParam?.lowercased() {
    case "tam", "montpellier":
        return .TaM_Montpellier
    default:
        return .sncf
    }
}

private func sourceLabel(_ source: DataSource) -> String {
    switch source {
    case .sncf: return "sncf"
    case .TaM_Montpellier: return "tam_montpellier"
    case .custom(let url): return url.absoluteString
    }
}
