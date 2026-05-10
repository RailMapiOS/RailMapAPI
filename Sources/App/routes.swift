import Vapor
import Foundation
import LocomoSwift

func routes(_ app: Application, feedManager: FeedManager, realtimeManager: RealtimeManager, registry: DataSourceRegistry) throws {
    // Public health-check — kept open so liveness probes don't need a token.
    app.get("hello") { req async -> String in
        return "Hello, world!"
    }

    // Everything else sits behind the API token middleware.
    let api = app.grouped(APIKeyMiddleware())

    // Register GTFS Realtime routes
    realtimeRoutes(api, feedManager: feedManager, realtimeManager: realtimeManager, registry: registry)

    let journeyStation = JourneyStation()
    let VJH = VehicleJourneyHelper()

    // GET /stop/:headsign?source=sncf-ter
    api.get("stop", ":headsign") { req async throws -> VehicleJourneys in
        guard let headsign = req.parameters.get("headsign") else {
            throw Abort(.badRequest, reason: "Missing headsign parameter")
        }

        // Resolve DataSource from ?source= query param
        let sourceParam = req.query[String.self, at: "source"] ?? "sncf-ter"
        guard let source = registry.source(for: sourceParam) else {
            let available = registry.allSources
                .filter { $0.hasStaticFeed }
                .map(\.identifier)
                .sorted()
            throw Abort(.badRequest, reason: "Unknown source '\(sourceParam)'. Available: \(available.joined(separator: ", "))")
        }

        guard source.hasStaticFeed else {
            throw Abort(.badRequest, reason: "Source '\(sourceParam)' has no static feed configured")
        }

        // Check journey cache
        if let cachedJourneys = journeyStation.getJourneys(for: .headsign(headsign)) {
            return cachedJourneys
        }

        // Load feed from shared FeedManager (URL-deduplicated, coalesced)
        let feed = try await feedManager.getFeed(for: source, on: req.db)

        // Filter trips by headsign
        let trips = feed.trips?.filter { $0.headSign == headsign } ?? []
        if trips.isEmpty {
            throw Abort(.notFound, reason: "No trips found for headsign '\(headsign)'")
        }

        guard let agencies = feed.agencies else {
            throw Abort(.internalServerError, reason: "Agencies missing from GTFS feed")
        }

        let calendarDates = feed.calendarDates?.dates ?? []

        let vehicleJourneys = trips.map { trip in
            VJH.createVehicleJourney(from: trip, with: feed, calendarDates: calendarDates)
        }

        let fullVehicleJourneys = VJH.createVehicleJourneys(from: vehicleJourneys, agencies: agencies)

        journeyStation.addJourneys(fullVehicleJourneys, for: .headsign(headsign))

        print("[Routes] Returning \(fullVehicleJourneys.vehicleJourneys.count) journeys for '\(headsign)'")
        return fullVehicleJourneys
    }

    // GET /train/:trainNumber?source=sncf-ter  (source optional — searches all if omitted)
    //
    // Resolves the service type of a train from its number (trip_short_name in GTFS).
    // Returns route type, agency info, headsign, and the source it was found in.
    api.get("train", ":trainNumber") { req async throws -> TrainInfoResponse in
        guard let trainNumber = req.parameters.get("trainNumber") else {
            throw Abort(.badRequest, reason: "Missing trainNumber parameter")
        }

        let sourceParam: String? = req.query[String.self, at: "source"]

        // Determine which sources to search
        let sourcesToSearch: [DataSource]
        if let sourceParam {
            guard let source = registry.source(for: sourceParam) else {
                let available = registry.allSources
                    .filter { $0.hasStaticFeed }
                    .map(\.identifier)
                    .sorted()
                throw Abort(.badRequest, reason: "Unknown source '\(sourceParam)'. Available: \(available.joined(separator: ", "))")
            }
            sourcesToSearch = [source]
        } else {
            // Search all sources that have a static feed
            sourcesToSearch = registry.allSources.filter { $0.hasStaticFeed }
        }

        // Search each source for matching trips
        var results: [TrainInfo] = []

        for source in sourcesToSearch {
            let feed: Feed
            do {
                feed = try await feedManager.getFeed(for: source, on: req.db)
            } catch {
                // Skip sources that fail to load (e.g. network issues)
                continue
            }

            // Find trips matching the train number (trip_short_name)
            let matchingTrips = feed.trips?.filter { $0.shortName == trainNumber } ?? []
            if matchingTrips.isEmpty { continue }

            // Build route lookup for this feed
            let routeLookup: [String: LocomoSwift.Route] = {
                guard let routes = feed.routes else { return [:] }
                return Dictionary(routes.map { ($0.routeID, $0) }, uniquingKeysWith: { first, _ in first })
            }()

            // Build agency lookup
            let agencyLookup: [String: LocomoSwift.Agency] = {
                guard let agencies = feed.agencies else { return [:] }
                return Dictionary(
                    agencies.compactMap { a in a.agencyID.map { ($0, a) } },
                    uniquingKeysWith: { first, _ in first }
                )
            }()

            // Deduplicate by routeID (many trips share the same route)
            var seenRouteIDs: Set<String> = []

            for trip in matchingTrips {
                guard seenRouteIDs.insert(trip.routeID).inserted else { continue }

                let route = routeLookup[trip.routeID]
                let agency = route?.agencyID.flatMap { agencyLookup[$0] }
                    ?? feed.agencies?.first

                results.append(TrainInfo(
                    trainNumber: trainNumber,
                    source: source.identifier,
                    sourceDisplayName: source.displayName,
                    tripID: trip.tripID,
                    routeID: trip.routeID,
                    routeShortName: route?.shortName,
                    routeLongName: route?.name,
                    routeType: route?.type.rawValue ?? 2,
                    routeTypeDescription: route?.type.description ?? "Rail",
                    agencyID: agency?.agencyID,
                    agencyName: agency?.name ?? "Unknown",
                    headsign: trip.headSign,
                    direction: trip.direction
                ))
            }
        }

        if results.isEmpty {
            throw Abort(.notFound, reason: "No train found with number '\(trainNumber)'")
        }

        return TrainInfoResponse(
            trainNumber: trainNumber,
            results: results
        )
    }

    // GET /train/:trainNumber/shape?source=sncf-ter
    //
    // Returns the geographic shape (polyline) for a train trip.
    // Priority: GTFS shapes.txt → signal.eu.org OSRM → Overpass API → stop-to-stop lines.
    api.get("train", ":trainNumber", "shape") { req async throws -> TrainShapeResponse in
        guard let trainNumber = req.parameters.get("trainNumber") else {
            throw Abort(.badRequest, reason: "Missing trainNumber parameter")
        }

        let sourceParam = req.query[String.self, at: "source"] ?? "sncf-ter"
        guard let source = registry.source(for: sourceParam) else {
            let available = registry.allSources
                .filter { $0.hasStaticFeed }
                .map(\.identifier)
                .sorted()
            throw Abort(.badRequest, reason: "Unknown source '\(sourceParam)'. Available: \(available.joined(separator: ", "))")
        }

        let feed = try await feedManager.getFeed(for: source, on: req.db)

        // Find the trip by train number (trip_short_name)
        guard let trip = feed.trips?.first(where: { $0.shortName == trainNumber }) else {
            throw Abort(.notFound, reason: "No trip found with train number '\(trainNumber)' in source '\(sourceParam)'")
        }

        // 1. Try GTFS shapes.txt
        if let shapeID = trip.shapeID, let shapes = feed.shapes {
            let shapePoints = shapes.pointsForShape(shapeID)
            if !shapePoints.isEmpty {
                let coordinates = shapePoints.compactMap { point -> [Double]? in
                    guard let lat = point.latitude, let lon = point.longitude else { return nil }
                    return [lon, lat]
                }
                if !coordinates.isEmpty {
                    return TrainShapeResponse(
                        trainNumber: trainNumber,
                        source: sourceParam,
                        shapeSource: "gtfs",
                        geojson: GeoJSONGeometry(type: "LineString", coordinates: coordinates)
                    )
                }
            }
        }

        // Build ordered stop coordinates for this trip
        let tripStopTimes = (feed.stopTimes?.filter { $0.tripID == trip.tripID } ?? [])
            .sorted { $0.stopSequenceNumber < $1.stopSequenceNumber }

        let stopLookup: [String: LocomoSwift.Stop] = {
            guard let stops = feed.stops else { return [:] }
            return Dictionary(
                stops.compactMap { s -> (String, LocomoSwift.Stop)? in
                    return (s.stopID, s)
                },
                uniquingKeysWith: { first, _ in first }
            )
        }()

        let stopCoordinates: [ShapeFallbackProvider.Coordinate] = tripStopTimes.compactMap { st in
            guard let stop = stopLookup[st.stopID],
                  let lat = stop.latitude,
                  let lon = stop.longitude else { return nil }
            return ShapeFallbackProvider.Coordinate(latitude: lat, longitude: lon)
        }

        guard stopCoordinates.count >= 2 else {
            throw Abort(.notFound, reason: "Not enough stop coordinates to build a shape for train '\(trainNumber)'")
        }

        // 2. Try signal.eu.org OSRM (European rail router)
        if let osrmShape = await ShapeFallbackProvider.fromSignalOSRM(stops: stopCoordinates, client: req.client) {
            return TrainShapeResponse(
                trainNumber: trainNumber,
                source: sourceParam,
                shapeSource: "signal-osrm",
                geojson: osrmShape
            )
        }

        // 3. Try Overpass API (OpenStreetMap railway data)
        if let overpassShape = await ShapeFallbackProvider.fromOverpass(stops: stopCoordinates, client: req.client) {
            return TrainShapeResponse(
                trainNumber: trainNumber,
                source: sourceParam,
                shapeSource: "overpass",
                geojson: overpassShape
            )
        }

        // 4. Fallback: straight lines between stops
        return TrainShapeResponse(
            trainNumber: trainNumber,
            source: sourceParam,
            shapeSource: "stops-only",
            geojson: ShapeFallbackProvider.fromStops(stopCoordinates)
        )
    }

    // GET /sources — List all available data sources
    api.get("sources") { req async throws -> AllSourcesResponse in
        let sources = registry.allSources.map { source in
            DataSourceInfo(
                identifier: source.identifier,
                displayName: source.displayName,
                hasStaticFeed: source.hasStaticFeed,
                staticRefreshInterval: source.staticRefreshInterval,
                availableRealtimeFeeds: source.availableRealtimeFeedTypes.map(\.description).sorted(),
                realtimeCacheTTL: source.realtimeCacheTTL
            )
        }.sorted { $0.identifier < $1.identifier }

        return AllSourcesResponse(sources: sources)
    }

}

