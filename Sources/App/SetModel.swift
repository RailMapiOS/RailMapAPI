import Foundation

enum JourneyKey: Hashable, Sendable {
    case tripID(String)
    case headsign(String)
    case serviceID(String)
}

actor JourneyStation {
    private var journeyCache: [JourneyKey: VehicleJourneys] = [:]

    func addJourneys(_ journeys: VehicleJourneys, for key: JourneyKey) {
        journeyCache[key] = journeys
    }

    func getJourneys(for key: JourneyKey) -> VehicleJourneys? {
        journeyCache[key]
    }

    func removeJourneys(for key: JourneyKey) {
        journeyCache.removeValue(forKey: key)
    }
}
