import Vapor
import Fluent
import FluentSQLiteDriver

// configures your application
public func configure(_ app: Application) async throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    app.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)
    
    // Ajouter tes migrations ici, si nécessaire
    app.migrations.add(CreateFeedRecord())
    app.migrations.add(CreateAgencyRecord())
    app.migrations.add(CreateTripRecord())
    app.migrations.add(CreateStopRecord())
    app.migrations.add(CreateStopTimeRecord())

    // Migrer automatiquement la base de données
    try await app.autoMigrate()
    
    try routes(app)
}
