//
//  FeedModelRecord.swift
//  RailMapAPI
//
//  Created by Jérémie Patot on 25/10/2024.
//

import Fluent
import LocomoSwift
import Vapor

protocol FeedModelRecord: Model {
    associatedtype Source
    init(from source: Source, feedID: UUID)
}

extension AgencyRecord: FeedModelRecord {
    typealias Source = Agency
}

extension TripRecord: FeedModelRecord {
    typealias Source = Trip
}

extension StopRecord: FeedModelRecord {
    typealias Source = Stop
}

extension StopTimeRecord: FeedModelRecord {
    typealias Source = StopTime

    convenience init(from source: StopTime, feedID: UUID) {
        self.init()
        self.$trip.id = source.tripID
        self.arrival = source.arrival
        self.departure = source.departure
        self.stopID = source.stopID
        self.stopSequenceNumber = source.stopSequenceNumber
        self.stopHeadingSign = source.stopHeadingSign
        self.pickupType = source.pickupType
        self.dropOffType = source.dropOffType
        self.continuousPickup = source.continuousPickup
        self.continuousDropOff = source.continuousDropOff
        self.distanceTraveledForShape = source.distanceTraveledForShape
        self.timePointType = source.timePointType
        self.timeZoneIdentifier = source.timeZone.identifier
        self.$feed.id = feedID
    }
}
