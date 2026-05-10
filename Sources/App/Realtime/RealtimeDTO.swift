//
//  RealtimeDTO.swift
//  RailMapAPI
//
//  GTFS-RT v2.0 schema fully exposed to API clients.
//
//  Design notes:
//  - Backward-compatible with older clients: the original flat fields
//    (`tripID`, `vehicleID`, `headerText`…) are kept at their existing position.
//  - Richer nested structures (`trip`, `vehicle`, `tripProperties`, etc.) sit
//    beside them so newer clients can opt into the full payload.
//  - `TranslatedString` payloads ship resolved-for-locale text PLUS the full
//    translations dict so the client can switch language without re-querying.
//

import Vapor
import LocomoSwift

// MARK: - Translated content

/// `TranslatedString` flattened to JSON.
///
/// Shape:
/// ```
/// { "text": "Travaux en gare", "translations": {"fr": "Travaux en gare", "en": "Station works"} }
/// ```
/// `text` is resolved for the request locale (`?lang=fr` / `Accept-Language` /
/// fallback) so simple consumers don't have to walk the dict.
struct TranslatedStringDTO: Content {
    let text: String
    let translations: [String: String]

    init(from value: TranslatedString, locale: Locale) {
        self.text = value.text(for: locale) ?? ""
        var dict: [String: String] = [:]
        for translation in value.translations {
            let key = translation.language ?? ""
            // Keep the first occurrence per language code.
            if dict[key] == nil { dict[key] = translation.text }
        }
        self.translations = dict
    }
}

struct LocalizedImageDTO: Content {
    let url: String
    let mediaType: String
    let language: String?
}

struct TranslatedImageDTO: Content {
    /// URL resolved for the request locale, when at least one image matches.
    let url: String?
    /// All localized variants — useful for fetching a different language asset.
    let images: [LocalizedImageDTO]

    init(from value: TranslatedImage, locale: Locale) {
        self.url = value.image(for: locale)?.url.absoluteString
        self.images = value.images.map {
            LocalizedImageDTO(
                url: $0.url.absoluteString,
                mediaType: $0.mediaType,
                language: $0.language
            )
        }
    }
}

// MARK: - Descriptors

struct VehicleDescriptorDTO: Content {
    let id: String?
    let label: String?
    let licensePlate: String?
    /// Raw value of ``WheelchairAccessible``: 0 noValue, 1 unknown,
    /// 2 accessible, 3 inaccessible.
    let wheelchairAccessible: Int?

    init(from desc: RealtimeVehicleDescriptor) {
        self.id = desc.id
        self.label = desc.label
        self.licensePlate = desc.licensePlate
        self.wheelchairAccessible = desc.wheelchairAccessible?.rawValue
    }
}

struct TripDescriptorDTO: Content {
    let tripID: String?
    let routeID: String?
    let directionID: UInt32?
    let startTime: String?
    let startDate: String?
    /// Raw value of ``TripScheduleRelationship``.
    let scheduleRelationship: Int?
    let modifiedTrip: ModifiedTripSelectorDTO?

    struct ModifiedTripSelectorDTO: Content {
        let modificationsID: String?
        let affectedTripID: String?
        let startTime: String?
        let startDate: String?
    }

    init(from desc: RealtimeTripDescriptor) {
        self.tripID = desc.tripID
        self.routeID = desc.routeID
        self.directionID = desc.directionID
        self.startTime = desc.startTime
        self.startDate = desc.startDate
        self.scheduleRelationship = desc.scheduleRelationship?.rawValue
        if let m = desc.modifiedTrip {
            self.modifiedTrip = ModifiedTripSelectorDTO(
                modificationsID: m.modificationsID,
                affectedTripID: m.affectedTripID,
                startTime: m.startTime,
                startDate: m.startDate
            )
        } else {
            self.modifiedTrip = nil
        }
    }
}

struct TripPropertiesDTO: Content {
    let tripID: String?
    let startDate: String?
    let startTime: String?
    let shapeID: String?
    let tripHeadsign: String?
    let tripShortName: String?

