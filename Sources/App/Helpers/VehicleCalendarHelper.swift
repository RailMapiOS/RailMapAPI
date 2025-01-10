//
//  VehicleCalendarHelper.swift
//  RailMapAPI
//
//  Created by Jérémie Patot on 10/01/2025.
//

import Foundation
import LocomoSwift

/// A helper struct for creating and managing vehicle calendars
struct VehicleCalendarHelper {
    /// Creates vehicle calendars from calendar dates for a specific service
    /// - Parameters:
    ///   - calendarDates: Array of calendar dates to process
    ///   - serviceID: The service ID to filter dates for
    /// - Returns: Array of VehicleCalendar objects grouped by month
    static func createVehicleCalendars(from calendarDates: [CalendarDate],
                                     serviceID: String) -> [VehicleCalendar] {
        let serviceCalendarDates = calendarDates.filter { $0.serviceID == serviceID }
        return groupAndCreateCalendars(from: serviceCalendarDates)
    }
    
    /// Groups dates by month and creates calendar objects
    private static func groupAndCreateCalendars(
        from dates: [CalendarDate]
    ) -> [VehicleCalendar] {
        let groupedDates = groupDatesByMonth(dates)
        return groupedDates.map(createCalendarForMonth)
    }
    
    /// Groups calendar dates by month
    private static func groupDatesByMonth(
        _ dates: [CalendarDate]
    ) -> [String: [CalendarDate]] {
        Dictionary(grouping: dates) { date -> String in
            date.date.formatAsYearMonth()
        }
    }
    
    /// Creates a VehicleCalendar for a specific month
    private static func createCalendarForMonth(
        month: String,
        dates: [CalendarDate]
    ) -> VehicleCalendar {
        VehicleCalendar(
            weekPattern: createWeekPattern(from: dates),
            exceptions: createExceptions(from: dates),
            activePeriods: [createActivePeriod(forMonth: month, dates: dates)]
        )
    }
    
    /// Creates a week pattern based on the dates provided
    private static func createWeekPattern(from dates: [CalendarDate]) -> WeekPattern {
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
    
    /// Creates exceptions from calendar dates
    private static func createExceptions(from dates: [CalendarDate]) -> [Exception] {
        dates.map { date in
            return Exception(
                datetime: DateFormatters.fullDate.string(from: date.date),
                type: date.exceptionType == 1 ? .add : .remove
            )
        }
    }
    
    /// Creates an active period for the given month and dates
    private static func createActivePeriod(forMonth month: String, dates: [CalendarDate]) -> ActivePeriod {
        let sortedDates = dates.map { $0.date }.sorted()
        
        return ActivePeriod(
            begin: DateFormatters.fullDate.string(from: sortedDates.first!),
            end: DateFormatters.fullDate.string(from: sortedDates.last!)
        )
    }
}
