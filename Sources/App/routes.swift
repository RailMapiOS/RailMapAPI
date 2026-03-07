import Vapor
import LocomoSwift

func routes(_ app: Application) throws {
    let journeyStation = JourneyStation()
    let feedManager = FeedManager(database: app.db)

    app.get("stop", ":headsign") { req async throws -> VehicleJourneys in
        guard let headsign = req.parameters.get("headsign") else {
            throw Abort(.badRequest, reason: "Headsign manquant")
        }

        let agencyParam = req.query[String.self, at: "agency"]
        let serviceTypeParam = req.query[String.self, at: "serviceType"]

        guard let agency = agencyParam.flatMap({ Agencies(rawValue: $0) }),
              let serviceType = serviceTypeParam.flatMap({ ServiceType(rawValue: $0) }) else {
            throw Abort(.badRequest, reason: "Agency ou ServiceType manquant ou invalide")
        }

        guard let endpoint = gtfsEndpoints.first(where: { $0.agency == agency && $0.serviceType == serviceType }) else {
            throw Abort(.notFound, reason: "Endpoint GTFS non trouvé pour l'agence \(agency) et le service \(serviceType)")
        }

        // Check journey cache
        if let cachedJourneys = await journeyStation.getJourneys(for: .headsign(headsign)) {
            return cachedJourneys
        }

        let feed = try await feedManager.getFeed(for: endpoint, logger: req.logger)

        let trips = feed.trips?.filter { $0.headSign == headsign } ?? []
        if trips.isEmpty {
            throw Abort(.notFound, reason: "Aucun trajet trouvé pour le headsign \(headsign)")
        }

        guard let agencies = feed.agencies else {
            throw Abort(.internalServerError, reason: "Les agences sont manquantes dans le feed GTFS.")
        }

        let calendarDates = feed.calendarDates?.dates ?? []

        // Build stop lookup dictionary once - O(n) instead of O(n*m) per stop time
        let stopLookup = buildStopLookup(from: feed)
        let agencyTimezone = feed.agencies?.first?.timeZone ?? TimeZone(secondsFromGMT: 0)!

        let vehicleJourneys = trips.map { trip in
            VehicleJourneyHelper.createVehicleJourney(
                from: trip,
                feed: feed,
                calendarDates: calendarDates,
                stopLookup: stopLookup,
                agencyTimezone: agencyTimezone
            )
        }

        let fullVehicleJourneys = VehicleJourneyHelper.createVehicleJourneys(from: vehicleJourneys, agencies: agencies)

        await journeyStation.addJourneys(fullVehicleJourneys, for: .headsign(headsign))
        req.logger.info("Returned \(vehicleJourneys.count) journeys for headsign '\(headsign)'")

        return fullVehicleJourneys
    }

    app.get("hello") { req async -> String in
        "Hello, world!"
    }
}

/// Build a dictionary for O(1) stop lookups by stopID.
private func buildStopLookup(from feed: Feed) -> [String: Stop] {
    guard let stops = feed.stops else { return [:] }
    var lookup = [String: Stop](minimumCapacity: stops.stops.count)
    for stop in stops {
        lookup[stop.stopID] = stop
    }
    return lookup
}
