import Vapor
import Foundation
import LocomoSwift

//func routes(_ app: Application) throws {
//
//    let journeyStation = JourneyStation()
//
//    app.get("stop", ":headsign") { req async throws -> VehicleJourneys in
//        // Récupère le headsign de la requête
//        guard let headsign = req.parameters.get("headsign") else {
//            throw Abort(.badRequest, reason: "Headsign manquant")
//        }
//
//        print("Recherche du headsign : \(headsign)")
//
//        // Vérifie si le headsign est déjà dans le cache
//        if let cachedJourney = journeyStation.getJourney(for: JourneyKey.headsign(headsign)) {
//            print("Headsign trouvé dans le cache")
//            // Si le headsign est dans le cache, renvoie le VehicleJourney
//            return VehicleJourneys(
//                pagination: Pagination(totalResult: 1, startPage: 1, itemsPerPage: 1, itemsOnPage: 1),
//                feedPublishers: [],
//                disruptions: [],
//                context: Context(currentDatetime: Date().description, timezone: TimeZone.current.identifier),
//                vehicleJourneys: [cachedJourney],
//                links: []
//            )
//        }
//
//        // URL du fichier GTFS
//        let feedURLString = "https://eu.ftp.opendatasoft.com/sncf/gtfs/export-ter-gtfs-last.zip"
//
//        // Télécharge et charge le flux GTFS
//        let vehicleJourneys: VehicleJourneys = try await withCheckedThrowingContinuation { continuation in
//            do {
//                let feed = try Feed(contentsOfURL: URL(string: feedURLString)!)
//                print("Feed chargé avec succès")
//
//                // Récupérer le fuseau horaire de l'agence, ou UTC par défaut
//                let agencyTimezone = getAgencyTimezone(from: feed)
//
//                // Filtrer les trips basés sur le headsign fourni
//                let trips = feed.trips?.filter { $0.headSign == headsign } ?? []
//
//                if trips.isEmpty {
//                    continuation.resume(throwing: Abort(.notFound, reason: "Aucun trajet trouvé pour le headsign \(headsign)"))
//                    return
//                }
//
//                // Obtenir les patterns de validité pour chaque trip
//                let calendarDates = feed.calendarDates?.dates ?? []
//
//                // Construction de VehicleJourneys en fonction du headsign
//                let vehicleJourneys = VehicleJourneys(
//                    pagination: Pagination(
//                        totalResult: trips.count,
//                        startPage: 1,
//                        itemsPerPage: trips.count,
//                        itemsOnPage: trips.count
//                    ),
//                    feedPublishers: [
//                        FeedPublisher(id: "1", name: "SNCF", url: "https://sncf.com", license: "OpenData License")
//                    ],
//                    disruptions: [],
//                    context: Context(currentDatetime: Date().description, timezone: TimeZone.current.identifier),
//                    vehicleJourneys: trips.map { trip in
//                        // Pour chaque trip, récupérer les stopTimes associés
//                        let stopTimes = feed.stopTimes?.filter { $0.tripID == trip.tripID } ?? []
//
//                        // Extraire la validité du service à partir de `calendar_dates`
//                        let validDates = calendarDates.filter { $0.serviceID == trip.serviceID }
//                        let validityPattern = constructValidityPattern(from: validDates)
//
//                        // Map des stopTimes dans le format attendu par le modèle VehicleJourney
//                        let vehicleStopTimes = stopTimes.map { stopTime -> VehicleStopTime in
//                            // Convertir les heures locales en UTC
//                            let utcArrivalTime = stopTime.arrival?.addingTimeInterval(-TimeInterval(agencyTimezone.secondsFromGMT(for: stopTime.arrival!))) ?? Date()
//                            let utcDepartureTime = stopTime.departure?.addingTimeInterval(-TimeInterval(agencyTimezone.secondsFromGMT(for: stopTime.departure!))) ?? Date()
//
//                            print("Times (Local): \(stopTime.arrival) - \(stopTime.departure)")
//                            print("Times (UTC): \(utcArrivalTime) - \(utcDepartureTime)")
//
//                            return VehicleStopTime(
//                                arrivalTime: stopTime.arrival?.ISO8601Format() ?? "",
//                                utcArrivalTime: utcArrivalTime.ISO8601Format() ?? "",
//                                departureTime: stopTime.departure?.ISO8601Format() ?? "",
//                                utcDepartureTime: utcDepartureTime.ISO8601Format() ?? "",
//                                headsign: (stopTime.stopHeadingSign ?? trip.headSign) ?? "",
//                                stopPoint: StopPoint(
//                                    id: stopTime.stopID,
//                                    name: feed.stops?.first(where: { $0.stopID == stopTime.stopID })?.name ?? "Unknown",
//                                    codes: [Code(type: .gtfsStopCode, value: stopTime.stopID)],
//                                    label: feed.stops?.first(where: { $0.stopID == stopTime.stopID })?.name ?? "Unknown",
//                                    coord: Coord(
//                                        lon: feed.stops?.first(where: { $0.stopID == stopTime.stopID })?.longitude?.formatted() ?? "0.0",
//                                        lat: feed.stops?.first(where: { $0.stopID == stopTime.stopID })?.latitude?.formatted() ?? "0.0"
//                                    ),
//                                    links: [],
//                                    equipments: []
//                                ),
//                                pickupAllowed: stopTime.pickupType == 0,
//                                dropOffAllowed: stopTime.dropOffType == 0,
//                                skippedStop: false
//                            )
//                        }
//
//                        let vehicleJourney = VehicleJourney(
//                            id: trip.tripID,
//                            name: trip.headSign ?? "",
//                            journeyPattern: JourneyPattern(id: trip.tripID, name: trip.headSign ?? ""),
//                            stopTimes: vehicleStopTimes,
//                            codes: [Code(type: .source, value: "GTFS")],
//                            validityPattern: validityPattern,
//                            calendars: [],
//                            trip: JourneyPattern(id: trip.tripID, name: trip.headSign ?? ""),
//                            disruptions: [],
//                            headsign: trip.headSign ?? ""
//                        )
//
//                        journeyStation.addJourney(vehicleJourney)
//
//                        return vehicleJourney
//                    },
//                    links: [
//                        Link(href: "https://sncf.com", templated: false, rel: "self", type: "application/json")
//                    ]
//                )
//
//                continuation.resume(returning: vehicleJourneys)
//
//            } catch {
//                print("Erreur lors du chargement du feed : \(error)")
//                continuation.resume(throwing: error)
//            }
//        }
//
//        return vehicleJourneys
//    }
//
//    // Route de test
//    app.get("hello") { req async -> String in
//        return "Hello, world!"
//    }
//
//    func getAgencyTimezone(from feed: Feed) -> TimeZone {
//        // Récupérer le fuseau horaire de l'agence s'il est disponible
//        if let agency = feed.agencies?.agencies.first {
//            let timeZone = agency.timeZone
//            print("Agency TimeZone : \(timeZone)")
//            return timeZone
//        }
//        // Retourner UTC par défaut si non trouvé
//        print("UTC TimeZone")
//        return TimeZone(secondsFromGMT: 0)!
//    }
//
//    func constructValidityPattern(from calendarDates: [CalendarDate]) -> ValidityPattern {
//        let formattedDates = calendarDates.map { $0.date.ISO8601Format() }.joined(separator: ", ")
//        return ValidityPattern(beginningDate: formattedDates, days: "Custom Dates")
//    }
//}

func routes(_ app: Application) throws {
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
