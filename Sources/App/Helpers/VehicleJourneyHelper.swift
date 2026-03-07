import Foundation
import LocomoSwift

/// Static helper for transforming GTFS data into VehicleJourney API response models.
/// Uses pre-built stop lookup dictionaries and cached formatters for performance.
enum VehicleJourneyHelper {

    // MARK: - Cached formatters (allocated once, reused across calls)

    private static let agencyTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let utcTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = TimeZone(secondsFromGMT: 0)!
        return f
    }()

    // MARK: - Public API

    static func createVehicleStopTime(
        from stopTime: StopTime,
        trip: Trip,
        stopLookup: [String: Stop],
        agencyTimezone: TimeZone
    ) -> VehicleStopTime {
        agencyTimeFormatter.timeZone = agencyTimezone

        let arrivalDate = stopTime.arrival ?? Date()
        let departureDate = stopTime.departure ?? Date()
        let stop = stopLookup[stopTime.stopID]

        let stopName = stop?.name ?? "Unknown"

        return VehicleStopTime(
            arrivalTime: agencyTimeFormatter.string(from: arrivalDate),
            utcArrivalTime: utcTimeFormatter.string(from: arrivalDate),
            departureTime: agencyTimeFormatter.string(from: departureDate),
            utcDepartureTime: utcTimeFormatter.string(from: departureDate),
            headsign: (stopTime.stopHeadingSign ?? trip.headSign) ?? "",
            stopPoint: StopPoint(
                id: stopTime.stopID,
                name: stopName,
                codes: [Code(type: .gtfsStopCode, value: stopTime.stopID)],
                label: stopName,
                coord: Coord(
                    lon: stop?.longitude?.formatted() ?? "0.0",
                    lat: stop?.latitude?.formatted() ?? "0.0"
                ),
                links: [],
                equipments: []
            ),
            pickupAllowed: stopTime.pickupType == 0,
            dropOffAllowed: stopTime.dropOffType == 0,
            skippedStop: false
        )
    }

    static func createVehicleJourney(
        from trip: Trip,
        feed: Feed,
        calendarDates: [CalendarDate],
        stopLookup: [String: Stop],
        agencyTimezone: TimeZone
    ) -> VehicleJourney {
        let stopTimes = feed.stopTimes?.filter { $0.tripID == trip.tripID } ?? []
        let validDates = calendarDates.filter { $0.serviceID == trip.serviceID }
        let validityPattern = constructValidityPattern(from: validDates)
        let vehicleCalendars = createVehicleCalendars(from: calendarDates, serviceID: trip.serviceID)

        let vehicleStopTimes = stopTimes.map { stopTime in
            createVehicleStopTime(from: stopTime, trip: trip, stopLookup: stopLookup, agencyTimezone: agencyTimezone)
        }

        let headsign = trip.headSign ?? ""
        return VehicleJourney(
            id: trip.tripID,
            name: headsign,
            journeyPattern: JourneyPattern(id: trip.tripID, name: headsign),
            stopTimes: vehicleStopTimes,
            codes: [Code(type: .source, value: "GTFS")],
            validityPattern: validityPattern,
            calendars: vehicleCalendars,
            trip: JourneyPattern(id: trip.tripID, name: headsign),
            disruptions: [],
            headsign: headsign
        )
    }

    static func createVehicleJourneys(from vehicleJourneys: [VehicleJourney], agencies: LocomoSwift.Agencies) -> VehicleJourneys {
        VehicleJourneys(
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
                Link(href: "api/v1/vehicle_journeys", templated: false, rel: "self", type: "application/json")
            ]
        )
    }

    // MARK: - Private helpers

    private static func constructValidityPattern(from calendarDates: [CalendarDate]) -> ValidityPattern {
        let formattedDates = calendarDates.map { $0.date.ISO8601Format() }.joined(separator: ", ")
        return ValidityPattern(beginningDate: formattedDates, days: "Custom Dates")
    }

    private static func createVehicleCalendars(from calendarDates: [CalendarDate], serviceID: String) -> [VehicleCalendar] {
        let serviceCalendarDates = calendarDates.filter { $0.serviceID == serviceID }

        let groupedDates = Dictionary(grouping: serviceCalendarDates) { date -> String in
            DateFormatters.yearMonth.string(from: date.date)
        }

        return groupedDates.map { _, dates in
            let exceptions = dates.map { date in
                Exception(
                    datetime: DateFormatters.fullDate.string(from: date.date),
                    type: date.exceptionType == 1 ? .add : .remove
                )
            }

            let sortedDates = dates.map(\.date).sorted()
            let activePeriod = ActivePeriod(
                begin: DateFormatters.fullDate.string(from: sortedDates.first!),
                end: DateFormatters.fullDate.string(from: sortedDates.last!)
            )

            return VehicleCalendar(
                weekPattern: createWeekPattern(from: dates),
                exceptions: exceptions,
                activePeriods: [activePeriod]
            )
        }
    }

    private static func createWeekPattern(from dates: [CalendarDate]) -> WeekPattern {
        let counts = dates.weekdayCounts()
        return WeekPattern(
            monday: counts[2, default: 0] > 0,
            tuesday: counts[3, default: 0] > 0,
            wednesday: counts[4, default: 0] > 0,
            thursday: counts[5, default: 0] > 0,
            friday: counts[6, default: 0] > 0,
            saturday: counts[7, default: 0] > 0,
            sunday: counts[1, default: 0] > 0
        )
    }
}
