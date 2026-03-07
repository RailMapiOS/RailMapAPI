import Fluent
import Vapor
import LocomoSwift

/// App-scoped feed manager that persists across requests so in-memory cache actually works.
final class FeedManager: Sendable {
    private let cache = FeedCache()
    private let db: any Database

    init(database: any Database) {
        self.db = database
    }

    func getFeed(for endpoint: GTFSEndpoint, logger: Logger) async throws -> Feed {
        // Check in-memory cache
        if let cached = await cache.get(endpoint),
           isFeedStillValid(cached.lastUpdate, refreshFrequency: endpoint.refreshFrequency) {
            logger.info("Feed cache hit for \(endpoint.agency.rawValue)/\(endpoint.serviceType.rawValue)")
            return cached.feed
        }

        // Check database
        if let storedFeed = try await loadFeedFromDB(endpoint: endpoint) {
            await cache.set(endpoint, feed: storedFeed)
            logger.info("Feed loaded from DB for \(endpoint.agency.rawValue)/\(endpoint.serviceType.rawValue)")
            return storedFeed
        }

        // Download as last resort
        let downloadedFeed = try await downloadFeed(from: endpoint.url)
        try await saveFeedToDB(feed: downloadedFeed, endpoint: endpoint)
        await cache.set(endpoint, feed: downloadedFeed)
        logger.info("Feed downloaded for \(endpoint.agency.rawValue)/\(endpoint.serviceType.rawValue)")
        return downloadedFeed
    }

    private func downloadFeed(from urlString: String) async throws -> Feed {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        return try await Feed(contentsOfURL: url)
    }

    /// Loads feed data from DB with parallel queries.
    private func loadFeedFromDB(endpoint: GTFSEndpoint) async throws -> Feed? {
        guard let record = try await FeedRecord.query(on: db)
            .filter(\.$url == endpoint.url)
            .first()
        else {
            return nil
        }

        let feedID = record.id!

        async let agenciesQuery = AgencyRecord.query(on: db).filter(\AgencyRecord.$feed.$id == feedID).all()
        async let tripsQuery = TripRecord.query(on: db).filter(\TripRecord.$feed.$id == feedID).all()
        async let stopsQuery = StopRecord.query(on: db).filter(\StopRecord.$feed.$id == feedID).all()
        async let stopTimesQuery = StopTimeRecord.query(on: db).filter(\StopTimeRecord.$feed.$id == feedID).with(\.$trip).all()
        async let calendarDatesQuery = CalendarDateRecord.query(on: db).filter(\CalendarDateRecord.$feed.$id == feedID).all()

        let (agencies, trips, stops, stopTimes, calendarDates) = try await (
            agenciesQuery, tripsQuery, stopsQuery, stopTimesQuery, calendarDatesQuery
        )

        return try createFeed(from: agencies, trips: trips, stops: stops, stopTimes: stopTimes, calendarDates: calendarDates)
    }

    private func saveFeedToDB(feed: Feed, endpoint: GTFSEndpoint) async throws {
        if let record = try await FeedRecord.query(on: db)
            .filter(\.$url == endpoint.url)
            .first()
        {
            record.updateLastUpdateDate(to: Date())
            try await record.update(on: db)
        } else {
            let feedRecord = FeedRecord(url: endpoint.url, lastUpdate: Date())
            try await feedRecord.save(on: db)
            let feedID = feedRecord.id!

            if let agencies = feed.agencies?.agencies {
                try await saveRecords(agencies, feedID: feedID, as: AgencyRecord.self)
            }
            if let trips = feed.trips?.trips {
                try await saveRecords(trips, feedID: feedID, as: TripRecord.self)
            }
            if let stops = feed.stops?.stops {
                try await saveRecords(stops, feedID: feedID, as: StopRecord.self)
            }
            if let stopTimes = feed.stopTimes?.stopTimes {
                try await saveRecords(stopTimes, feedID: feedID, as: StopTimeRecord.self)
            }
            if let calendarDates = feed.calendarDates?.dates {
                try await saveRecords(calendarDates, feedID: feedID, as: CalendarDateRecord.self)
            }
        }
    }

    private func saveRecords<T: FeedModelRecord>(_ records: [T.Source], feedID: UUID, as recordType: T.Type) async throws where T: Model {
        // Batch save: create all records first, then save in chunks
        let batchSize = 500
        for chunk in stride(from: 0, to: records.count, by: batchSize) {
            let end = min(chunk + batchSize, records.count)
            for i in chunk..<end {
                let dbRecord = T(from: records[i], feedID: feedID)
                do {
                    try await dbRecord.save(on: db)
                } catch {
                    if error.localizedDescription.contains("UNIQUE constraint failed") {
                        continue
                    }
                    throw error
                }
            }
        }
    }

    private func createFeed(from agencies: [AgencyRecord], trips: [TripRecord], stops: [StopRecord], stopTimes: [StopTimeRecord], calendarDates: [CalendarDateRecord]) throws -> Feed {
        let agencyModels = LocomoSwift.Agencies(agencies.map { $0.toAgency() })
        let tripModels = Trips(trips.map { $0.toTrip() })
        let stopModels = Stops(stops.map { $0.toStop() })
        let stopTimeModels = StopTimes(stopTimes.map { $0.toStopTimes() })
        let calendarDateModels = CalendarDates(calendarDates.map { $0.toCalendarDate() })

        return try Feed(
            agencices: agencyModels,
            stops: stopModels,
            trips: tripModels,
            stopTimes: stopTimeModels,
            calendarDates: calendarDateModels
        )
    }

    private func isFeedStillValid(_ lastUpdate: Date, refreshFrequency: RefreshRate) -> Bool {
        Date().timeIntervalSince(lastUpdate) < refreshFrequency.rawValue
    }
}

/// Actor-based thread-safe feed cache.
private actor FeedCache {
    private var storage: [GTFSEndpoint: (feed: Feed, lastUpdate: Date)] = [:]

    func get(_ endpoint: GTFSEndpoint) -> (feed: Feed, lastUpdate: Date)? {
        storage[endpoint]
    }

    func set(_ endpoint: GTFSEndpoint, feed: Feed) {
        storage[endpoint] = (feed, Date())
    }
}
