//
//  CalendarDates.swift
//  RailMapAPI
//
//  Created by Jérémie Patot on 10/01/2025.
//

import Fluent
import LocomoSwift
import Vapor

/// A database model representing a calendar date entry from GTFS calendar_dates.txt
///
/// This model stores information about service exceptions for specific dates, indicating whether
/// a service operates or not on particular dates.
///
/// - Note: The exception_type value of 1 indicates service is added, while 2 indicates service removal
final class CalendarDateRecord: Model, Content {
    static let schema = "calendar_dates"
    
    /// The unique identifier for this calendar date record
    @ID(custom: "id")
    var id: UUID?
    
    /// The service identifier this calendar date applies to
    @Field(key: "service_id")
    var serviceID: String
    
    /// The date for which this exception applies
    @Field(key: "date")
    var date: Date
    
    /// The type of exception (1 = service added, 2 = service removed)
    @Field(key: "exception_type")
    var exceptionType: Int
    
    /// The feed this calendar date belongs to
    @Parent(key: "feed_id")
    var feed: FeedRecord
    
    init() {}
    
    /// Creates a new calendar date record
    /// - Parameters:
    ///   - serviceID: The service identifier
    ///   - date: The date of the exception
    ///   - exceptionType: The type of exception
    ///   - feedID: The ID of the parent feed
    init(serviceID: String, date: Date, exceptionType: Int, feedID: UUID) {
        self.serviceID = serviceID
        self.date = date
        self.exceptionType = exceptionType
        self.$feed.id = feedID
    }
    
    func toCalendarDate() -> CalendarDate {
        return CalendarDate(
            serviceID: self.serviceID,
            date: self.date,
            exceptionType: self.exceptionType
        )
    }
}
