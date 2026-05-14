# Locale Resolution

How `TranslatedString` and `TranslatedImage` payloads pick a language for the response.

## Overview

GTFS-RT v2.0 carries `TranslatedString` and `TranslatedImage` for human-readable fields (alert headers, descriptions, image URLs). Each variant is tagged with a BCP-47 language code (`fr`, `en`, `fr-FR`…) or left untagged.

Rather than dump the full translation dict and let clients walk it, the API resolves a single best-match `text` (or `url`) for the request locale **and** ships the full `translations` dict alongside — so a client can render immediately and still switch language without re-querying.

## Resolution order

For each request, the API picks a `Locale` in this order:

1. **`?lang=<tag>` query parameter.** Highest priority. Accepts any BCP-47 tag — `fr`, `fr-FR`, `de-CH`, etc.
2. **`Accept-Language` HTTP header.** First tag is used; quality scores are ignored. The iOS app typically sends `fr-FR,fr;q=0.9,en;q=0.8` — only `fr-FR` is consulted.
3. **Fallback: `en`.**

## Matching rules

Language matching follows the GTFS-RT spec, implemented in LocomoSwift's `TranslatedString.text(for:)`:

1. **Exact match** on the full tag (`fr-FR` matches `fr-FR`).
2. **Primary language** match (`fr-FR` falls back to a `fr` translation).
3. **Untagged variant** — A translation with no language code is used as a final fallback.
4. `nil` if none of the above hits.

## Response shape

For `TranslatedString`:

```json
{
  "text": "Travaux en gare",
  "translations": {
    "fr": "Travaux en gare",
    "en": "Station works",
    "": "Travaux en gare"
  }
}
```

The empty string key (`""`) holds the untagged variant when the upstream feed publishes one.

For `TranslatedImage`:

```json
{
  "url": "https://example.com/poster-fr.png",
  "images": [
    { "url": "…/poster-fr.png", "mediaType": "image/png", "language": "fr" },
    { "url": "…/poster-en.png", "mediaType": "image/png", "language": "en" }
  ]
}
```

`url` is the resolved-for-locale variant; `images` is the full set so a client can prefetch alternate languages.

## Examples

```sh
# Explicit French
curl -H "Authorization: Bearer $TOKEN" \
  "$API/realtime/alerts?source=sncf-tgv&lang=fr"

# Implicit via Accept-Language
curl -H "Authorization: Bearer $TOKEN" \
     -H "Accept-Language: de-CH,de;q=0.9" \
     "$API/realtime/alerts?source=sbb"

# Falls back to en (no lang, no header)
curl -H "Authorization: Bearer $TOKEN" \
  "$API/realtime/alerts?source=sncf-tgv"
```