// MARK: - DTOs

struct AllSourcesResponse: Content {
    let sources: [DataSourceInfo]
}

struct DataSourceInfo: Content {
    let identifier: String
    let displayName: String
    let hasStaticFeed: Bool
    let staticRefreshInterval: TimeInterval
    let availableRealtimeFeeds: [String]
    let realtimeCacheTTL: TimeInterval
}

// MARK: - Train Info DTOs

struct TrainInfoResponse: Content {
    let trainNumber: String
    let results: [TrainInfo]
}

struct TrainInfo: Content {
    /// The train number queried (trip_short_name)
    let trainNumber: String
    /// DataSource identifier where this train was found
    let source: String
    /// Human-readable source name
    let sourceDisplayName: String
    /// GTFS trip ID (one representative trip)
    let tripID: String
    /// GTFS route ID
    let routeID: String
    /// Route short name (e.g. "TER", "TGV", "IC")
    let routeShortName: String?
    /// Route long name
    let routeLongName: String?
    /// GTFS route_type as raw integer
    let routeType: UInt
    /// Human-readable route type description
    let routeTypeDescription: String
    /// Agency ID
    let agencyID: String?
    /// Agency name (e.g. "SNCF", "SBB CFF FFS")
    let agencyName: String
    /// Trip headsign (destination)
    let headsign: String?
    /// Direction ID
    let direction: String?

    enum CodingKeys: String, CodingKey {
        case trainNumber = "train_number"
        case source
        case sourceDisplayName = "source_display_name"
        case tripID = "trip_id"
        case routeID = "route_id"
        case routeShortName = "route_short_name"
        case routeLongName = "route_long_name"
        case routeType = "route_type"
        case routeTypeDescription = "route_type_description"
        case agencyID = "agency_id"
        case agencyName = "agency_name"
        case headsign
        case direction
    }
}

// MARK: - Train Shape DTOs

struct TrainShapeResponse: Content {
    /// The train number queried
    let trainNumber: String
    /// DataSource identifier
    let source: String
    /// Where the shape data came from: "gtfs", "signal-osrm", "overpass", or "stops-only"
    let shapeSource: String
    /// GeoJSON geometry for the train route
    let geojson: GeoJSONGeometry

    enum CodingKeys: String, CodingKey {
        case trainNumber = "train_number"
        case source
        case shapeSource = "shape_source"
        case geojson
    }
}

struct GeoJSONGeometry: Content {
    /// GeoJSON geometry type ("LineString")
    let type: String
    /// Array of [longitude, latitude] coordinate pairs
    let coordinates: [[Double]]
}
