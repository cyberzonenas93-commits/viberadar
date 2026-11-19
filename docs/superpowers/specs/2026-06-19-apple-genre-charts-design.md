# Apple Music genre charts as the primary genre source

Date: 2026-06-19
Status: Approved (design)

## Problem

When a user selects a genre, results feel low-quality and unlike Apple Music's own
genre pages. Root cause: the app never calls Apple Music's **genre charts**. Today:

- `_searchApple` does keyword search (`catalog/{storefront}/search?term=<genre>`).
- `_searchAppleCharts` fetches the **global** most-played chart
  (`catalog/{storefront}/charts?types=songs&chart=most-played`, no `genre`) and then
  *filters* it by genre tokens — so genre songs outside the global top-100 never appear,
  and it returns nothing for the Global region.

Apple Music's "tap a genre" experience is the genre-scoped chart:
`catalog/{storefront}/charts?types=songs&chart=most-played&genre=<genreId>`.

Verified live (MusicKit token): US Hip-Hop(18)→Drake, US Pop(14)→Olivia Rodrigo.
Genre IDs confirmed: Hip-Hop/Rap=18, Pop=14, R&B/Soul=15, Dance=17, Electronic=7,
Reggae=24, Latin=12, K-Pop=51, Rock=21, Alternative=20, Country=6, Christian=22,
Classical=5, Jazz=11, Blues=2, Worldwide=19. **Afrobeats=100051 and Amapiano=42 exist
only in African storefronts (ZA/NG/GH), not US** — genre availability is storefront-specific.

## Decision

When a specific genre is selected, **Apple Music's genre chart is the primary list**
(user-chosen "Apple genre charts first"). Other platforms only add Play-on-X links via
the existing bounded `enrichPlaybackLinksForResults`. Parent-genre mapping is acceptable
(House→Dance 17, Dancehall→Reggae 24). Unmapped lanes (Open Format, Disco, Funk, …) and
any failure/sparse result fall back to today's keyword-search blend — nothing regresses.

## Changes

1. **`lib/core/config/music_genres.dart`** — add `AppleGenreMapping {int id; List<String>
   preferredStorefronts}` and `AppleGenreMapping? appleGenreFor(String? lane)`. Map keyed by
   `canonicalGenre(lane)`. `preferredStorefronts` non-empty only for regional genres
   (Afrobeats/Amapiano/African subgenres) so they chart in an African storefront when the
   selected region lacks them; empty = use the selected region's storefront.

2. **`lib/services/apple_music_artist_service.dart`** — add
   `getGenreChartSongs({required int genreId, String? region, int limit, List<String>
   preferredStorefronts})` → `catalog/{storefront}/charts?types=songs&chart=most-played&
   genre=<id>`. Storefront chosen by a pure helper `appleGenreChartStorefront(region,
   preferred)`: empty preferred → selected storefront; else selected if it's in preferred,
   otherwise `preferred.first`. Returns `[]` on error.

3. **`lib/services/platform_search_service.dart`** — add `_searchAppleGenreChart(lane,
   region, limit)`: resolve `appleGenreFor`; null → `[]`. Map rows to `PlatformTrackResult`
   with `appleChartRank` (so they pass `hasChartEvidenceForRegion` for any region) and
   `genre = lane` (stamp the selected lane — they are Apple's genre chart by curation).
   - In `fetchTrendingChartTracks`: when `lane` maps to an Apple genre id, use
     `_searchAppleGenreChart` as the Apple chart source (index 1) instead of
     `_searchAppleCharts`. Merge/enrichment unchanged.
   - In `searchByGenre`: seed `_searchAppleGenreChart` results first (deduped), then the
     existing keyword-query loop fills the rest.

4. **`lib/services/live_track_catalog_service.dart`** — no change. Its `chartBacked` filter
   already accepts `appleChartRank` rows; `_withGenreFallbacks` fills from search rows only
   when the chart is sparse.

## Testing

- `appleGenreFor`: House→17, Hip-Hop→18, Amapiano→42 (preferred has `za`), Afrobeats→100051
  (preferred has `ng`), Dancehall→24, Deep House→17; `Open Format`/`All`/`Disco`→null.
- `appleGenreChartStorefront`: global genre uses selected region; regional genre with a
  non-African region falls back to the preferred storefront; regional genre with a matching
  region keeps it.
- `platform_search`: with a fake Apple service, selecting a mapped genre yields
  genre-chart rows carrying `appleChartRank` as the primary results; unmapped genre and
  empty chart fall back to the search path.

## Out of scope

No backend change (`appleProxy` already allows `catalog/...`). No web/native deploy in this
change — that's a separate ship step.
