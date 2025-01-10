//
//  DateExt.swift
//  RailMapAPI
//
//  Created by Jérémie Patot on 10/01/2025.
//

import Foundation
import LocomoSwift

// MARK: - Date Extension
extension Date {
    /// Formats date as "yyyy-MM"
    func formatAsYearMonth() -> String {
        let formatter = DateFormatters.yearMonth
        return formatter.string(from: self)
    }
    
    /// Formats date as "yyyy-MM-dd"
    func formatAsFullDate() -> String {
        let formatter = DateFormatters.fullDate
        return formatter.string(from: self)
    }
}

extension Array where Element == CalendarDate {
    /// Groups dates by weekday and counts occurrences
    func weekdayCounts() -> [Int: Int] {
        reduce(into: [:]) { counts, date in
            let weekday = Calendar.current.component(.weekday, from: date.date)
            counts[weekday, default: 0] += 1
        }
    }
}
