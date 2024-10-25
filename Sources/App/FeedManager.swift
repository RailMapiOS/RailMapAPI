//
//  FeedManager.swift
//  RailMapAPI
//
//  Created by Jérémie Patot on 11/10/2024.
//

import Fluent
import Vapor
import LocomoSwift

public final class FeedManager {
    
    private var feedCache: [GTFSEndpoint: (feed: Feed, lastUpdate: Date)] = [:]  // Cache avec horodatage
    private let db: Database

    init(database: Database) {
        self.db = database
    }

    /// Récupère un `Feed` soit depuis le cache (s'il est encore valide), soit depuis la base de données, soit en le téléchargeant.
    func getFeed(for endpoint: GTFSEndpoint) async throws -> Feed {
        // Vérifier si le feed est dans le cache et encore valide
        if let cachedFeed = feedCache[endpoint] {
            if isFeedStillValid(cachedFeed.lastUpdate, refreshFrequency: endpoint.refreshFrequency) {
                print("Feed trouvé dans le cache et encore valide.")
                return cachedFeed.feed
            } else {
                print("Feed dans le cache, mais expiré. Rafraîchissement en cours.")
            }
        }

        // Vérifier si le feed est dans la base de données
        if let storedFeed = try await loadFeedFromDB(endpoint: endpoint) {
            feedCache[endpoint] = (storedFeed, Date())
            return storedFeed
        }

        // Télécharger le feed s'il n'est ni en cache ni en base de données
        let downloadedFeed = try await downloadFeed(from: endpoint.url)
        try await saveFeedToDB(feed: downloadedFeed, endpoint: endpoint)
        feedCache[endpoint] = (downloadedFeed, Date())  // Mettre en cache avec l'horodatage actuel
        return downloadedFeed
    }

    /// Télécharge un Feed à partir d'une URL.
    private func downloadFeed(from urlString: String) async throws -> Feed {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let feed = try await Feed(contentsOfURL: url)
        print("Feed téléchargé avec succès depuis \(urlString)")
        return feed
    }

    /// Charge un Feed depuis la base de données Fluent.
    private func loadFeedFromDB(endpoint: GTFSEndpoint) async throws -> Feed? {
        guard let record = try await FeedRecord.query(on: db)
            .filter(\.$url == endpoint.url)
            .first()
        else {
            return nil
        }

        // Charger les données liées au Feed depuis la base de données
        let agencies = try await AgencyRecord.query(on: db).filter(\AgencyRecord.$feed.$id == record.id!).all()
        let trips = try await TripRecord.query(on: db).filter(\TripRecord.$feed.$id == record.id!).all()
        let stops = try await StopRecord.query(on: db).filter(\StopRecord.$feed.$id == record.id!).all()
        let stopTimes = try await StopTimeRecord.query(on: db).filter(\StopTimeRecord.$feed.$id == record.id!).with(\.$trip).all()

        // Créer un Feed à partir des données
        return try createFeed(from: agencies, trips: trips, stops: stops, stopTimes: stopTimes)
    }

    /// Sauvegarde un Feed dans la base de données et met à jour l'horodatage de la dernière mise à jour.
    private func saveFeedToDB(feed: Feed, endpoint: GTFSEndpoint) async throws {
        // Rechercher si le feed existe déjà dans la base de données
        if let record = try await FeedRecord.query(on: db)
            .filter(\.$url == endpoint.url)
            .first()
        {
            // Mettre à jour la date de mise à jour
            record.updateLastUpdateDate(to: Date())
            try await record.update(on: db)
        } else {
            // Créer un nouvel enregistrement si aucun n'existe
            let feedRecord = FeedRecord(url: endpoint.url, lastUpdate: Date())
            try await feedRecord.save(on: db)
            
            // Sauvegarder les agences, trips, stops, etc.
            if let agencies = feed.agencies?.agencies {
                try await saveRecords(agencies, feedID: feedRecord.id!, as: AgencyRecord.self)
            } else {
                print("Aucune agence à sauvegarder.")
            }

            if let trips = feed.trips?.trips {
                try await saveRecords(trips, feedID: feedRecord.id!, as: TripRecord.self)
            } else {
                print("Aucun trip à sauvegarder.")
            }

            if let stops = feed.stops?.stops {
                try await saveRecords(stops, feedID: feedRecord.id!, as: StopRecord.self)
            } else {
                print("Aucun stop à sauvegarder.")
            }
            
            if let stopTimes = feed.stopTimes?.stopTimes {
                try await saveRecords(stopTimes, feedID: feedRecord.id!, as: StopTimeRecord.self)
            } else {
                print("Aucun stopTime à sauvegarder.")
            }

        }
    }

    private func saveRecords<T: FeedModelRecord>(_ records: [T.Source], feedID: UUID, as recordType: T.Type) async throws where T: Model {
        for record in records {
            let dbRecord = T(from: record, feedID: feedID)
            try await dbRecord.save(on: db)
        }
    }


    /// Crée un `Feed` à partir des données extraites de la base de données
    private func createFeed(from agencies: [AgencyRecord], trips: [TripRecord], stops: [StopRecord], stopTimes: [StopTimeRecord]) throws -> Feed {
        let agenciesFormatted: [Agency] = agencies.map { $0.toAgency() }
        let agencyModels: LocomoSwift.Agencies = LocomoSwift.Agencies(agenciesFormatted)
        let tripModels = Trips(trips.map { $0.toTrip() })
        let stopModels = Stops(stops.map { $0.toStop() })
        let stopTimes = StopTimes(stopTimes.map { $0.toStopTimes() })

        // Utiliser l'init personnalisé du Feed
        return try Feed(
            agencices: agencyModels,
            stops: stopModels,
            trips: tripModels,
            stopTimes: stopTimes
        )
    }

    /// Vérifie si le `Feed` est encore valide en fonction de la date de la dernière mise à jour et de la fréquence de rafraîchissement.
    private func isFeedStillValid(_ lastUpdate: Date, refreshFrequency: RefreshRate) -> Bool {
        let now = Date()
        return now.timeIntervalSince(lastUpdate) < refreshFrequency.rawValue
    }
    
    func removeTemporaryFolder(at path: String) {
        let fileManager = FileManager.default
        do {
            try fileManager.removeItem(atPath: path)
            print("Dossier temporaire supprimé : \(path)")
        } catch let error {
            print("Erreur lors de la suppression du dossier temporaire : \(error)")
        }
    }
}
