//
//  TripRecord.swift
//  RailMapAPI
//
//  Created by Jérémie Patot on 11/10/2024.
//


import Fluent
import LocomoSwift
import Vapor

final class TripRecord: Model, Content {
    typealias IDValue = String
    
    static let schema = "trips"

    @ID(custom: "trip_id")
    var id: String?
    
    @Field(key: "headsign")
    var headsign: String?

    @Field(key: "service_id")
    var serviceID: String

    @Parent(key: "feed_id")
    var feed: FeedRecord

    init() {}

    init(from trip: Trip, feedID: UUID) {
        self.id = trip.tripID
        self.headsign = trip.headSign
        self.serviceID = trip.serviceID
        self.$feed.id = feedID
    }

    func toTrip() -> Trip {
        return Trip(
            serviceID: self.serviceID,
            tripID: self.id ?? "",
            headSign: self.headsign
        )
    }
}

struct CreateTripRecord: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("trips")
            .field("trip_id", .string, .identifier(auto: false))
            .field("headsign", .string)
            .field("service_id", .string, .required)
            .field("feed_id", .uuid, .required, .references("feeds", "id"))
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("trips").delete()
    }
}
