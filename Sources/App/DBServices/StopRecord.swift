//
//  StopRecord.swift
//  RailMapAPI
//
//  Created by Jérémie Patot on 11/10/2024.
//


import Fluent
import Vapor
import LocomoSwift

final class StopRecord: Model, Content {
    static let schema = "stops"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "stop_id")
    var stopID: String
    
    @OptionalField(key: "stop_code")
    var code: String?
    
    @OptionalField(key: "stop_desc")
    var details: String?
    
    @Field(key: "stop_name")
    var name: String
    
    @Field(key: "stop_lat")
    var latitude: Double
    
    @Field(key: "stop_lon")
    var longitude: Double
    
    @OptionalField(key: "zone_id")
    var zoneID: String?
    
    @OptionalField(key: "stop_url")
    var url: String?
    
    @OptionalField(key: "location_type")
    var locationType: String?
    
    @OptionalField(key: "parent_station")
    var parentStationID: String?
    
    @OptionalField(key: "stop_timezone")
    var timeZone: String?
    
    @OptionalField(key: "wheelchair_boarding")
    var accessibility: String?
    
    @OptionalField(key: "level_id")
    var levelID: String?
    
    @OptionalField(key: "platform_code")
    var platformCode: String?
    
    @OptionalField(key: "nonstandard")
    var nonstandard: String?
    
    @Parent(key: "feed_id")
    var feed: FeedRecord
    
    // Default initializer
    init() {}
    
    // Initialize from Stop model
    init(from stop: Stop, feedID: UUID) {
        self.stopID = stop.stopID
        self.code = stop.code
        self.name = stop.name ?? "Unknown Stop"  // Default value if name is nil
        self.details = stop.details
        self.latitude = stop.latitude ?? 0.0  // Default value if latitude is nil
        self.longitude = stop.longitude ?? 0.0  // Default value if longitude is nil
        self.zoneID = stop.zoneID
        self.url = stop.url?.absoluteString
        self.locationType = stop.locationType?.rawValue.formatted()  // Assuming this formatted() is necessary
        self.parentStationID = stop.parentStationID
        self.timeZone = stop.timeZone?.identifier
        self.accessibility = stop.accessibility?.rawValue.formatted()  // Assuming this formatted() is necessary
        self.levelID = stop.levelID
        self.platformCode = stop.platformCode
        self.nonstandard = stop.nonstandard
        self.$feed.id = feedID
    }
    
    // Convert back to Stop model
    func toStop() -> Stop {
        let locationType = self.locationType.flatMap { UInt($0) }.flatMap { StopLocationType(rawValue: $0) }
        let accessibility = self.accessibility.flatMap { UInt($0) }.flatMap { Accessibility(rawValue: $0) }
        
        return Stop(
            stopID: self.stopID,
            code: self.code?.isEmpty == true ? nil : self.code,
            name: self.name.isEmpty ? nil : self.name,
            details: self.details?.isEmpty == true ? nil : self.details,
            latitude: self.latitude,
            longitude: self.longitude,
            zoneID: self.zoneID?.isEmpty == true ? nil : self.zoneID,
            url: self.url?.isEmpty == true ? nil : URL(string: self.url ?? ""),
            locationType: locationType,
            parentStationID: self.parentStationID?.isEmpty == true ? nil : self.parentStationID,
            timeZone: TimeZone(identifier: self.timeZone ?? ""),
            accessibility: accessibility,
            levelID: self.levelID?.isEmpty == true ? nil : self.levelID,
            platformCode: self.platformCode?.isEmpty == true ? nil : self.platformCode
        )
    }
}

struct CreateStopRecord: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("stops")
            .id()
            .field("stop_id", .string, .required)
            .field("stop_code", .string)
            .field("stop_desc", .string)
            .field("stop_name", .string, .required)
            .field("stop_lat", .double, .required)
            .field("stop_lon", .double, .required)
            .field("zone_id", .string)
            .field("stop_url", .string)
            .field("location_type", .string)
            .field("parent_station", .string)
            .field("stop_timezone", .string)
            .field("wheelchair_boarding", .string)
            .field("level_id", .string)
            .field("platform_code", .string)
            .field("nonstandard", .string)
            .field("feed_id", .uuid, .required, .references("feeds", "id"))
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("stops").delete()
    }
}