    init(from props: RealtimeTripProperties) {
        self.tripID = props.tripID
        self.startDate = props.startDate
        self.startTime = props.startTime
        self.shapeID = props.shapeID
        self.tripHeadsign = props.tripHeadsign
        self.tripShortName = props.tripShortName
    }
}

// MARK: - StopTime

struct StopTimeEventDTO: Content {
    let delay: Int32?
    let time: Date?
    let uncertainty: Int32?
    /// Scheduled time for NEW / REPLACEMENT / DUPLICATED trips.
    let scheduledTime: Date?

    init(from event: RealtimeStopTimeEvent) {
        self.delay = event.delay
        self.time = event.time
        self.uncertainty = event.uncertainty
        self.scheduledTime = event.scheduledTime
    }
}

struct StopTimePropertiesDTO: Content {
    /// Real-time stop reassignment (e.g. platform change).
    let assignedStopID: String?
    let stopHeadsign: String?
    /// Raw value of ``DropOffPickupType``.
    let pickupType: Int?
    let dropOffType: Int?

    init(from props: RealtimeStopTimeProperties) {
        self.assignedStopID = props.assignedStopID
        self.stopHeadsign = props.stopHeadsign
        self.pickupType = props.pickupType?.rawValue
        self.dropOffType = props.dropOffType?.rawValue
    }
}

// MARK: - Carriage details (multi-carriage trains: TGV duplex, ICE…)

struct CarriageDetailsDTO: Content {
    let id: String?
    let label: String?
    /// Raw value of ``OccupancyStatus``.
    let occupancyStatus: Int?
    /// Integer 0–100, or `nil` when not provided.
    let occupancyPercentage: Int32?
    /// Order in the direction of travel (1 = first car).
    let carriageSequence: UInt32

    init(from car: CarriageDetails) {
        self.id = car.id
        self.label = car.label
        self.occupancyStatus = car.occupancyStatus?.rawValue
        self.occupancyPercentage = car.occupancyPercentage
        self.carriageSequence = car.carriageSequence
    }
}

// MARK: - Realtime shapes (encoded polylines for detours)

struct RealtimeShapeDTO: Content {
    let id: String
    let encodedPolyline: String

    init(from shape: RealtimeShape) {
        self.id = shape.id
        self.encodedPolyline = shape.encodedPolyline
    }
}

// MARK: - Trip Update DTOs

struct TripUpdatesResponse: Content {
    let source: String
    let tripUpdates: [TripUpdateDTO]
}

struct TripUpdateDTO: Content {
    // --- Existing flat conveniences (kept for backward compat) ---
    let tripID: String
    let routeID: String?
    let scheduleRelationship: Int
    let delay: Int32?
    let timestamp: Date
    let vehicleID: String?
    let stopTimeUpdates: [StopTimeUpdateDTO]

    // --- Full GTFS-RT v2.0 surface ---
    let trip: TripDescriptorDTO
    let vehicle: VehicleDescriptorDTO?
    let tripProperties: TripPropertiesDTO?
}

struct StopTimeUpdateDTO: Content {
    // --- Existing flat conveniences ---
    let stopID: String
    let stopSequence: UInt32?
    let arrivalDelay: Int32?
    let arrivalTime: Date?
    let departureDelay: Int32?
    let departureTime: Date?
    let scheduleRelationship: Int

    /// Announced platform / track number, when published by the operator.
    let platform: String?

    // --- Full GTFS-RT v2.0 surface ---
    let arrival: StopTimeEventDTO?
    let departure: StopTimeEventDTO?
    /// Expected occupancy after departure from this stop (raw `OccupancyStatus`).
    let departureOccupancyStatus: Int?
    let stopTimeProperties: StopTimePropertiesDTO?
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

    // --- Existing convenience: resolved-for-locale text strings (kept) ---
    let url: String?
    let headerText: String?
    let descriptionText: String?

    let activePeriods: [TimePeriodDTO]
    let informedEntities: [EntityDTO]

