//
//  RealtimeDTO.swift
//  RailMapAPI
//
//  Created by RailMapAPI on 2024.
//

import Vapor
import LocomoSwift

// MARK: - Trip Update DTOs

struct TripUpdatesResponse: Content {
    let source: String
    let tripUpdates: [TripUpdateDTO]
}

struct TripUpdateDTO: Content {
    let tripID: String
    let routeID: String?
    let scheduleRelationship: Int
    let delay: Int32?
    let timestamp: Date
    let vehicleID: String?
    let stopTimeUpdates: [StopTimeUpdateDTO]
}

struct StopTimeUpdateDTO: Content {
    let stopID: String
    let stopSequence: UInt32?
    let arrivalDelay: Int32?
    let arrivalTime: Date?
    let departureDelay: Int32?
    let departureTime: Date?
    let scheduleRelationship: Int

    /// Announced platform / track number, when published.
    ///
    /// SNCF (and most operators) don't put the platform in a dedicated
    /// GTFS-RT field — instead they re-route `stopID` from the parent
    /// `stop_area` to a child stop carrying `platform_code`. This field
    /// holds the resolved value (looked up against the static feed at
    /// response time). `nil` when the platform is not yet announced.
    let platform: String?
}

// MARK: - Alert DTOs

struct AlertsResponse: Content {
    let source: String
    let alerts: [AlertDTO]
}

struct AlertDTO: Content {
    let alertID: String
    let cause: Int?
    let effect: Int?
    let url: String?
    let headerText: String?
    let descriptionText: String?
    let activePeriods: [TimePeriodDTO]
    let informedEntities: [EntityDTO]
}

struct TimePeriodDTO: Content {
    let start: Date?
    let end: Date?
}

struct EntityDTO: Content {
    let agencyID: String?
    let routeID: String?
    let routeType: Int32?
    let tripID: String?
    let stopID: String?
    let directionID: UInt32?
}

// MARK: - Vehicle Position DTOs

struct VehiclePositionsResponse: Content {
    let source: String
    let vehiclePositions: [VehiclePositionDTO]
}

struct VehiclePositionDTO: Content {
    let tripID: String?
    let vehicleID: String
    let latitude: Double?
    let longitude: Double?
    let bearing: Float?
    let speed: Float?
    let currentStopSequence: UInt32?
    let currentStatus: Int
    let timestamp: Date
    let occupancyStatus: Int?
}

// MARK: - Conversions from LocomoSwift types

extension TripUpdateDTO {
    init(from update: RealtimeTripUpdate) {
        self.init(from: update, platformResolver: { _ in nil })
    }

    /// Building variant that takes a `platformResolver` closure looking up
    /// the static `platform_code` for any GTFS stop ID. The closure is
    /// passed to each child `StopTimeUpdateDTO` so the response carries the
    /// resolved platform (when published by the operator).
    init(from update: RealtimeTripUpdate, platformResolver: (String) -> String?) {
        self.tripID = update.tripID
        self.routeID = update.routeID
        self.scheduleRelationship = update.scheduleRelationship.rawValue
        self.delay = update.delay
        self.timestamp = update.timestamp
        self.vehicleID = update.vehicleID
        self.stopTimeUpdates = update.stopTimeUpdates.map {
            StopTimeUpdateDTO(from: $0, platform: platformResolver($0.stopID))
        }
    }
}

extension StopTimeUpdateDTO {
    init(from stu: RealtimeStopTimeUpdate) {
        self.init(from: stu, platform: nil)
    }

    init(from stu: RealtimeStopTimeUpdate, platform: String?) {
        self.stopID = stu.stopID
        self.stopSequence = stu.stopSequence
        self.arrivalDelay = stu.arrivalDelay
        self.arrivalTime = stu.arrivalTime
        self.departureDelay = stu.departureDelay
        self.departureTime = stu.departureTime
        self.scheduleRelationship = stu.scheduleRelationship.rawValue
        self.platform = platform
    }
}

extension AlertDTO {
    init(from alert: RealtimeServiceAlert) {
        self.alertID = alert.alertID
        self.cause = alert.cause?.rawValue
        self.effect = alert.effect?.rawValue
        self.url = alert.url?.absoluteString
        self.headerText = alert.headerText
        self.descriptionText = alert.descriptionText
        self.activePeriods = alert.activePeriods.map { TimePeriodDTO(start: $0.start, end: $0.end) }
        self.informedEntities = alert.informedEntities.map { EntityDTO(from: $0) }
    }
}

extension EntityDTO {
    init(from entity: AlertInformedEntity) {
        self.agencyID = entity.agencyID
        self.routeID = entity.routeID
        self.routeType = entity.routeType
        self.tripID = entity.tripID
        self.stopID = entity.stopID
        self.directionID = entity.directionID
    }
}

extension VehiclePositionDTO {
    init(from vp: RealtimeVehiclePosition) {
        self.tripID = vp.tripID
        self.vehicleID = vp.vehicleID
        self.latitude = vp.latitude
        self.longitude = vp.longitude
        self.bearing = vp.bearing
        self.speed = vp.speed
        self.currentStopSequence = vp.currentStopSequence
        self.currentStatus = vp.currentStatus.rawValue
        self.timestamp = vp.timestamp
        self.occupancyStatus = vp.occupancyStatus?.rawValue
    }
}
