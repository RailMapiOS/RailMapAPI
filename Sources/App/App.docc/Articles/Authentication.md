# Authentication

Bearer-token allowlist with constant-time compare and zero-downtime rotation.

## Overview

Every authenticated request must carry an `Authorization: Bearer <token>` header. Tokens are read from the `API_AUTH_TOKENS` environment variable — a comma-separated list — and matched in **constant time** to avoid timing-attack leaks.

The middleware lives at ``APIKeyMiddleware`` and is applied to every route except `/hello` (a public liveness probe).

## Generating tokens

Either of these works — both produce ~32 bytes of entropy:

```sh
openssl rand -base64 32
uuidgen
```

## Configuring tokens

In `.env`:

```sh
API_AUTH_TOKENS=tok-A,tok-B
```

Whitespace around tokens is trimmed. Empty tokens are filtered out. If the resulting set is empty, the middleware **fails closed**: every request returns `503 Service Unavailable` until at least one valid token is configured. This prevents accidentally deploying an unauthenticated server.

## Zero-downtime rotation

Multiple tokens are accepted concurrently — use this for rotating without breaking live clients:

1. **Add** the new token: `API_AUTH_TOKENS=tok-old,tok-new` → redeploy.
2. **Ship** a client build that uses `tok-new`.
3. **Wait** for old clients to upgrade.
4. **Remove** the old token: `API_AUTH_TOKENS=tok-new` → redeploy.

## Constant-time comparison

Token comparison runs through ``APIKeyMiddleware/constantTimeEquals(_:_:)`` (length-then-byte). Rejected tokens take the same time regardless of how many bytes matched the prefix — so an attacker can't bisect the valid token by measuring response latency.

## Error responses

| Condition                         | Status | Reason                          |
|-----------------------------------|--------|---------------------------------|
| `API_AUTH_TOKENS` empty/unset     | 503    | `API auth not configured`       |
| Missing/empty `Authorization`     | 401    | `Missing Bearer token`          |
| Token not in allowlist            | 401    | `Invalid token`                 |

## Client example

```swift
var request = URLRequest(url: url)
request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
```

Never hard-code tokens in shipped binaries — fetch from your secret store at runtime, or build them into per-environment Info.plist via build settings.