    // --- Full GTFS-RT v2.0 surface ---
    let severityLevel: Int?
    /// Translated payloads with all language variants exposed.
    let urlTranslated: TranslatedStringDTO?
    let headerTextTranslated: TranslatedStringDTO?
    let descriptionTextTranslated: TranslatedStringDTO?
    /// Text-to-speech variants — useful for Apple Watch / accessibility.
    let ttsHeaderText: TranslatedStringDTO?
    let ttsDescriptionText: TranslatedStringDTO?
    /// Free-form, agency-specific cause/effect descriptions.
    let causeDetail: TranslatedStringDTO?
    let effectDetail: TranslatedStringDTO?
    /// Translated graphics (signage, accessibility maps…).
    let image: TranslatedImageDTO?
    let imageAlternativeText: TranslatedStringDTO?
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
    /// Full trip descriptor when the producer attached one — exposes the
    /// route/direction/start dates that the flat `tripID` doesn't carry.
    let trip: TripDescriptorDTO?
}

// MARK: - Vehicle Position DTOs

struct VehiclePositionsResponse: Content {
    let source: String
    let vehiclePositions: [VehiclePositionDTO]
}

struct VehiclePositionDTO: Content {
    // --- Existing flat conveniences ---
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

    // --- Full GTFS-RT v2.0 surface ---
    let trip: TripDescriptorDTO?
    let vehicle: VehicleDescriptorDTO
    let stopID: String?
    let odometer: Double?
    /// Raw value of ``CongestionLevel`` — traffic congestion affecting the vehicle.
    /// Distinct from `occupancyStatus` (passenger crowding).
    let congestionLevel: Int?
    /// Onboard occupancy as integer 0–100.
    let occupancyPercentage: UInt32?
    /// Per-carriage details (TGV duplex, Eurostar e320, ICE…).
    let multiCarriageDetails: [CarriageDetailsDTO]
}

// MARK: - Realtime feed envelope (whole feed in one shot)

struct RealtimeFeedHeaderDTO: Content {
    let gtfsRealtimeVersion: String
    /// Raw value of ``Incrementality``: 0 fullDataset, 1 differential.
    let incrementality: Int
    let timestamp: Date?
    let feedVersion: String?
}

struct RealtimeFeedResponse: Content {
    let source: String
    /// Which GTFS-RT feed type was fetched (`tripUpdates`, `vehiclePositions`,
    /// `serviceAlerts`).
    let feedType: String
    let header: RealtimeFeedHeaderDTO
    let tripUpdates: [TripUpdateDTO]
    let vehiclePositions: [VehiclePositionDTO]
    let serviceAlerts: [AlertDTO]
    let shapes: [RealtimeShapeDTO]
    /// Identifiers of `FeedEntity` records marked `isDeleted = true`.
    /// Only meaningful when `header.incrementality == 1` (differential).
    let deletedEntityIDs: [String]
}

struct ShapesResponse: Content {
    let source: String
    let shapes: [RealtimeShapeDTO]
}

// MARK: - Conversions from LocomoSwift 1.2.0+ types

extension TripUpdateDTO {
    init(from update: RealtimeTripUpdate) {
        self.init(from: update, platformResolver: { _ in nil })
    }

    init(from update: RealtimeTripUpdate, platformResolver: (String) -> String?) {
        self.tripID = update.tripID ?? ""
        self.routeID = update.routeID
        self.scheduleRelationship = update.scheduleRelationship?.rawValue ?? 0
        self.delay = update.delay
        self.timestamp = update.timestamp ?? Date()
        self.vehicleID = update.vehicleID
        self.stopTimeUpdates = update.stopTimeUpdates.map {
            StopTimeUpdateDTO(from: $0, platform: $0.stopID.flatMap(platformResolver))
        }
        self.trip = TripDescriptorDTO(from: update.trip)
        self.vehicle = update.vehicle.map(VehicleDescriptorDTO.init(from:))
        self.tripProperties = update.tripProperties.map(TripPropertiesDTO.init(from:))
    }
}

extension StopTimeUpdateDTO {
    init(from stu: RealtimeStopTimeUpdate) {
        self.init(from: stu, platform: nil)
    }

