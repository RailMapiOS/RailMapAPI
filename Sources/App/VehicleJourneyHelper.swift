//
//  VehicleJourneyHelper.swift
//  RailMapAPI
//
//  Created by Jérémie Patot on 11/10/2024.
//

import Foundation
import LocomoSwift

public struct VehicleJourneyHelper {
    public func createVehicleJourney(from trip: Trip, with feed: Feed, calendarDates: [CalendarDate]) -> VehicleJourney {
        let stopTimes = feed.stopTimes?.filter { $0.tripID == trip.tripID } ?? []
        let validDates = calendarDates.filter { $0.serviceID == trip.serviceID }
        let validityPattern = constructValidityPattern(from: validDates)
        
        let vehicleStopTimes = stopTimes.map { stopTime in
            createVehicleStopTime(from: stopTime, trip: trip, feed: feed)
        }
        
        return VehicleJourney(
            id: trip.tripID,
            name: trip.headSign ?? "",
            journeyPattern: JourneyPattern(id: trip.tripID, name: trip.headSign ?? ""),
            stopTimes: vehicleStopTimes,
            codes: [Code(type: .source, value: "GTFS")],
            validityPattern: validityPattern,
            calendars: [],
            trip: JourneyPattern(id: trip.tripID, name: trip.headSign ?? ""),
            disruptions: [],
            headsign: trip.headSign ?? ""
        )
    }
    
    public func createVehicleStopTime(from stopTime: StopTime, trip: Trip, feed: Feed) -> VehicleStopTime {
        let agencyTimezone = getAgencyTimezone(from: feed)
        let utcArrivalTime = stopTime.arrival?.addingTimeInterval(-TimeInterval(agencyTimezone.secondsFromGMT(for: stopTime.arrival!))) ?? Date()
        let utcDepartureTime = stopTime.departure?.addingTimeInterval(-TimeInterval(agencyTimezone.secondsFromGMT(for: stopTime.departure!))) ?? Date()
        
        print("""
            stopTimes
                name: \(feed.stops?.first(where: { $0.stopID == stopTime.stopID })?.name ?? "Unknown"),
            pickupAllowed:\(stopTime.pickupType)==0 \(stopTime.pickupType == 0),
            dropOffAllowed:\(stopTime.dropOffType)==0 \(stopTime.dropOffType == 0),
""")
        
        return VehicleStopTime(
            arrivalTime: stopTime.arrival?.ISO8601Format() ?? "",
            utcArrivalTime: utcArrivalTime.ISO8601Format() ?? "",
            departureTime: stopTime.departure?.ISO8601Format() ?? "",
            utcDepartureTime: utcDepartureTime.ISO8601Format() ?? "",
            headsign: (stopTime.stopHeadingSign ?? trip.headSign) ?? "",
            stopPoint: StopPoint(
                id: stopTime.stopID,
                name: feed.stops?.first(where: { $0.stopID == stopTime.stopID })?.name ?? "Unknown",
                codes: [Code(type: .gtfsStopCode, value: stopTime.stopID)],
                label: feed.stops?.first(where: { $0.stopID == stopTime.stopID })?.name ?? "Unknown",
                coord: Coord(
                    lon: feed.stops?.first(where: { $0.stopID == stopTime.stopID })?.longitude?.formatted() ?? "0.0",
                    lat: feed.stops?.first(where: { $0.stopID == stopTime.stopID })?.latitude?.formatted() ?? "0.0"
                ),
                links: [],
                equipments: []
            ),
            pickupAllowed: stopTime.pickupType == 0,
            dropOffAllowed: stopTime.dropOffType == 0,
            skippedStop: false
        )
    }
    
    public func getAgencyTimezone(from feed: Feed) -> TimeZone {
        if let agency = feed.agencies?.agencies.first {
            return agency.timeZone
        }
        return TimeZone(secondsFromGMT: 0)!
    }
    
    public func constructValidityPattern(from calendarDates: [CalendarDate]) -> ValidityPattern {
        let formattedDates = calendarDates.map { $0.date.ISO8601Format() }.joined(separator: ", ")
        return ValidityPattern(beginningDate: formattedDates, days: "Custom Dates")
    }
    
    // Méthode pour créer un objet VehicleJourneys à partir d'une liste de VehicleJourney et du contenu du fichier GTFS
    public func createVehicleJourneys(from journeys: [VehicleJourney], agencies: LocomoSwift.Agencies) -> VehicleJourneys {
            // Extraire les FeedPublishers depuis les agences
            let feedPublishers: [FeedPublisher] = agencies.agencies.map { agency in
                FeedPublisher(
                    id: agency.agencyID ?? UUID().uuidString,
                    name: agency.name,
                    url: agency.url.absoluteString,
                    license: "" // Ajoutez des informations de licence si disponibles
                )
            }

            // Créer des liens depuis les URLs des agences
        let links: [Link] = agencies.agencies.map { agency in
                Link(
                    href: agency.url.absoluteString,
                    templated: false,
                    rel: nil,
                    type: "application/json"
                )
            }

            return VehicleJourneys(
                pagination: Pagination(
                    totalResult: journeys.count,
                    startPage: 1,
                    itemsPerPage: journeys.count,
                    itemsOnPage: journeys.count
                ),
                feedPublishers: feedPublishers,
                disruptions: [],
                context: Context(currentDatetime: Date().description, timezone: TimeZone.current.identifier),
                vehicleJourneys: journeys,
                links: links
            )
        }
}
