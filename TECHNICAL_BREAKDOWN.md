# VibeRadar — Full Technical Breakdown

**Version:** 1.0.0
**Platform:** macOS (Flutter Desktop)
**Firebase Project:** viberadar-462b8
**Download:** https://viberadar-462b8.web.app
**Built by:** Angelo Nartey
**Codebase:** 25,170 lines across 73 files (61 Dart + 16 TypeScript)

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────┐
│                    macOS Desktop App                      │
│  Flutter 3.x + Riverpod 3.x + Firebase + OpenAI GPT-5.4  │
├──────────────────────────────────────────────────────────┤
│  UI Layer (21 files)                                      │
│  ├── Shell (sidebar + main + detail panel)                │
│  ├── Auth (splash, onboarding, auth gate)                 │
│  ├── 10 Feature Screens                                   │
│  └── 7 Reusable Widgets                                   │
├──────────────────────────────────────────────────────────┤
│  State Management (3 providers)                           │
│  ├── WorkspaceController (navigation + filters + sort)    │
│  ├── LibraryNotifier (scan + tracks + duplicates)         │
│  └── Repository Providers (DI overrides)                  │
├──────────────────────────────────────────────────────────┤
│  Service Layer (17 services)                              │
│  ├── AI Copilot (GPT-5.4 streaming chat + intent parse)   │
│  ├── Platform Search (Apple Music + Spotify merge)        │
│  ├── Playlist Aggregation (multi-source playlists)        │
│  ├── Set Builder (energy curve + harmonic mixing)         │
│  ├── Greatest-Of Engine (8-dimension scoring)             │
│  ├── Library Scanner (parallel + isolate + cache)         │
│  ├── Local Match (6-tier fuzzy matching)                  │
│  ├── Export (7 formats + physical crates)                 │
│  ├── Duplicate Detector (3-tier + batch cleanup)          │
│  ├── Artist Service (aggregation + collaborators)         │
│  ├── DJ Workflow (VirtualDJ/Serato path detection)        │
│  └── Action Log (file operation audit trail)              │
├──────────────────────────────────────────────────────────┤
│  Data Layer (4 files)                                     │
│  ├── Firestore Track Repository (real-time stream)        │
│  ├── Firestore User Repository (prefs + crates)           │
│  ├── Firebase Session Repository (auth persistence)       │
│  └── Mock Track Seed (500 demo tracks)                    │
├──────────────────────────────────────────────────────────┤
│  Models (9 models)                                        │
│  ├── Track (with releaseYear, effectiveSources)           │
│  ├── ArtistModel (collaborators, vibes, BPM buckets)      │
│  ├── LibraryTrack + DuplicateGroup                        │
│  ├── UserProfile + Crate                                  │
│  ├── SessionState + AppSection + TrendPoint               │
│  └── TrackFilters                                         │
├──────────────────────────────────────────────────────────┤
│  Cloud Functions (16 TypeScript files) [LOCKED]           │
│  ├── 10 ingestion clients (Spotify, YouTube, Apple,       │
│  │   Deezer, Billboard, SoundCloud, Beatport, Audius,     │
│  │   Audiomack, MusicBrainz)                              │
│  ├── normalize.ts (signal merging + scoring)              │
│  ├── classify.ts (vibe/energy classification)             │
│  ├── scoring.ts (trend score calculation)                 │
│  └── index.ts (scheduled + manual ingestion)              │
└──────────────────────────────────────────────────────────┘
```

---

## 1. Models (lib/models/) — 9 Files

### Track (`track.dart`)
Core data model representing a unified track from Firestore.

| Field | Type | Description |
|-------|------|-------------|
| id | String | Firestore document ID |
| title | String | Track title |
| artist | String | Artist name |
| artworkUrl | String | Album artwork URL |
| bpm | int | Beats per minute |
| keySignature | String | Musical key (e.g. "7A") |
| genre | String | Genre classification |
| vibe | String | Vibe classification (club, chill, etc.) |
| trendScore | double | 0.0-1.0 aggregated trend momentum |
| regionScores | Map | Per-region scores (GH, NG, ZA, GB, US, DE) |
| platformLinks | Map | Source to URL map |
| energyLevel | double | 0.0-1.0 track energy |
| trendHistory | List | Historical trend snapshots |
| sources | List | Contributing ingestion sources |
| releaseYear | int? | Release year (nullable) |
| createdAt / updatedAt | DateTime | Timestamps |

Key getters:
- `effectiveReleaseYear` — falls back to `createdAt.year`
- `effectiveSources` — falls back to `platformLinks.keys`
- `leadRegion` — region with highest score
- `isRisingFast` — trend delta >= 0.18 or score >= 0.84

### ArtistModel (`artist_model.dart`)
Aggregated artist intelligence built from Track data.

| Field | Type | Description |
|-------|------|-------------|
| id | String | Normalized lowercase name |
| name | String | Display name |
| genres | List | Most common first |
| popularityScore | double | Average trendScore across catalogue |
| trendScore | double | Average of top-5 tracks |
| trackCount | int | Total tracks |
| topTracks | List | Top 5 by trendScore |
| trendingTracks | List | Above-average tracks |
| tracksByEra | Map | Pre-2000, 2000s, 2010s, 2020s |
| bpmRange | List | [min, max] |
| leadRegion | String | Dominant region |
| collaborators | List | Extracted from feat/ft/& patterns |
| tracksByVibe | Map | Grouped by vibe |
| tracksByBpmBucket | Map | 10-BPM bands |
| greatestOfScore | double | Average greatest-of across catalogue |
| allTracks | List | Full sorted catalogue |
| activeSources | Set | All sources present |
| yearRange | List | [earliest, latest] year |

### LibraryTrack (`library_track.dart`)
Local audio file metadata with all fields: filePath, fileName, title, artist, album, genre, bpm, key, durationSeconds, fileSizeBytes, fileExtension, md5Hash, bitrate, sampleRate, year.

Also contains `DuplicateGroup` with tracks, reason, recommended keeper, confidence.

### Other Models
- **UserProfile** — displayName, preferredRegion, watchlist, savedCrates, followedArtists
- **Crate** — id, name, context, trackIds, timestamps
- **SessionState** — userId, displayName, email, provider, isAuthenticated, isDemo
- **AppSection** — enum of 17+ navigation sections
- **TrendPoint** — label + score for trend history
- **TrackFilters** — BPM/energy ranges, genre/vibe/region selectors

---

## 2. Services (lib/services/) — 17 Files

### AI Copilot (`ai_copilot_service.dart`)
- **Model:** GPT-5.4 (from .env OPENAI_MODEL)
- **API:** OpenAI v1/chat/completions with `max_completion_tokens`
- **Streaming:** Server-sent events for real-time response display
- **Intent parsing:** Structured JSON (temperature 0.3)
- **Intents:** buildSet, findArtist, setReleaseRange, matchLibrary, cleanDuplicates, createCrate, general
- **Crate generation:** Parses numbered track lists, searches Apple Music + Spotify, creates AiCrateTrack objects
- **Fallback:** Simulated responses when no API key

### Platform Search (`platform_search_service.dart`)
- Wraps SpotifyArtistService + AppleMusicArtistService
- `search(query)` — parallel search both platforms, merge by title+artist key
- `searchByGenre(genre, era, limit)` — 10+ varied queries for broad coverage
- `searchByArtist(artistName)` — comma-separated multi-artist support
- Deduplicates, combines URLs, sorts by popularity

### Playlist Aggregation (`playlist_aggregation_service.dart`)
- Fetches from Spotify Featured Playlists API + Apple Music Charts API
- Genre-filtered playlist search
- Concurrent fetching with Future.wait()
- 10-second timeout per request

### Set Builder (`set_builder_service.dart`)
- Filters: genre, vibe, BPM range, yearFrom/yearTo, duration
- Greedy next-track selection maximizing transition score
- Transition scoring: energy fit (0.35), BPM proximity (0.25), harmonic compatibility (0.20), trend fit (0.20)
- Full Camelot wheel mapping (24 keys)
- Progressive energy curve from 0.35 to 0.90

### Greatest-Of Engine (`greatest_of_service.dart`)
8-dimension weighted scoring:

| Dimension | Weight | Logic |
|-----------|--------|-------|
| Long-term popularity | 0.20 | Direct trendScore |
| Chart legacy | 0.15 | platformLinks count / 5 |
| Replay longevity | 0.15 | Energy x 0.6 + history bonus |
| DJ usefulness | 0.12 | BPM 85-140 = 1.0, key bonus +0.15 |
| Timelessness | 0.10 | Age factor x trendScore |
| Familiarity | 0.10 | Trend x 0.6 + region breadth x 0.4 |
| Artist influence | 0.08 | regionScores count / 6 |
| Cross-source prominence | 0.10 | (sourceCount - 1) / 2 |

Multi-genre, multi-artist, release-range filtering via effectiveReleaseYear. Era presets: 90s, 2000s, 2010s, 2020s, All Time.

### Library Scanner (`library_scanner_service.dart`)
- **Formats:** MP3, FLAC, WAV, AAC, M4A, OGG, OPUS, AIFF
- **Parallel processing:** 6 concurrent files per batch
- **Metadata:** macOS mdls (Spotlight) for title, artist, album, genre, BPM, key, duration, bitrate, sample rate, year
- **MD5 hashing:** compute() isolate for files > 5MB
- **Incremental cache:** Skips unchanged files (same mtime + size)
- **Fallbacks:** BPM simulation, key simulation, genre guessing

### Local Match (`local_match_service.dart`)
6-tier matching:

| Tier | Method | Confidence |
|------|--------|------------|
| 1 | Exact artist + title | 1.0 |
| 2 | Artist-title inversion | 0.7 |
| 3 | Remix/edit stripped | 0.9 |
| 4 | Fuzzy Levenshtein <= 3 | Variable |
| 5 | Filename heuristic | 0.5-0.7 |
| 6 | Missing | 0.0 |

MatchStatus: found, fuzzyMatch, duplicateVersions, uncertain, missing

### Export (`export_service.dart`)
7 export formats:

| Format | Method |
|--------|--------|
| Rekordbox XML | exportRekordboxXml() |
| Serato CSV | exportSeratoCsv() (with year + bitrate) |
| M3U Playlist | exportM3u() |
| Traktor NML | exportTraktorNml() |
| VirtualDJ XML | exportVirtualDjXml() |
| TIDAL-aware M3U | exportTidalAwareM3u() |
| Missing Manifest | exportMissingManifest() |

Physical crate: virtualOnly, copyFiles, aliasLinks. Auto-logging via ActionLogService. Show in Finder utility.

### Duplicate Detector (`duplicate_detector_service.dart`)
3-tier detection (exact hash 1.0, same title/artist 0.85, similar filename 0.5). Cleanup: trashDuplicates, moveDuplicatesToReview, batchCleanup with minConfidence threshold.

### Artist Service (`artist_service.dart`)
Builds ArtistModel from tracks. Collaborator extraction, vibe/BPM grouping, greatest-of scoring, source aggregation.

### DJ Workflow (`dj_workflow_service.dart`)
Auto-detects VirtualDJ and Serato install paths. Manual override. Auto-load toggle. LibrarySafetySettings for crate mode, cleanup mode, confirmation preference.

### Action Log (`action_log_service.dart`)
Logs exports, crate creation, duplicate cleanup to ~/Documents/VibeRadar/Logs/action_log.tsv. In-memory cache of 200 recent actions.

### Other Services
- **Spotify Artist Service** — Client Credentials, token caching, search/catalogue
- **Apple Music Artist Service** — MusicKit REST API, searchSongs, discography
- **YouTube Search Service** — Data API v3, music category filter
- **Ingest Service** — Manual Cloud Functions trigger
- **Library Persistence** — JSON cache

---

## 3. State Management — 3 Providers

- **WorkspaceController** — section, search, filters, sort, selection, detail panel
- **LibraryNotifier** — scanned tracks, duplicates, scan progress, crates
- **Repository Providers** — DI overrides for Firestore/Mock implementations

Stream providers: sessionProvider, trackStreamProvider, userProfileProvider
Computed: visibleTracksProvider, selectedTrackProvider, genre/vibe/region providers

---

## 4. UI — 21 Files

### Shell (`vibe_shell.dart`, ~2800 lines)
Sidebar (262px) + main panel + detail panel (360/420px). Contains RegionsView, GenresView, SetBuilderView, ShellTrackCard, PlatformResultCard, AI/regular crate cards. Left-click = direct play + detail panel; right-click = action menu.

### 10 Feature Screens

| Screen | Key Features |
|--------|-------------|
| Home | Hero cards, genre chips, hot now grid, rising fast scroll, regional highlights |
| Trending | Track grid, genre/region filters, source badges |
| Search | 3-way search (Spotify+Apple+YouTube), grid cards with BPM, detail dialog |
| Artists | Intelligence tab, Spotify catalogue, eras, BPM analysis, albums |
| For You | Auto-trigger artist picker on first visit |
| Greatest Of | 8-dimension scoring, release-range, multi-genre/artist |
| Library | 5 tabs: All Tracks, Recommendations, Create Crate, Duplicates, Stats |
| Duplicates | Groups with confidence, keeper recommendation, comparison |
| Exports | 7 formats, physical crates, local match, Show in Finder |
| AI Copilot | GPT-5.4 streaming, persistent chat, crate generation, year filter |

### 7 Widgets
SourceBadges, TrackTable, TrackDetailPanel, SidebarNav, TrackActionMenu, FilterBar, DashboardCards

### 3 Auth Screens
AuthGate (session restore), OnboardingScreen (artist selection), SplashScreen (animated intro)

---

## 5. Cloud Functions — 16 Files [LOCKED]

Scheduled ingestion every 30 minutes from 10 sources. Signal merging with genre-region affinity. Trend scoring. Vibe/energy classification. All TypeScript, deployed to Firebase Functions.

---

## 6. Theme

Dark premium desktop theme. Colors: ink (#080914), panel (#111425), panelRaised (#191D33), surface (#1E2340), edge (#272D4E). Accents: cyan, violet, pink, lime, amber, orange. Typography: Google Fonts Inter.

---

## 7. Security and Safety

- Firebase Auth with Keychain persistence, session restore without login flash
- Library READ-ONLY by default (copy-based crates, trash-based cleanup)
- All file operations logged
- Configurable safety settings
- Google Sign-In + Anonymous support

---

## 8. Build and Distribution

- Production: `flutter build macos --release` (116.7MB)
- DMG: `hdiutil create -volname VibeRadar -srcfolder VibeRadar.app -format UDZO`
- Deploy: `firebase deploy --only hosting`
- Live: https://viberadar-462b8.web.app
- Signing: Apple Development cert available, Developer ID Application needed for Gatekeeper

---

## 9. File Tree

```
lib/ (61 files, 25,170 lines)
├── main.dart
├── app/ (app.dart, bootstrap.dart)
├── core/ (firebase_runtime_config.dart, app_theme.dart, formatters.dart)
├── models/ (9 files)
├── services/ (17 files)
├── providers/ (3 files)
├── data/ (4 files)
└── ui/ (21 files)
    ├── auth/ (3)
    ├── shell/ (1)
    ├── features/ (10)
    └── widgets/ (7)

functions/src/ (16 files) [LOCKED]
├── index.ts, types.ts
├── lib/ (classify, config, normalize, scoring)
└── clients/ (10 source integrations)

public/ (index.html + VibeRadar.dmg)
```