    init(from stu: RealtimeStopTimeUpdate, platform: String?) {
        self.stopID = stu.stopID ?? ""
        self.stopSequence = stu.stopSequence
        self.arrivalDelay = stu.arrivalDelay
        self.arrivalTime = stu.arrivalTime
        self.departureDelay = stu.departureDelay
        self.departureTime = stu.departureTime
        self.scheduleRelationship = stu.scheduleRelationship.rawValue
        self.platform = platform
        self.arrival = stu.arrival.map(StopTimeEventDTO.init(from:))
        self.departure = stu.departure.map(StopTimeEventDTO.init(from:))
        self.departureOccupancyStatus = stu.departureOccupancyStatus?.rawValue
        self.stopTimeProperties = stu.stopTimeProperties.map(StopTimePropertiesDTO.init(from:))
    }
}

extension AlertDTO {
    /// Locale used to flatten ``TranslatedString`` payloads into the JSON
    /// response. Defaults to the runtime current locale.
    init(from alert: RealtimeServiceAlert, locale: Locale = .current) {
        self.alertID = alert.alertID
        self.cause = alert.cause?.rawValue
        self.effect = alert.effect?.rawValue
        self.url = alert.url?.text(for: locale)
        self.headerText = alert.headerText?.text(for: locale)
        self.descriptionText = alert.descriptionText?.text(for: locale)
        self.activePeriods = alert.activePeriods.map { TimePeriodDTO(start: $0.start, end: $0.end) }
        self.informedEntities = alert.informedEntities.map { EntityDTO(from: $0) }

        self.severityLevel = alert.severityLevel?.rawValue
        self.urlTranslated = alert.url.map { TranslatedStringDTO(from: $0, locale: locale) }
        self.headerTextTranslated = alert.headerText.map { TranslatedStringDTO(from: $0, locale: locale) }
        self.descriptionTextTranslated = alert.descriptionText.map { TranslatedStringDTO(from: $0, locale: locale) }
        self.ttsHeaderText = alert.ttsHeaderText.map { TranslatedStringDTO(from: $0, locale: locale) }
        self.ttsDescriptionText = alert.ttsDescriptionText.map { TranslatedStringDTO(from: $0, locale: locale) }
        self.causeDetail = alert.causeDetail.map { TranslatedStringDTO(from: $0, locale: locale) }
        self.effectDetail = alert.effectDetail.map { TranslatedStringDTO(from: $0, locale: locale) }
        self.image = alert.image.map { TranslatedImageDTO(from: $0, locale: locale) }
        self.imageAlternativeText = alert.imageAlternativeText.map { TranslatedStringDTO(from: $0, locale: locale) }
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
        self.trip = entity.trip.map(TripDescriptorDTO.init(from:))
    }
}

extension VehiclePositionDTO {
    init(from vp: RealtimeVehiclePosition) {
        self.tripID = vp.tripID
        self.vehicleID = vp.vehicleID ?? ""
        self.latitude = vp.latitude
        self.longitude = vp.longitude
        self.bearing = vp.bearing
        self.speed = vp.speed
        self.currentStopSequence = vp.currentStopSequence
        self.currentStatus = vp.currentStatus.rawValue
        self.timestamp = vp.timestamp ?? Date()
        self.occupancyStatus = vp.occupancyStatus?.rawValue

        self.trip = vp.trip.map(TripDescriptorDTO.init(from:))
        self.vehicle = VehicleDescriptorDTO(from: vp.vehicle)
        self.stopID = vp.stopID
        self.odometer = vp.odometer
        self.congestionLevel = vp.congestionLevel?.rawValue
        self.occupancyPercentage = vp.occupancyPercentage
        self.multiCarriageDetails = vp.multiCarriageDetails.map(CarriageDetailsDTO.init(from:))
    }
}

extension RealtimeFeedHeaderDTO {
    init(from header: RealtimeFeedHeader) {
        self.gtfsRealtimeVersion = header.gtfsRealtimeVersion
        self.incrementality = header.incrementality.rawValue
        self.timestamp = header.timestamp
        self.feedVersion = header.feedVersion
    }
}
