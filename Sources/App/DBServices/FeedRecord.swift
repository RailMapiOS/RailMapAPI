//
//  FeedRecord.swift
//  RailMapAPI
//
//  Created by Jérémie Patot on 11/10/2024.
//


import Fluent
import Vapor

final class FeedRecord: Model, Content {
    static let schema = "feeds"  // Nom de la table dans la base de données

    @ID(key: .id)
    var id: UUID?

    @Field(key: "url")
    var url: String

    @Field(key: "last_update")
    var lastUpdate: String

    init() {}

    init(id: UUID? = nil, url: String, lastUpdate: Date) {
        self.id = id
        self.url = url
        self.lastUpdate = ISO8601DateFormatter().string(from: lastUpdate)
    }
    
    var lastUpdateDate: Date? {
            return ISO8601DateFormatter().date(from: self.lastUpdate)
        }
    
    func updateLastUpdateDate(to date: Date) {
            self.lastUpdate = ISO8601DateFormatter().string(from: date)  // Conversion de la nouvelle date en chaîne
        }
}

struct CreateFeedRecord: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("feeds")
            .id()
            .field("url", .string, .required)
            .field("last_update", .string, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("feeds").delete()
    }
}
