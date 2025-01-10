//
//  DateFormatters.swift
//  RailMapAPI
//
//  Created by Jérémie Patot on 10/01/2025.
//

import Foundation

public struct DateFormatters {
    static let yearMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()
    
    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    static let localTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss'UTC'Z"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
    
    static func utcTimeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss'UTC'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)!
        return formatter
    }
    
    static func agencyTimeFormatter(timezone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss'UTC'Z"
        formatter.timeZone = timezone
        return formatter
    }
}
