//
//  ShapeFallbackProvider.swift
//  RailMapAPI
//
//  Created by Jérémie Patot on 15/03/2026.
//

import Vapor
import LocomoSwift

/// Provides fallback train route shapes when GTFS shapes.txt is unavailable.
/// Uses signal.eu.org OSRM (rail profile) as primary fallback,
/// Overpass API (OpenStreetMap railway data) as secondary fallback,
/// and straight stop-to-stop lines as last resort.
struct ShapeFallbackProvider {

    /// A simple lat/lon coordinate pair used as waypoint input.
    struct Coordinate {
        let latitude: Double
        let longitude: Double
    }

    // MARK: - signal.eu.org OSRM (European rail OSRM instance)

    /// Requests a train route shape from the signal.eu.org OSRM router.
    ///
    /// - Parameters:
    ///   - stops: Ordered list of stop coordinates along the trip.
    ///   - client: Vapor HTTP client for making requests.
    /// - Returns: A `GeoJSONGeometry` LineString, or `nil` if the request fails.
    static func fromSignalOSRM(
        stops: [Coordinate],
        client: Client
    ) async -> GeoJSONGeometry? {
        guard stops.count >= 2 else { return nil }

        // OSRM expects coordinates as lon,lat pairs separated by semicolons
        // Limit waypoints to avoid URL length issues (use first, last, + evenly spaced intermediate)
        let waypoints = selectWaypoints(from: stops, maxCount: 25)
        let coordinateString = waypoints
            .map { "\($0.longitude),\($0.latitude)" }
            .joined(separator: ";")

        let url = "https://signal.eu.org/osm/eu/route/v1/train/\(coordinateString)?overview=full&geometries=geojson"

        do {
            let response = try await client.get(URI(string: url))

            guard response.status == .ok,
                  let body = response.body else {
                return nil
            }

            let osrmResponse = try JSONDecoder().decode(OSRMResponse.self, from: body)

            guard osrmResponse.code == "Ok",
                  let route = osrmResponse.routes.first else {
                return nil
            }

            return GeoJSONGeometry(
                type: route.geometry.type,
                coordinates: route.geometry.coordinates
            )
        } catch {
            print("[ShapeFallback] signal.eu.org OSRM error: \(error)")
            return nil
        }
    }

    // MARK: - Overpass API (OpenStreetMap railway segments)

    /// Queries the Overpass API for railway segments near the trip's stops.
    ///
    /// This builds a bounding box from the stops and queries for `railway=rail` ways.
    /// The result is a simplified polyline connecting the railway segments.
    ///
    /// - Parameters:
    ///   - stops: Ordered list of stop coordinates along the trip.
    ///   - client: Vapor HTTP client for making requests.
    /// - Returns: A `GeoJSONGeometry` LineString, or `nil` if the request fails.
    static func fromOverpass(
        stops: [Coordinate],
        client: Client
    ) async -> GeoJSONGeometry? {
        guard stops.count >= 2 else { return nil }

        // Build bounding box with padding
        let lats = stops.map { $0.latitude }
        let lons = stops.map { $0.longitude }
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return nil
        }
        let padding = 0.01 // ~1km padding
        let bbox = "\(minLat - padding),\(minLon - padding),\(maxLat + padding),\(maxLon + padding)"

        // Query Overpass for railway=rail ways within the bounding box
        let query = """
        [out:json][timeout:15];
        way["railway"="rail"](\(bbox));
        (._;>;);
        out body;
        """

        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = "https://overpass-api.de/api/interpreter?data=\(encodedQuery)"

