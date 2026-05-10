//
//  GTFSEndpoints.swift
//  RailMapAPI
//
//  Created by Jérémie Patot on 04/10/2024.
//

import Foundation
import LocomoSwift

// MARK: - DataSource Registry

/// Centralized registry of all configured data sources.
/// Each entry is a complete `DataSource` (GTFS static + GTFS RT).
struct DataSourceRegistry {

    /// All registered sources, indexed by identifier.
    private(set) var sources: [String: DataSource]

    /// Looks up a source by its identifier.
    func source(for identifier: String) -> DataSource? {
        sources[identifier]
    }

    /// All available sources.
    var allSources: [DataSource] {
        Array(sources.values)
    }

    init(sources: [DataSource]) {
        self.sources = Dictionary(uniqueKeysWithValues: sources.map { ($0.identifier, $0) })
    }
}

// MARK: - RailMapAPI-specific DataSource presets

extension DataSource {

    // MARK: France

    /// Trenitalia France
    static let trenitaliaFR = DataSource(
        identifier: "trenitalia-fr",
        displayName: "Trenitalia France",
        staticFeedURL: URL(string: "https://thello.axelor.com/public/gtfs/gtfs.zip"),
        staticRefreshInterval: 86_400, // 24h
        realtimeFeeds: [
            .tripUpdates: URL(string: "https://proxy.transport.data.gouv.fr/resource/trenitalia-gtfs-rt")!
        ],
        realtimeCacheTTL: 60
    )

    // MARK: Europe

    /// Renfe — Spanish long-distance trains
    static let renfe = DataSource(
        identifier: "renfe",
        displayName: "Renfe",
        staticFeedURL: URL(string: "https://ssl.renfe.com/gtransit/Fichero_AV_LD/google_transit.zip"),
        staticRefreshInterval: 604_800 // 7 days
    )

    /// Renfe Cercanías — Spanish commuter trains
    static let renfeCercanias = DataSource(
        identifier: "renfe-cercanias",
        displayName: "Renfe Cercanías",
        staticFeedURL: URL(string: "https://ssl.renfe.com/ftransit/Fichero_CER_FOMENTO/fomento_transit.zip"),
        staticRefreshInterval: 604_800, // 7 days,
        realtimeFeeds: [
            .serviceAlerts: URL(string: "https://gtfsrt.renfe.com/alerts.pb")!,
            .tripUpdates: URL(string: "https://gtfsrt.renfe.com/trip_updates.pb")!,
            .vehiclePositions: URL(string: "https://gtfsrt.renfe.com/vehicle_positions.pb")!
        ],
        realtimeCacheTTL: 20
    )

    /// Deutsche Bahn — German Railways
    static let db = DataSource(
        identifier: "db",
        displayName: "Deutsche Bahn",
        staticFeedURL: URL(string: "https://download.gtfs.de/germany/free/latest.zip"),
        staticRefreshInterval: 604_800, // 7 days
        realtimeFeeds: [.tripUpdates: URL(string: "https://realtime.gtfs.de/realtime-free.pb")!],
        realtimeCacheTTL: 10
    )
    
    /// NMBS/SNCB — Belgian Railways
    static let sncb = DataSource(
        identifier: "sncb",
        displayName: "NMBS/SNCB",
        authentication: .header(name: "bmc-partner-key", value: "3294ce6a3a6f4e24b5c9dfb5571e72ec"),
        staticFeedURL: URL(string: "https://api-management-opendata-production.azure-api.net/api/gtfs/feed/nmbssncb/static/"),
        staticRefreshInterval: 86_400, // 24h
        realtimeFeeds: [
            .serviceAlerts: URL(string: "https://api-management-opendata-production.azure-api.net/api/gtfs/feed/nmbssncb/rt/alert/protobuf")!,
            .tripUpdates: URL(string: "https://api-management-opendata-production.azure-api.net/api/gtfs/feed/nmbssncb/rt/trip-update/protobuf")!
        ],
        realtimeCacheTTL: 120
    )

}

// MARK: - Default Registry

extension DataSourceRegistry {

    /// Default registry with all configured sources
    static let `default` = DataSourceRegistry(sources: [
        // France
        .sncfTER,
        .sncfTGV,
        .sncfIntercites,
        .trenitaliaFR,
        .tamMontpellier,
        // Europe
        .sbb,
        .renfe,
        .renfeCercanias,
        .db,
        .sncb
    ])
}
