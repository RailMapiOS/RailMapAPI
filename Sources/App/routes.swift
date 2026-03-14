import Vapor
import Foundation
import LocomoSwift

func routes(_ app: Application, realtimeManager: RealtimeManager) throws {
    // Register GTFS Realtime routes
    realtimeRoutes(app, realtimeManager: realtimeManager)

    let journeyStation = JourneyStation()
    let VJH = VehicleJourneyHelper()
    
    app.get("stop", ":headsign") { req async throws -> VehicleJourneys in
        let feedManager = try FeedManager(database: req.db)
        
        // Récupération des paramètres `headsign`
        guard let headsign = req.parameters.get("headsign") else {
            throw Abort(.badRequest, reason: "Headsign manquant")
        }
        
        // Récupération des paramètres `agency` et `serviceType`
        let agencyParam = req.query[String.self, at: "agency"]
        let serviceTypeParam = req.query[String.self, at: "serviceType"]
        
        // Validation des paramètres `agency` et `serviceType` des GTFSEndpoints
        guard let agency = agencyParam.flatMap({ Agencies(rawValue: $0) }),
              let serviceType = serviceTypeParam.flatMap({ ServiceType(rawValue: $0) }) else {
            throw Abort(.badRequest, reason: "Agency ou ServiceType manquant ou invalide")
        }
        
        // Récupération de l'endpoint GTFS correspondant
        guard let endpoint = gtfsEndpoints.first(where: { $0.agency == agency && $0.serviceType == serviceType }) else {
            throw Abort(.notFound, reason: "Endpoint GTFS non trouvé pour l'agence \(agency) et le service \(serviceType)")
        }
        
        // Vérifier si le trajet est en cache
        if let cachedJourneys = journeyStation.getJourneys(for: .headsign(headsign)) {
            return cachedJourneys
        }
        
        // Si le trajet n'est pas en cache, on charge le feed
        let feed = try await feedManager.getFeed(for: endpoint)
        
        // Filtrer les trips par `headsign`
        let trips = feed.trips?.filter { $0.headSign == headsign } ?? []
        if trips.isEmpty {
            throw Abort(.notFound, reason: "Aucun trajet trouvé pour le headsign \(headsign)")
        }

        // Récupérer les agences à partir du feed
        guard let agencies = feed.agencies else {
            throw Abort(.internalServerError, reason: "Les agences sont manquantes dans le feed GTFS.")
        }
        
        // Récupérer les dates de validité associées aux trips
        let calendarDates = feed.calendarDates?.dates ?? []

        // Créer les `VehicleJourneys` à partir des trips et des données du feed
        let vehicleJourneys = trips.map { trip in
            VJH.createVehicleJourney(from: trip, with: feed, calendarDates: calendarDates)
        }

        // Créer l'objet `VehicleJourneys` avec les agences
        let fullVehicleJourneys = VJH.createVehicleJourneys(from: vehicleJourneys, agencies: agencies)
        
        // Mettre en cache les nouveaux trajets
        journeyStation.addJourneys(fullVehicleJourneys, for: .headsign(headsign))
        
        print("Success return fullVehicleJourneys for \(headsign)")
        // Retourner les `VehicleJourneys`
        return fullVehicleJourneys
    }
    
    // Route de test basique
    app.get("hello") { req async -> String in
        return "Hello, world!"
    }
}
