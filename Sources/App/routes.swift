import Vapor
import GTFS

func routes(_ app: Application) throws {
    app.get("stops") { req async -> String in

            let workingDirectory = DirectoryConfiguration.detect().workingDirectory
            let protobufFilePath = workingDirectory + "sncf-tgv-gtfs-rt-trip-updates"
            let feedURL = URL(fileURLWithPath: "https://eu.ftp.opendatasoft.com/sncf/gtfs/export-ter-gtfs-last.zip")
//            let feed = Feed(contentsOfURL: feedURL)
//            
//            var response = "Feed: \(feed)/n"
//        response += "Trips: \(feed.trips?.id)"
//        
    
//            if let stops = feed.stops {
//                for stop in stops {
//                    response += "\(stop)"
//                }
//            } else {
//                response = "no stops: \(feed)"
//            }
            return "Test docker"
    }
    
    
    app.get("hello") { req async -> String in
        "Hello, world!"
    }
}

