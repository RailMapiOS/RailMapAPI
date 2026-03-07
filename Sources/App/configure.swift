import Vapor
import Fluent
import FluentSQLiteDriver

public func configure(_ app: Application) async throws {
    app.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)

    // Schema migrations
    app.migrations.add(CreateFeedRecord())
    app.migrations.add(CreateAgencyRecord())
    app.migrations.add(CreateTripRecord())
    app.migrations.add(CreateStopRecord())
    app.migrations.add(CreateStopTimeRecord())
    app.migrations.add(CreateCalendarDateRecord())
    // Indices for frequent queries
    app.migrations.add(AddDatabaseIndices())

    try await app.autoMigrate()
    try routes(app)
}
