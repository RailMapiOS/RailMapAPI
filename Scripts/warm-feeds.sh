#!/usr/bin/env bash
#
# Forces a fresh GTFS static ingestion, then warms the in-memory cache.
#
# Why the restart: FeedManager keeps its cache in memory, keyed by URL, and
# stamps `lastUpdate` when the download COMPLETES. A plain daily cron would
# therefore find the feed only ~23h45 old and skip the refresh, effectively
# refreshing every other day. Restarting the container empties the cache, so the
# warm-up requests below always trigger a real download — at a time we control.
#
# The SQLite reload is bypassed today (fix A, see FeedManager.swift), so the
# in-memory cache is the only thing that matters here.
#
# Requests go to the loopback, NOT through Cloudflare: the edge cuts at 100s and
# a cold ingestion takes ~15 min per feed.

set -uo pipefail

COMPOSE_DIR="${COMPOSE_DIR:-$HOME/RailMapAPI}"
API="${API:-http://127.0.0.1:8090}"
SOURCES="${SOURCES:-sncf-ter sncf-tgv sncf-intercites}"
# A cold ingestion is long; allow 30 min per source before giving up.
TIMEOUT="${TIMEOUT:-1800}"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

TOKEN=$(grep '^API_AUTH_TOKENS=' "$COMPOSE_DIR/.env" 2>/dev/null | cut -d= -f2- | cut -d, -f1)
if [ -z "${TOKEN:-}" ]; then
    log "FATAL: no API_AUTH_TOKENS found in $COMPOSE_DIR/.env"
    exit 1
fi

log "restarting container to drop the in-memory feed cache"
if ! docker compose --project-directory "$COMPOSE_DIR" restart app; then
    log "FATAL: docker compose restart failed"
    exit 1
fi

# Wait for the server to accept connections again before warming.
for _ in $(seq 1 30); do
    code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "$API/hello" || true)
    [ "$code" = "200" ] && break
    sleep 2
done
if [ "${code:-}" != "200" ]; then
    log "FATAL: API did not come back after restart (last code=${code:-none})"
    exit 1
fi
log "API is back up"

rc=0
for src in $SOURCES; do
    log "warming $src ..."
    # /stop hits FeedManager.getFeed before doing anything else; the headsign
    # itself is irrelevant, we only care about the ingestion side effect.
    read -r code time < <(curl -s -m "$TIMEOUT" -o /dev/null \
        -w '%{http_code} %{time_total}' \
        -H "Authorization: Bearer $TOKEN" \
        "$API/stop/warmup?source=$src" || echo "000 0")
    if [ "$code" = "200" ]; then
        log "  $src OK in ${time}s"
    else
        log "  $src FAILED (code=$code after ${time}s)"
        rc=1
    fi
done

log "done (exit $rc)"
exit $rc
