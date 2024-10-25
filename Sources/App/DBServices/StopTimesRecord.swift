//
//  StopTimesRecord.swift
//  RailMapAPI
//
//  Created by Jérémie Patot on 25/10/2024.
//


import Fluent
import Vapor
import LocomoSwift

final class StopTimeRecord: Model, Content {
    static let schema = "stop_times"
    
    @ID(key: .id)
    var id: UUID?
    
    @Parent(key: "trip_id")
    var trip: TripRecord
    
    @OptionalField(key: "arrival_time")
    var arrival: Date?
    
    @OptionalField(key: "departure_time")
    var departure: Date?
    
    @Field(key: "stop_id")
    var stopID: String
    
    @Field(key: "stop_sequence")
    var stopSequenceNumber: UInt
    
    @OptionalField(key: "stop_headsign")
    var stopHeadingSign: String?
    
    @OptionalField(key: "pickup_type")
    var pickupType: Int?
    
    @OptionalField(key: "drop_off_type")
    var dropOffType: Int?
    
    @OptionalField(key: "continuous_pickup")
    var continuousPickup: Int?
    
    @OptionalField(key: "continuous_drop_off")
    var continuousDropOff: Int?
    
    @OptionalField(key: "shape_dist_traveled")
    var distanceTraveledForShape: Double?
    
    @OptionalField(key: "timepoint")
    var timePointType: Int?
    
    @OptionalField(key: "time_zone_identifier")
    var timeZoneIdentifier: String?
    
    var timeZone: TimeZone? {
           get {
               guard let identifier = timeZoneIdentifier else { return nil }
               return TimeZone(identifier: identifier)
           }
           set {
               timeZoneIdentifier = newValue?.identifier
           }
       }
    
    @Parent(key: "feed_id")
    var feed: FeedRecord
    
    // Initialiseur par défaut
    init() {}
    
    // Initialiseur à partir du modèle `StopTime`
    init(from stopTime: StopTime, feedID: UUID, tripID: String) {
        self.$trip.id = stopTime.tripID
        self.arrival = stopTime.arrival
        self.departure = stopTime.departure
        self.stopID = stopTime.stopID
        self.stopSequenceNumber = stopTime.stopSequenceNumber
        self.stopHeadingSign = stopTime.stopHeadingSign
        self.pickupType = stopTime.pickupType
        self.dropOffType = stopTime.dropOffType
        self.continuousPickup = stopTime.continuousPickup
        self.continuousDropOff = stopTime.continuousDropOff
        self.distanceTraveledForShape = stopTime.distanceTraveledForShape
        self.timePointType = stopTime.timePointType
        self.timeZone = stopTime.timeZone
        self.$feed.id = feedID
    }
    
    func toStopTimes() -> StopTime {
        return StopTime(
            tripID: self.trip.id ?? "",
            arrival: self.arrival,
            departure: self.departure,
            stopID: self.stopID,
            stopSequenceNumber: self.stopSequenceNumber,
            stopHeadingSign: self.stopHeadingSign,
            pickupType: self.pickupType,
            dropOffType: self.dropOffType,
            continuousPickup: self.continuousPickup,
            continuousDropOff: self.continuousDropOff,
            distanceTraveledForShape: self.distanceTraveledForShape,
            timePointType: self.timePointType,
            timeZone: self.timeZone
        )
    }
}

struct CreateStopTimeRecord: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("stop_times")
            .id()
            .field("trip_id", .string, .required, .references("trips", "trip_id"))
            .field("arrival_time", .datetime)
            .field("departure_time", .datetime)
            .field("stop_id", .string, .required)
            .field("stop_sequence", .uint, .required)
            .field("stop_headsign", .string)
            .field("pickup_type", .int)
            .field("drop_off_type", .int)
            .field("continuous_pickup", .int)
            .field("continuous_drop_off", .int)
            .field("shape_dist_traveled", .double)
            .field("timepoint", .int)
            .field("time_zone_identifier", .string)
            .field("feed_id", .uuid, .required, .references("feeds", "id"))
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("stop_times").delete()
    }
}
