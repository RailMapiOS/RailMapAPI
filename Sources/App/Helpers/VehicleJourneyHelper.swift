//
//  VehicleJourneyHelper.swift
//  RailMapAPI
//
//  Created by Jérémie Patot on 11/10/2024.
//

import Foundation
import LocomoSwift

public struct VehicleJourneyHelper {
//    public func createVehicleJourney(from trip: Trip, with feed: Feed, calendarDates: [CalendarDate]) -> VehicleJourney {
//        let stopTimes = feed.stopTimes?.filter { $0.tripID == trip.tripID } ?? []
//        let validDates = calendarDates.filter { $0.serviceID == trip.serviceID }
//        let validityPattern = constructValidityPattern(from: validDates)
//        
//        let vehicleStopTimes = stopTimes.map { stopTime in
//            createVehicleStopTime(from: stopTime, trip: trip, feed: feed)
//        }
//        
//        return VehicleJourney(
//            id: trip.tripID,
//            name: trip.headSign ?? "",
//            journeyPattern: JourneyPattern(id: trip.tripID, name: trip.headSign ?? ""),
//            stopTimes: vehicleStopTimes,
//            codes: [Code(type: .source, value: "GTFS")],
//            validityPattern: validityPattern,
//            calendars: validDates,
//            trip: JourneyPattern(id: trip.tripID, name: trip.headSign ?? ""),
//            disruptions: [],
//            headsign: trip.headSign ?? ""
//        )
//    }
    
    public func createVehicleStopTime(from stopTime: StopTime, trip: Trip, feed: Feed) -> VehicleStopTime {
        let agencyTimezone = getAgencyTimezone(from: feed)
            
            // Formatter pour l'heure locale (agence)
            let agencyFormatter = DateFormatter()
            agencyFormatter.dateFormat = "HH:mm:ss"
            agencyFormatter.timeZone = agencyTimezone
            
            // Formatter pour UTC
            let utcFormatter = DateFormatter()
            utcFormatter.dateFormat = "HH:mm:ss"
            utcFormatter.timeZone = TimeZone(secondsFromGMT: 0)!
            
            // Convertir les dates UTC en dates locales de l'agence
            let arrivalDate = stopTime.arrival ?? Date()
            let departureDate = stopTime.departure ?? Date()
        print("""
            stopTimes
                name: \(feed.stops?.first(where: { $0.stopID == stopTime.stopID })?.name ?? "Unknown"),
                agencyTimezone: \(agencyTimezone)
            arrival: \(stopTime.arrival),
                arrivalTime: \(agencyFormatter.string(from: arrivalDate))
                utcArrivalTime: \(utcFormatter.string(from: arrivalDate))
            departure: \(stopTime.departure),
                departureTime: \(agencyFormatter.string(from: departureDate)),
                utcDepartureTime: \(utcFormatter.string(from: departureDate))),
            pickupAllowed:\(stopTime.pickupType)==0 \(stopTime.pickupType == 0),
            dropOffAllowed:\(stopTime.dropOffType)==0 \(stopTime.dropOffType == 0),
""")
  
        return VehicleStopTime(
            arrivalTime: agencyFormatter.string(from: arrivalDate),
            utcArrivalTime: utcFormatter.string(from: arrivalDate),
            departureTime: agencyFormatter.string(from: departureDate),
            utcDepartureTime: utcFormatter.string(from: departureDate),
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
    public func createVehicleJourney(from trip: Trip, with feed: Feed, calendarDates: [CalendarDate]) -> VehicleJourney {
        let stopTimes = feed.stopTimes?.filter { $0.tripID == trip.tripID } ?? []
        let validDates = calendarDates.filter { $0.serviceID == trip.serviceID }
        let validityPattern = constructValidityPattern(from: validDates)
        let vehicleDates = createVehicleCalendar(from: calendarDates, serviceID: trip.serviceID)
        
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
            calendars: vehicleDates,
            trip: JourneyPattern(id: trip.tripID, name: trip.headSign ?? ""),
            disruptions: [],
            headsign: trip.headSign ?? ""
        )
    }
}

extension VehicleJourneyHelper {
    func createVehicleCalendar(from calendarDates: [CalendarDate], serviceID: String) -> [VehicleCalendar] {
        let serviceCalendarDates = calendarDates.filter { $0.serviceID == serviceID }
        
        // Grouper les dates par mois
        let groupedDates = Dictionary(grouping: serviceCalendarDates) { date -> String in
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM"
            return dateFormatter.string(from: date.date)
        }
        
        return groupedDates.map { month, dates in
            let exceptions = dates.map { date -> Exception in
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                return Exception(
                    datetime: dateFormatter.string(from: date.date),
                    type: date.exceptionType == 1 ? .add : .remove
                )
            }
            
            let sortedDates = dates.map { $0.date }.sorted()
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            
            let activePeriod = ActivePeriod(
                begin: dateFormatter.string(from: sortedDates.first!),
                end: dateFormatter.string(from: sortedDates.last!)
            )
            
            return VehicleCalendar(
                weekPattern: createWeekPattern(from: dates),
                exceptions: exceptions,
                activePeriods: [activePeriod]
            )
        }
    }
    
    private func createWeekPattern(from dates: [CalendarDate]) -> WeekPattern {
        let calendar = Calendar.current
        var weekdayCounts = [Int: Int]()
        
        dates.forEach { date in
            let weekday = calendar.component(.weekday, from: date.date)
            weekdayCounts[weekday, default: 0] += 1
        }
        
        return WeekPattern(
            monday: weekdayCounts[2, default: 0] > 0,
            tuesday: weekdayCounts[3, default: 0] > 0,
            wednesday: weekdayCounts[4, default: 0] > 0,
            thursday: weekdayCounts[5, default: 0] > 0,
            friday: weekdayCounts[6, default: 0] > 0,
            saturday: weekdayCounts[7, default: 0] > 0,
            sunday: weekdayCounts[1, default: 0] > 0
        )
    }
}

extension VehicleJourneyHelper {
    public func createVehicleJourneys(from vehicleJourneys: [VehicleJourney], agencies: LocomoSwift.Agencies) -> VehicleJourneys {
        return VehicleJourneys(
            pagination: Pagination(
                totalResult: vehicleJourneys.count,
                startPage: 1,
                itemsPerPage: vehicleJourneys.count,
                itemsOnPage: vehicleJourneys.count
            ),
            feedPublishers: agencies.agencies.map { agency in
                FeedPublisher(
                    id: agency.agencyID ?? "unknown",
                    name: agency.name,
                    url: agency.url.path(),
                    license: "OpenData License"
                )
            },
            disruptions: [],
            context: Context(
                currentDatetime: Date().description,
                timezone: TimeZone.current.identifier
            ),
            vehicleJourneys: vehicleJourneys,
            links: [
                Link(
                    href: "api/v1/vehicle_journeys",
                    templated: false,
                    rel: "self",
                    type: "application/json"
                )
            ]
        )
    }
}
