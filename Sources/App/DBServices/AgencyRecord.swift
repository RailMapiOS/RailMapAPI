//
//  AgencyRecord.swift
//  RailMapAPI
//
//  Created by Jérémie Patot on 11/10/2024.
//

import Fluent
import LocomoSwift
import Vapor

final class AgencyRecord: Model, Content {
    static let schema = "agencies"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "agency_id")
    var agencyID: String?

    @Field(key: "name")
    var name: String

    @Field(key: "url")
    var url: String

    @Field(key: "time_zone")
    var timeZone: String

    @Field(key: "locale")
    var locale: String?

    @Field(key: "phone")
    var phone: String?

    @Field(key: "fare_url")
    var fareURL: String?

    @Field(key: "email")
    var email: String?

    @Parent(key: "feed_id")
    var feed: FeedRecord

    init() {}

    init(from agency: Agency, feedID: UUID) {
        self.agencyID = agency.agencyID
        self.name = agency.name
        self.url = agency.url.absoluteString
        self.timeZone = agency.timeZone.identifier
        self.locale = agency.locale?.identifier
        self.phone = agency.phone
        self.fareURL = agency.fareURL?.absoluteString
        self.email = agency.email
        self.$feed.id = feedID
    }

    func toAgency() -> Agency {
        return Agency(
            agencyID: self.agencyID,
            name: self.name,
            url: URL(string: self.url)!,
            timeZone: TimeZone(identifier: self.timeZone)!,
            locale: self.locale != nil ? Locale(identifier: self.locale!) : nil,
            phone: self.phone,
            fareURL: self.fareURL != nil ? URL(string: self.fareURL!) : nil,
            email: self.email
        )
    }
}

struct CreateAgencyRecord: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("agencies")
            .id()
            .field("agency_id", .string)
            .field("name", .string, .required)
            .field("url", .string, .required)
            .field("time_zone", .string, .required)
            .field("locale", .string)
            .field("phone", .string)
            .field("fare_url", .string)
            .field("email", .string)
            .field("feed_id", .uuid, .required, .references("feeds", "id"))
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("agencies").delete()
    }
}
