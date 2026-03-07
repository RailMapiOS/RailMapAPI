import Fluent
import FluentSQL

struct AddDatabaseIndices: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        try await sql.raw("CREATE UNIQUE INDEX IF NOT EXISTS idx_feeds_url ON feeds(url)").run()
        try await sql.raw("CREATE UNIQUE INDEX IF NOT EXISTS idx_trips_trip_feed ON trips(trip_id, feed_id)").run()
        try await sql.raw("CREATE UNIQUE INDEX IF NOT EXISTS idx_stops_stop_feed ON stops(stop_id, feed_id)").run()
        try await sql.raw("CREATE UNIQUE INDEX IF NOT EXISTS idx_stop_times_composite ON stop_times(trip_id, stop_id, stop_sequence, feed_id)").run()
        try await sql.raw("CREATE UNIQUE INDEX IF NOT EXISTS idx_calendar_dates_composite ON calendar_dates(service_id, date, feed_id)").run()
        try await sql.raw("CREATE UNIQUE INDEX IF NOT EXISTS idx_agencies_agency_feed ON agencies(agency_id, feed_id)").run()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        try await sql.raw("DROP INDEX IF EXISTS idx_feeds_url").run()
        try await sql.raw("DROP INDEX IF EXISTS idx_trips_trip_feed").run()
        try await sql.raw("DROP INDEX IF EXISTS idx_stops_stop_feed").run()
        try await sql.raw("DROP INDEX IF EXISTS idx_stop_times_composite").run()
        try await sql.raw("DROP INDEX IF EXISTS idx_calendar_dates_composite").run()
        try await sql.raw("DROP INDEX IF EXISTS idx_agencies_agency_feed").run()
    }
}
