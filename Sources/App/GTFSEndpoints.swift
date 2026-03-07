import Foundation

enum Agencies: String, Sendable {
    case SNCF = "sncf"
    case SNCB = "sncb"
    case SBB = "sbb"
    case Renfe = "renfe"
    case DB = "db"
}

enum ServiceType: String, Sendable {
    case TER = "ter"
    case TGV = "tgv"
    case Intercite = "intercité"
    case Cercanias = "cercanias"
    case TrenitaliaFR = "trenitalia"
    case All = "all"
}

enum RefreshRate: TimeInterval, Sendable {
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

struct GTFSEndpoint: Hashable, Sendable {
    let agency: Agencies
    let serviceType: ServiceType
    let url: String
    let refreshFrequency: RefreshRate
}

let gtfsEndpoints: Set<GTFSEndpoint> = [
    GTFSEndpoint(agency: .SNCF,
                 serviceType: .TER,
                 url: "https://eu.ftp.opendatasoft.com/sncf/gtfs/export-ter-gtfs-last.zip",
                 refreshFrequency: .everyDay),
    GTFSEndpoint(agency: .SNCF,
                 serviceType: .TGV,
                 url: "https://eu.ftp.opendatasoft.com/sncf/plandata/export_gtfs_voyages.zip",
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
