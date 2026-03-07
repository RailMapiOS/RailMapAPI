//
//  RouteGeometryController.swift
//  RailMapAPI
//
//  Created by Claude on 07/03/2026.
//

import Vapor

/// Response model for route geometry
struct RouteGeometryResponse: Content, Sendable {
    let coordinates: [[Double]]  // [[lon, lat], ...]
}

/// Controller that proxies rail route geometry from signal.eu.org OSRM train router
struct RouteGeometryController {

    private static let osrmBaseURL = "https://signal.eu.org/osm/route/v1/train/"

    /// GET /route/geometry?waypoints=lon1,lat1;lon2,lat2;...
    func getGeometry(req: Request) async throws -> RouteGeometryResponse {
        guard let waypointsParam = req.query[String.self, at: "waypoints"] else {
            throw Abort(.badRequest, reason: "Missing 'waypoints' query parameter. Format: lon1,lat1;lon2,lat2")
        }

        let pairs = waypointsParam.split(separator: ";")
        guard pairs.count >= 2 else {
            throw Abort(.badRequest, reason: "At least 2 waypoints required")
        }

        // Build OSRM URL: /route/v1/train/lon1,lat1;lon2,lat2?overview=full&geometries=polyline
        let coordinatesString = pairs.joined(separator: ";")
        let urlString = "\(Self.osrmBaseURL)\(coordinatesString)?overview=full&geometries=polyline"

        let url = URI(string: urlString)

        let response = try await req.client.get(url)

        guard response.status == .ok else {
            req.logger.warning("OSRM request failed with status \(response.status) for URL: \(urlString)")
            throw Abort(.serviceUnavailable, reason: "Rail routing service unavailable")
        }

        let osrmResponse = try response.content.decode(OSRMResponse.self)

        guard let route = osrmResponse.routes.first,
              let geometry = route.geometry, !geometry.isEmpty else {
            throw Abort(.notFound, reason: "No rail route found between these waypoints")
        }

        // Decode Google Encoded Polyline to [[lon, lat], ...]
        let coordinates = decodePolyline(geometry)

        return RouteGeometryResponse(coordinates: coordinates)
    }

    /// Decodes a Google Encoded Polyline string into [[lon, lat], ...] pairs
    private func decodePolyline(_ encoded: String) -> [[Double]] {
        var coordinates: [[Double]] = []
        var index = encoded.startIndex
        var lat: Int = 0
        var lon: Int = 0

        while index < encoded.endIndex {
            // Decode latitude
            var result: Int = 0
            var shift: Int = 0
            var byte: Int

            repeat {
                byte = Int(encoded[index].asciiValue! - 63)
                index = encoded.index(after: index)
                result |= (byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20

            lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1)

            // Decode longitude
            result = 0
            shift = 0

            repeat {
                byte = Int(encoded[index].asciiValue! - 63)
                index = encoded.index(after: index)
                result |= (byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20

            lon += (result & 1) != 0 ? ~(result >> 1) : (result >> 1)

            // OSRM polyline precision is 1e5 → lon, lat order for our response
            coordinates.append([Double(lon) / 1e5, Double(lat) / 1e5])
        }

        return coordinates
    }
}

// MARK: - OSRM Response Models

private struct OSRMResponse: Codable, Sendable {
    let code: String
    let routes: [OSRMRoute]
}

private struct OSRMRoute: Codable, Sendable {
    let geometry: String?  // Encoded polyline string
    let distance: Double?
    let duration: Double?
}