        do {
            let response = try await client.get(URI(string: url))

            guard response.status == .ok,
                  let body = response.body else {
                return nil
            }

            let overpassResponse = try JSONDecoder().decode(OverpassResponse.self, from: body)

            // Build node lookup
            var nodeLookup: [Int: Coordinate] = [:]
            for element in overpassResponse.elements {
                if element.type == "node", let lat = element.lat, let lon = element.lon {
                    nodeLookup[element.id] = Coordinate(latitude: lat, longitude: lon)
                }
            }

            // Collect all railway way coordinates
            var allCoordinates: [[Double]] = []
            for element in overpassResponse.elements {
                if element.type == "way", let nodes = element.nodes {
                    for nodeID in nodes {
                        if let coord = nodeLookup[nodeID] {
                            allCoordinates.append([coord.longitude, coord.latitude])
                        }
                    }
                }
            }

            guard !allCoordinates.isEmpty else { return nil }

            // Sort coordinates by proximity to the stop sequence to form a coherent path
            let sortedCoordinates = sortCoordinatesByStopProximity(
                coordinates: allCoordinates,
                stops: stops
            )

            return GeoJSONGeometry(
                type: "LineString",
                coordinates: sortedCoordinates
            )
        } catch {
            print("[ShapeFallback] Overpass API error: \(error)")
            return nil
        }
    }

    // MARK: - Stop-to-stop fallback (straight lines)

    /// Creates a simple LineString by connecting stop coordinates with straight lines.
    static func fromStops(_ stops: [Coordinate]) -> GeoJSONGeometry {
        let coordinates = stops.map { [$0.longitude, $0.latitude] }
        return GeoJSONGeometry(
            type: "LineString",
            coordinates: coordinates
        )
    }

    // MARK: - Helpers

    /// Selects evenly spaced waypoints from a list of stops to avoid hitting URL length limits.
    private static func selectWaypoints(from stops: [Coordinate], maxCount: Int) -> [Coordinate] {
        guard stops.count > maxCount else { return stops }

        var result: [Coordinate] = [stops.first!]
        let step = Double(stops.count - 1) / Double(maxCount - 1)

        for i in 1..<(maxCount - 1) {
            let index = Int((Double(i) * step).rounded())
            result.append(stops[index])
        }

        result.append(stops.last!)
        return result
    }

    /// Sorts Overpass coordinates by proximity to the ordered stop sequence.
    /// Groups coordinates by closest stop segment and orders them accordingly.
    private static func sortCoordinatesByStopProximity(
        coordinates: [[Double]],
        stops: [Coordinate]
    ) -> [[Double]] {
        guard stops.count >= 2 else { return coordinates }

        // Simple approach: for each stop pair, find nearby coordinates
        var result: [[Double]] = []
        var used: Set<Int> = []

        for i in 0..<(stops.count - 1) {
            let from = stops[i]
            let to = stops[i + 1]
            let midLat = (from.latitude + to.latitude) / 2
            let midLon = (from.longitude + to.longitude) / 2
            let maxDist = distance(from: from, to: to) * 1.5

            // Find coordinates near this segment
            var segmentCoords: [(index: Int, dist: Double, coord: [Double])] = []
            for (idx, coord) in coordinates.enumerated() {
                guard !used.contains(idx) else { continue }
                let point = Coordinate(latitude: coord[1], longitude: coord[0])
                let distToMid = distance(
                    from: Coordinate(latitude: midLat, longitude: midLon),
                    to: point
                )
                if distToMid <= maxDist {
                    let distFromStart = distance(from: from, to: point)
                    segmentCoords.append((idx, distFromStart, coord))
                }
            }

            segmentCoords.sort { $0.dist < $1.dist }
            for item in segmentCoords {
                result.append(item.coord)
                used.insert(item.index)
            }
        }

        // Add any remaining coordinates at the end
        for (idx, coord) in coordinates.enumerated() {
            if !used.contains(idx) {
                result.append(coord)
            }
        }

        return result
    }

    /// Simple Euclidean distance approximation (sufficient for sorting purposes).
    private static func distance(from a: Coordinate, to b: Coordinate) -> Double {
        let latDiff = a.latitude - b.latitude
        let lonDiff = a.longitude - b.longitude
        return (latDiff * latDiff + lonDiff * lonDiff).squareRoot()
    }
}

// MARK: - OSRM Response DTOs

struct OSRMResponse: Decodable {
    let code: String
    let routes: [OSRMRoute]
}

struct OSRMRoute: Decodable {
    let distance: Double
    let duration: Double
    let geometry: OSRMGeometry
}

struct OSRMGeometry: Decodable {
    let type: String
    let coordinates: [[Double]]
}

// MARK: - Overpass Response DTOs

struct OverpassResponse: Decodable {
    let elements: [OverpassElement]
}

struct OverpassElement: Decodable {
    let type: String
    let id: Int
    let lat: Double?
    let lon: Double?
    let nodes: [Int]?
}
