# Mobile AI Set Builder → real, playable crates

**Date:** 2026-06-08
**Status:** Design — awaiting review

## Problem

On mobile, the AI Set Builder ([ai_tab.dart](../../../lib/ui/mobile/ai_tab.dart)) parses the AI's
` ```crate ` block into a draft list, and "Save as setlist" writes a `Crate`
whose `trackIds` are **synthesized placeholders** (`ai:artist - title`). Those
ids match no real track, so the setlist editor renders every row as
**"Unknown track"** ([setlist_editor.dart:330](../../../lib/ui/mobile/setlist_editor.dart)).
The result: the mobile builder produces an unusable list, not a real set.

Desktop instead resolves each AI song against Spotify/Apple/YouTube into rich
`AiCrateTrack`s with playable links ([ai_copilot_screen.dart:812](../../../lib/ui/features/ai_copilot/ai_copilot_screen.dart)),
but those live in a **local, SharedPreferences-only** `aiCrateProvider`
([library_provider.dart:525](../../../lib/providers/library_provider.dart)) — separate from the
Firestore-synced `Crate` setlists, desktop-only, and not "add-to-existing".

## Goals

1. AI songs become **real, usable crate entries with playable links** (Spotify/Apple/YouTube + artwork) — desktop parity.
2. Songs can go into a **new setlist** *or* be appended to an **existing** one.
3. Works on **mobile** and **syncs** (send-to-computer carries the real songs/links).
4. Backward compatible with existing `Crate`s already in Firestore.

## Non-goals

- Full re-render of the desktop AI-crate UI (desktop keeps working; richer desktop rendering is an optional follow-on).
- Moving setlists out of the user doc into a subcollection (flagged as a future escape hatch, not done now).
- Audio playback in-app (we store/open platform links, not stream audio).

## Design

### 1. Data model — `CrateTrack` (new: `lib/models/crate_track.dart`)

```
CrateTrack {
  String? trackId          // real tracks/{id} when matched; null for resolve-only
  String title, artist
  int bpm; String key
  String? spotifyUrl, appleUrl, youtubeUrl, artworkUrl
  String get bestUrl  => spotifyUrl ?? appleUrl ?? youtubeUrl ?? ''
  bool   get hasUrl   => bestUrl.isNotEmpty
  String get stableKey => trackId ?? '${artist}|${title}'.toLowerCase()  // dedupe
  toMap() / fromMap()
}
```

`Crate.trackIds: List<String>` → **`Crate.tracks: List<CrateTrack>`**
([crate.dart](../../../lib/models/crate.dart)).

**Backward compatibility (no data migration needed):**
- `fromMap`: parse `map['tracks']` (rich array) if present; else map legacy
  `map['track_ids']` strings → `CrateTrack(trackId: id)` *reference* entries.
- `toMap`: write `tracks` **and** mirror `track_ids` (each entry's `trackId ?? stableKey`)
  so any unmodified desktop read path still functions.
- Rendering: a *reference* entry (empty title/artist) resolves against the live
  tracks stream as today; a *rich* entry renders its own title/artist/links —
  this is what kills "Unknown track" for AI songs.

### 2. Shared resolver — `SetResolutionService` (new: `lib/services/set_resolution_service.dart`)

Extract desktop's inline `_resolveTracksOnPlatforms` into one injectable service
used by both platforms.

```
resolve(
  List<({String title, String artist, int bpm, String key})> drafts,
  {List<Track> library = const [], void Function(int found, int total)? onProgress},
) -> Future<List<CrateTrack>>
```
(Uses the same anonymous-record shape desktop already produces in
`_extractTracksFromResponse`, so no new public draft model is needed. `library`
is the already-loaded tracks list for the free local-match pass.)

Per song, **in order, stopping at first hit for links** (but always keeping the
named entry even if unresolved):
1. **Local trends library** match (canonicalized title+artist) → reuse that
   track's `id` + `platformLinks` + artwork. *Free, no API call.*
2. **Spotify** search (proxy).
3. **Apple Music** search (proxy).
4. **YouTube** search (proxy) — **fallback only**, called only when 1–3 miss, to
   protect the ~100/day YouTube quota. (Desktop currently always calls all three;
   it will inherit this conservation when refactored onto the shared service.)

Services already exist and are proxy-backed / mobile-usable:
`SpotifyArtistService`, `AppleMusicArtistService`, `YoutubeSearchService`.
Desktop's `_resolveTracksOnPlatforms` becomes a thin wrapper mapping
`CrateTrack` → its existing `AiCrateTrack` (minimal desktop churn).

### 3. Mobile flow — `ai_tab.dart`

1. Build (unchanged) → draft list shown.
2. **"Resolve & add"** → `SetResolutionService.resolve(...)` with progress
   ("Found 9/12 on Spotify/Apple…"); rows show a resolved ✓ / link affordance.
3. Two actions:
   - **Save as new setlist** — `Crate(tracks: resolved)` via `SetlistActions.save`.
   - **Add to crate…** — bottom sheet listing `setlistsProvider` crates + "New
     setlist"; appends via new `SetlistActions.addTracks(crate, resolved)`
     (dedupe by `stableKey`).

### 4. Providers — `setlist_provider.dart`

- New `addTracks(Crate, List<CrateTrack>)` — append + dedupe + save.
- `addTrack(Crate, String trackId)` (used by Search/Trending) → wraps the id in a
  **reference** `CrateTrack(trackId: id)`; unchanged UX (resolves via tracks stream).
- `createWithTrack` similarly wraps.

### 5. Editor / list — `setlist_editor.dart`, `setlists_tab.dart`

- `_TrackRow`: rich entry → show its own title/artist/bpm/key + open-link button
  (`bestUrl`); reference entry → resolve against tracks stream (today's behavior).
- Reorder/remove operate on `List<CrateTrack>` (rename `reorderTrackIds` →
  `reorderTracks`, same algorithm).
- `setlists_tab` track count → `crate.tracks.length`.

### 6. Sync & desktop

- `pushSetlist` serializes via `crate.toMap()` → rich entries flow to desktop via
  the `pairings/{id}/setlists` subcollection automatically; **no pairing change**.
- Desktop `Crate.fromMap` gets the same compat update so it never breaks.

### 7. Cost

- Per build: local matches are free; ~1–3 proxy calls per *unmatched* song.
  Firestore impact unchanged: **1 user-doc write per save**.
- Rich entries enlarge the user doc; add a soft guard and document the 1 MB
  ceiling. Escape hatch (future, not now): `users/{uid}/crates/{crateId}` subcollection.

### 8. Bundled: decay-sweep cost tuning

Addresses the "high Firestore charges" question for the sweep deployed earlier.
- `decayTrendingScores` schedule `15,45 * * * *` → **hourly** `15 * * * *`.
- `planTrackDecay`: add `WRITE_EPSILON` (≈0.01) — skip the write when not retiring
  and `|newTrend − current| < WRITE_EPSILON` and base already set.
- Effect: ~$8/mo → ~$1–2/mo, no visible ranking change.

## Testing (TDD)

- `CrateTrack` toMap/fromMap round-trip; `bestUrl`; `stableKey`.
- `Crate.fromMap`: legacy `track_ids` → reference entries; new `tracks` → rich;
  `toMap` mirrors `track_ids`.
- `SetlistActions.addTracks`: dedupe by `stableKey`.
- `SetResolutionService.resolve` (fake platform services): local-match-first;
  Spotify→Apple→YouTube order; **YouTube called only when others miss**.
- `reorderTracks` reorder semantics preserved.
- `planTrackDecay`: no write when delta < `WRITE_EPSILON`; still retires past window.

## Files

**New:** `lib/models/crate_track.dart`, `lib/services/set_resolution_service.dart`, tests.
**Modified:** `lib/models/crate.dart`, `lib/providers/setlist_provider.dart`,
`lib/ui/mobile/ai_tab.dart`, `lib/ui/mobile/setlist_editor.dart`,
`lib/ui/mobile/setlists_tab.dart`,
`lib/ui/features/ai_copilot/ai_copilot_screen.dart`,
`lib/providers/library_provider.dart` (CrateTrack↔AiCrateTrack map),
`functions/src/decayTrending.ts`, `functions/src/lib/recency.ts`,
`functions/test/recency.test.ts`.

## Risks

- **User-doc growth** with rich entries — mitigated by guard + documented limit.
- **Resolver latency** (serial platform calls per song) — show progress; consider
  small concurrency. Unresolved songs still added as named entries.
- **Desktop compat** — covered by the `fromMap`/`track_ids`-mirror; desktop UI
  parity is a follow-on, not a blocker.
