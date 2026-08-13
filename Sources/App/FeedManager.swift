//
//  FeedManager.swift
//  RailMapAPI
//
//  Created by Jérémie Patot on 11/10/2024.
//

import Fluent
import Vapor
import LocomoSwift

/// Thread-safe, shared manager for downloading, caching, and persisting GTFS feeds.
///
/// Key optimizations:
/// - **URL-level deduplication**: Multiple `DataSource`s pointing to the same ZIP share
///   a single cache entry (e.g. SNCF TER / TGV / Intercités).
/// - **Download coalescing**: Concurrent requests for the same URL `await` a single
///   in-flight `Task` instead of triggering parallel downloads.
/// - **Batch DB inserts**: Records are inserted in chunks to minimize SQL round-trips.
public actor FeedManager {

    // MARK: - Cache (keyed by URL, not by identifier)

    private var urlCache: [String: (feed: Feed, lastUpdate: Date)] = [:]

    /// In-flight downloads keyed by URL — concurrent callers await the same Task.
    private var inFlightDownloads: [String: Task<Feed, Error>] = [:]

    public init() {}

    // MARK: - Public API

    /// Returns a `Feed` for the given source, using (in order):
    /// 1. The in-memory URL cache (if still fresh)
    /// 2. The SQLite database
    /// 3. A fresh download (coalesced if another request for the same URL is in progress)
    func getFeed(for source: DataSource, on db: Database) async throws -> Feed {
        guard source.hasStaticFeed else {
            throw Abort(.badRequest, reason: "DataSource '\(source.identifier)' has no static feed configured")
        }

        let feedURL = try source.authenticatedStaticFeedURL()
        let cacheKey = source.staticFeedURL!.absoluteString

        // 1. Check in-memory cache (keyed by raw URL, shared across sources)
        if let cached = urlCache[cacheKey],
           !source.staticFeedNeedsRefresh(since: cached.lastUpdate) {
            print("[FeedManager] Cache hit for '\(source.displayName)' (URL: \(cacheKey))")
            return cached.feed
        }

        // 2. SQLite reload is intentionally BYPASSED (stopgap fix A).
        //
        // The DB layer does not persist `routes`, `shapes`, nor a trip's
        // `shortName` / `shapeID` / `routeID` (see TripRecord + saveFeedToDB).
        // A feed rebuilt from SQLite therefore loses its shapes AND becomes
        // unsearchable by train number — which is exactly why
        // `/train/:num/shape` returned 404 and the app fell back to straight
        // stop-to-stop lines once the in-memory cache had expired.
        //
        // Until the proper fix lands (persist routes/shapes + those trip fields
        // — see ADR-009 / "fix B"), always serve the COMPLETE freshly downloaded
        // feed via the in-memory cache or a new download below.
        //
        // Trade-off: a cold process re-downloads on the first request per source
        // (the download is still coalesced). `saveFeedToDB` keeps running so the
        // data is ready for fix B; its output is simply not read back yet.

        // 3. Download (coalesced)
        let feed = try await coalesceDownload(url: feedURL, cacheKey: cacheKey, on: db)
        return feed
    }

    // MARK: - Download coalescing

    /// If a download for the same URL is already in progress, awaits that task.
    /// Otherwise starts a new download task and registers it.
    private func coalesceDownload(url: URL, cacheKey: String, on db: Database) async throws -> Feed {
        // If there's already an in-flight download for this URL, await it
        if let existingTask = inFlightDownloads[cacheKey] {
            print("[FeedManager] Coalescing download for \(cacheKey)")
            return try await existingTask.value
        }

        // Start a new download task
        let task = Task<Feed, Error> {
            let feed = try await Feed(contentsOfURL: url)
            print("[FeedManager] Downloaded feed from \(cacheKey)")
            return feed
        }
        inFlightDownloads[cacheKey] = task

        do {
            let feed = try await task.value

            // Persist to DB and cache
            try await saveFeedToDB(feed: feed, url: cacheKey, on: db)
            urlCache[cacheKey] = (feed, Date())

            inFlightDownloads[cacheKey] = nil
            return feed
        } catch {
            inFlightDownloads[cacheKey] = nil
            throw error
        }
    }

    // MARK: - Database: Load

    /// Loads a Feed from the database by URL. Returns nil if not found.
    ///
    /// Currently unused: `getFeed` bypasses the SQLite reload because the DB
    /// layer loses routes/shapes and trip identifiers (see fix A note in
    /// `getFeed`). Retained for the proper fix (B), which will make the DB
    /// round-trip lossless and re-enable this path. `internal` (not `private`)
    /// on purpose so it doesn't trip the "never used" warning meanwhile.
    func loadFeedFromDB(url: String, on db: Database) async throws -> Feed? {
        guard let record = try await FeedRecord.query(on: db)
            .filter(\.$url == url)
            .first()
        else {
            return nil
        }

        let feedID = record.id!

        // Sequential DB queries — SQLite's connection pool is small,
        // parallel queries from concurrent requests cause deadlocks.
        let agencies = try await AgencyRecord.query(on: db).filter(\AgencyRecord.$feed.$id == feedID).all()
        let trips = try await TripRecord.query(on: db).filter(\TripRecord.$feed.$id == feedID).all()
        let stops = try await StopRecord.query(on: db).filter(\StopRecord.$feed.$id == feedID).all()
        let stopTimes = try await StopTimeRecord.query(on: db).filter(\StopTimeRecord.$feed.$id == feedID).with(\.$trip).all()
        let calendarDates = try await CalendarDateRecord.query(on: db).filter(\CalendarDateRecord.$feed.$id == feedID).all()

        return try createFeed(from: agencies, trips: trips, stops: stops, stopTimes: stopTimes, calendarDates: calendarDates)
    }

    // MARK: - Database: Save (batch inserts)

    /// Saves a Feed to the database using batch inserts.
    private func saveFeedToDB(feed: Feed, url: String, on db: Database) async throws {
        // Check if a record already exists for this URL
        if let record = try await FeedRecord.query(on: db)
            .filter(\.$url == url)
            .first()
        {
            record.updateLastUpdateDate(to: Date())
            try await record.update(on: db)
            return
        }

        let feedRecord = FeedRecord(url: url, lastUpdate: Date())
        try await feedRecord.save(on: db)
        let feedID = feedRecord.id!

        // Batch-insert all record types inside a transaction
        try await db.transaction { tx in
            if let agencies = feed.agencies?.agencies {
                try await self.batchSave(agencies, feedID: feedID, as: AgencyRecord.self, on: tx)
            }
            if let trips = feed.trips?.trips {
                try await self.batchSave(trips, feedID: feedID, as: TripRecord.self, on: tx)
            }
            if let stops = feed.stops?.stops {
                try await self.batchSave(stops, feedID: feedID, as: StopRecord.self, on: tx)
            }
            if let stopTimes = feed.stopTimes?.stopTimes {
                try await self.batchSave(stopTimes, feedID: feedID, as: StopTimeRecord.self, on: tx)
            }
            if let calendarDates = feed.calendarDates?.dates {
                try await self.batchSave(calendarDates, feedID: feedID, as: CalendarDateRecord.self, on: tx)
            }
        }

        print("[FeedManager] Saved feed to database (\(url))")
    }

    /// Batch-insert records in chunks to stay within SQLite's 999 variable limit.
    /// Falls back to per-record insert on UNIQUE constraint failures.
    private func batchSave<T: FeedModelRecord>(
        _ records: [T.Source],
        feedID: UUID,
        as recordType: T.Type,
        on db: Database
    ) async throws where T: Model {
        let dbRecords = records.map { T(from: $0, feedID: feedID) }

        // SQLite limit: 999 variables per statement
        // Estimate ~10 fields per record → chunk of ~99
        let chunkSize = 99
        for chunk in dbRecords.chunked(into: chunkSize) {
            do {
                try await chunk.create(on: db)
            } catch {
                // If batch fails (likely UNIQUE constraint), fall back to per-record
                if error.localizedDescription.contains("UNIQUE constraint failed") {
                    for record in chunk {
                        do {
                            try await record.save(on: db)
                        } catch {
                            if error.localizedDescription.contains("UNIQUE constraint failed") {
                                continue
                            }
                            throw error
                        }
                    }
                } else {
                    throw error
                }
            }
        }
    }

    // MARK: - Feed construction

    /// Creates a `Feed` from database records.
    private func createFeed(
        from agencies: [AgencyRecord],
        trips: [TripRecord],
        stops: [StopRecord],
        stopTimes: [StopTimeRecord],
        calendarDates: [CalendarDateRecord]
    ) throws -> Feed {
        let agencyModels = Agencies(agencies.map { $0.toAgency() })
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

    // MARK: - Cache management

    /// Clears the in-memory feed cache.
    func clearCache() {
        urlCache.removeAll()
    }
}

// MARK: - Array chunking helper

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
