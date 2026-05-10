import Vapor
import Fluent
import FluentSQLiteDriver
import LocomoSwift

// configures your application
public func configure(_ app: Application) async throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    app.databases.use(
        .sqlite(.file("db.sqlite"), maxConnectionsPerEventLoop: 4),
        as: .sqlite
    )

    // Add migrations
    app.migrations.add(CreateFeedRecord())
    app.migrations.add(CreateAgencyRecord())
    app.migrations.add(CreateTripRecord())
    app.migrations.add(CreateStopRecord())
    app.migrations.add(CreateStopTimeRecord())
    app.migrations.add(CreateCalendarDateRecord())

    // Run pending migrations
    try await app.autoMigrate()

    // Initialize shared services (singletons)
    let feedManager = FeedManager()
    let realtimeManager = RealtimeManager()
    let registry = DataSourceRegistry.default

    try routes(app, feedManager: feedManager, realtimeManager: realtimeManager, registry: registry)
}
