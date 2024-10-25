//
//  SetModel.swift
//  RailMapAPI
//
//  Created by Jérémie Patot on 04/10/2024.
//

import Foundation

enum JourneyKey: Hashable {
    case tripID(String)
    case headsign(String)
    case serviceID(String)
}

public final class JourneyStation {
    private var journeyCache: [JourneyKey: VehicleJourneys] = [:]
    private let queue = DispatchQueue(label: "com.journeystation.threadsafe", attributes: .concurrent)
    
    // Méthode pour ajouter des trajets au cache
    func addJourneys(_ journeys: VehicleJourneys, for key: JourneyKey) {
        queue.async(flags: .barrier) {
            print("VehicleJourneys stopTimes: \(journeys.vehicleJourneys.first?.stopTimes.count)")
            self.journeyCache[key] = journeys
        }
    }
    
    // Méthode pour récupérer des trajets depuis le cache
    func getJourneys(for key: JourneyKey) -> VehicleJourneys? {
        return queue.sync {
            return self.journeyCache[key]
        }
    }
    
    // Méthode pour supprimer des trajets du cache
    func removeJourneys(for key: JourneyKey) {
        queue.async(flags: .barrier) {
            self.journeyCache.removeValue(forKey: key)
        }
    }
}
