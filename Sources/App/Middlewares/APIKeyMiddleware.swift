//
//  APIKeyMiddleware.swift
//  RailMapAPI
//
//  Validates `Authorization: Bearer <token>` against an env-supplied allowlist.
//
//  The allowlist comes from the `API_AUTH_TOKENS` env var (comma-separated).
//  Multiple tokens are supported for **zero-downtime rotation**:
//    1. Add a new token to `API_AUTH_TOKENS` → deploy.
//    2. Ship a new iOS build that uses the new token.
//    3. Remove the old token from the env → redeploy.
//
//  Comparison is constant-time to avoid timing-attack leaks of the valid prefix.
//

import Vapor

struct APIKeyMiddleware: AsyncMiddleware {
    let validTokens: Set<String>

    init() {
        let raw = Environment.get("API_AUTH_TOKENS") ?? ""
        let tokens = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.validTokens = Set(tokens)
    }

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // Fail closed: refuse to serve traffic if no tokens are configured —
        // prevents accidentally deploying an unauthenticated server.
        guard !validTokens.isEmpty else {
            request.logger.error("API_AUTH_TOKENS is empty — refusing all traffic")
            throw Abort(.serviceUnavailable, reason: "API auth not configured")
        }

        guard let provided = request.headers.bearerAuthorization?.token, !provided.isEmpty else {
            throw Abort(.unauthorized, reason: "Missing Bearer token")
        }

        let providedBytes = Array(provided.utf8)
        let isValid = validTokens.contains { token in
            Self.constantTimeEquals(Array(token.utf8), providedBytes)
        }
        guard isValid else {
            throw Abort(.unauthorized, reason: "Invalid token")
        }

        return try await next.respond(to: request)
    }

    /// Length-then-byte constant-time compare. Prevents leaking the matched
    /// prefix length via response timing on rejected tokens.
    private static func constantTimeEquals(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count {
            diff |= a[i] ^ b[i]
        }
        return diff == 0
    }
}
