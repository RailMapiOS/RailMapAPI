//
//  GTFSEndpoints.swift
//  RailMapAPI
//
//  Created by Jérémie Patot on 04/10/2024.
//

import Foundation

// Enumération pour les agences
enum Agencies: String {
    case SNCF = "sncf"
    case SNCB = "sncb"
    case SBB = "sbb"
    case Renfe = "renfe"
    case DB = "db"
}

// Enumération pour les types de service (TER, TGV, Intercités, etc.)
enum ServiceType: String {
    case TER = "ter"
    case TGV = "tgv"
    case Intercite = "intercité"
    case Cercanias = "cercanias"
    case TrenitaliaFR = "trenitalia"
    case All = "all"
}

enum RefreshRate: TimeInterval {
    case once = 0
    case everyMinute = 60
    case everyHour = 3600
    case everyDay = 86400
    case everyWeek = 604800
    case everyTwoWeeks = 1209600
    case everyMonth = 2592000
    case everyTwoMonths = 5184000
    case everySixMonths = 15778463
    case everyYear = 31556926
}

// Structure pour représenter les endpoints avec agence et type de service
struct GTFSEndpoint: Hashable {
    let agency: Agencies
    let serviceType: ServiceType
    var url: String
    var refreshFrequency: RefreshRate
    var lastUpdate: Date?
    
//TODO: Ajout regles de frequences de MAJ
}

// Set des endpoints GTFS avec leur agence et type de service
@MainActor var gtfsEndpoints: Set<GTFSEndpoint> = [
    GTFSEndpoint(agency: .SNCF,
                 serviceType: .TER,
                 url: "https://eu.ftp.opendatasoft.com/sncf/gtfs/export-ter-gtfs-last.zip",
                 refreshFrequency: .everyDay),
    GTFSEndpoint(agency: .SNCF,
                 serviceType: .TGV,
                 url: "https://eu.ftp.opendatasoft.com/sncf/gtfs/export_gtfs_voyages.zip",
                 refreshFrequency: .everyDay),
    GTFSEndpoint(agency: .SNCF,
                 serviceType: .Intercite,
                 url: "https://eu.ftp.opendatasoft.com/sncf/gtfs/export-intercites-gtfs-last.zip",
                 refreshFrequency: .everyDay),
    GTFSEndpoint(agency: .SBB,
                 serviceType: .All,
                 url: "https://opentransportdata.swiss/fr/dataset/timetable-2024-gtfs2020/permalink",
                 refreshFrequency: .everySixMonths),
    GTFSEndpoint(agency: .Renfe,
                 serviceType: .All,
                 url: "https://ssl.renfe.com/gtransit/Fichero_AV_LD/google_transit.zip",
                 refreshFrequency: .everyWeek),
    GTFSEndpoint(agency: .Renfe,
                 serviceType: .Cercanias,
                 url: "https://ssl.renfe.com/ftransit/Fichero_CER_FOMENTO/fomento_transit.zip",
                 refreshFrequency: .everyWeek),
    GTFSEndpoint(agency: .SNCF,
                 serviceType: .TrenitaliaFR,
                 url: "https://www.data.gouv.fr/fr/datasets/r/bdecea2c-ebc9-4f22-812d-927e4a2e4bad",
                 refreshFrequency: .everyDay),
    GTFSEndpoint(agency: .DB,
                 serviceType: .All,
                 url: "https://download.gtfs.de/germany/free/latest.zip",
                 refreshFrequency: .everyWeek)
]
