import Fluent

struct AddDatabaseIndices: AsyncMigration {
    func prepare(on database: Database) async throws {
        // Index on feeds.url for endpoint lookups
        try await database.schema("feeds")
            .unique(on: "url")
            .update()

        // Index on trips.feed_id and trips.headsign for filtered queries
        try await database.schema("trips")
            .unique(on: "trip_id", "feed_id")
            .update()

        // Index on stops.feed_id and stops.stop_id for lookups
        try await database.schema("stops")
            .unique(on: "stop_id", "feed_id")
            .update()

        // Index on stop_times.trip_id for join queries
        try await database.schema("stop_times")
            .unique(on: "trip_id", "stop_id", "stop_sequence", "feed_id")
            .update()

        // Index on calendar_dates for service_id filtering
        try await database.schema("calendar_dates")
            .unique(on: "service_id", "date", "feed_id")
            .update()

        // Index on agencies.feed_id
        try await database.schema("agencies")
            .unique(on: "agency_id", "feed_id")
            .update()
    }

    func revert(on database: Database) async throws {
        // SQLite doesn't support dropping individual constraints easily,
        // so reverting would require recreating tables.
    }
}
