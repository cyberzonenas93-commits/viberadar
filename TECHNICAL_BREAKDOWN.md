# VibeRadar -- Complete Technical Breakdown

> Generated: 2026-03-27
> Codebase: 27,752 lines of Dart across 68 files
> Platform: macOS (Flutter desktop)
> Backend: Firebase (Firestore, Auth, Storage, Cloud Functions v2)

---

## 1. Architecture Overview

| Layer | Technology | Responsibility |
|-------|-----------|----------------|
| **UI** | Flutter (Material 3, dark-only) | Desktop shell, sidebar nav, feature screens, widgets |
| **State** | Riverpod (NotifierProvider, StreamProvider) | Workspace state, session, tracks, library, crates |
| **Services** | Dart service classes | AI copilot, export, scanning, matching, platform APIs |
| **Data** | Repository pattern (abstract + Firestore/Mock) | Tracks, users, sessions with offline caching |
| **Backend** | Firebase Cloud Functions v2 (TypeScript) | Scheduled ingestion from 9 music sources every 30 min |
| **Auth** | Firebase Auth | Email/password, Google Sign-In, anonymous |
| **Storage** | Firebase Storage | Community audio uploads |
| **Hosting** | Firebase Hosting | Landing page (public/) |
| **Local Persistence** | SharedPreferences + JSON file cache | Library cache, crate cache, AI crate cache, settings |

---

## 2. Project Structure

```
lib/
  core/
    theme/
      app_theme.dart              -- Design tokens, Material 3 dark theme
    utils/
      formatters.dart             -- Shared formatting utilities
  data/
    repositories/
      session_repository.dart     -- Auth session (Demo / Firebase)
      track_repository.dart       -- Track data (Mock / Firestore)
      user_repository.dart        -- User profiles (Mock / Firestore)
    sources/
      mock_track_seed.dart        -- Seed data for demo mode
  models/
    app_section.dart              -- Enum of 20 navigation sections
    artist_model.dart             -- Aggregated artist intelligence
    crate.dart                    -- DJ crate container
    library_track.dart            -- Local file track + DuplicateGroup
    session_state.dart            -- Auth session state
    social_profile.dart           -- Community DJ profile
    track.dart                    -- Core trending track model
    track_filters.dart            -- BPM/energy/genre/vibe/region filters
    trend_point.dart              -- Trend history data point
    uploaded_track.dart           -- Community uploaded track
    user_profile.dart             -- User preferences, watchlist, crates
  providers/
    app_state.dart                -- Workspace, session, tracks, filters
    library_provider.dart         -- Library state, crate state, AI crate state
    repositories.dart             -- Repository provider declarations
  services/
    action_log_service.dart       -- File operation audit log
    ai_copilot_service.dart       -- OpenAI GPT chat + structured commands
    apple_music_artist_service.dart -- Apple Music MusicKit REST API
    artist_service.dart           -- Artist aggregate builder
    dj_workflow_service.dart      -- VirtualDJ/Serato path detection + safety
    duplicate_detector_service.dart -- Hash/name/Levenshtein dup detection
    export_service.dart           -- Multi-format DJ export engine
    greatest_of_service.dart      -- 8-dimension cultural impact scoring
    ingest_service.dart           -- Manual Cloud Function trigger
    library_persistence_service.dart -- JSON cache for scanned library
    library_scanner_service.dart  -- macOS mdls-based audio file scanner
    local_match_service.dart      -- Isolate-based library-to-radar matching
    platform_search_service.dart  -- Multi-platform search + merge
    playlist_aggregation_service.dart -- 5-source playlist/chart fetcher
    set_builder_service.dart      -- Energy-arc set construction + Camelot
    spotify_artist_service.dart   -- Spotify Web API (Client Credentials)
    youtube_search_service.dart   -- YouTube Data API v3
  ui/
    features/
      ai_copilot/ai_copilot_screen.dart
      artists/artists_screen.dart
      community/
        community_screen.dart
        discover_djs_screen.dart
        profile_screen.dart
        upload_screen.dart
      duplicates/duplicates_screen.dart
      exports/exports_screen.dart
      for_you/for_you_screen.dart
      greatest_of/greatest_of_screen.dart
      home/home_screen.dart
      library/library_screen.dart
      search/search_screen.dart
      trending/trending_screen.dart
    shell/
      vibe_shell.dart             -- Main app shell (sidebar + content)
    widgets/
      dashboard_cards.dart        -- Stat cards for home dashboard
      filter_bar.dart             -- BPM/energy/genre/vibe/region filter bar
      sidebar_nav.dart            -- Collapsible sidebar navigation
      source_badges.dart          -- Platform source badges (Spotify, etc.)
      track_action_menu.dart      -- Right-click/context menu for tracks
      track_detail_panel.dart     -- Track detail side panel
      track_table.dart            -- Sortable track data table
functions/
  src/
    index.ts                      -- Cloud Functions entry (schedule + HTTP)
    types.ts                      -- TypeScript interfaces
    lib/
      config.ts                   -- Secret refs, region config
      normalize.ts                -- Signal-to-track merge logic
    clients/
      appleMusic.ts               -- Apple Music catalog API
      audiomack.ts                -- Audiomack API
      audius.ts                   -- Audius decentralized API
      beatport.ts                 -- Beatport DJ chart API
      billboard.ts                -- Billboard chart scraper
      deezer.ts                   -- Deezer public chart API
      musicbrainz.ts              -- MusicBrainz metadata enrichment
      soundcloud.ts               -- SoundCloud API
      spotify.ts                  -- Spotify Web API
      youtube.ts                  -- YouTube Data API
```

---

## 3. Data Models

### Track (16 fields, 4 getters)
Core trending track from Firestore. Fields: `id`, `title`, `artist`, `artworkUrl`, `bpm` (int), `keySignature`, `genre`, `vibe`, `trendScore` (double), `regionScores` (Map), `platformLinks` (Map), `createdAt`, `updatedAt`, `energyLevel` (double), `trendHistory` (List<TrendPoint>), `sources` (List<String>), `releaseYear` (int?). Getters: `effectiveReleaseYear`, `effectiveSources`, `leadRegion`, `isRisingFast`. Has `fromMap`/`toMap` with Firestore Timestamp support.

### ArtistModel (22 fields, 6 getters)
Aggregated artist intelligence derived from Track data. Fields: `id`, `name`, `genres`, `popularityScore`, `trendScore`, `trackCount`, `topTracks`, `trendingTracks`, `tracksByEra`, `bpmRange`, `leadRegion`, `artworkUrl`, `spotifyUrl`, `collaborators`, `tracksByVibe`, `tracksByBpmBucket`, `greatestOfScore`, `allTracks`, `activeSources`, `yearRange`. Getters: `primaryGenre`, `hasBpmData`, `bpmRangeLabel`, `hasYearData`, `yearRangeLabel`, `hasCollaborators`, `sourceCount`.

### LibraryTrack (16 fields, 3 getters)
Local audio file metadata. Fields: `id`, `filePath`, `fileName`, `title`, `artist`, `album`, `genre`, `bpm` (double), `key`, `durationSeconds`, `fileSizeBytes`, `fileExtension`, `md5Hash`, `bitrate`, `sampleRate`, `year` (int?), `artworkUrl` (String?). Getters: `releaseYear`, `durationFormatted`, `fileSizeFormatted`. Has `copyWith`.

### DuplicateGroup (4 fields, 1 getter)
Groups of duplicate library tracks. Fields: `tracks`, `reason`, `recommended` (auto-picked best quality), `confidence` (0.0-1.0). Getter: `reasonLabel`. Reasons: `exact_hash`, `same_title_artist`, `similar_name`. Auto-recommends keeper by bitrate > file size > metadata completeness.

### Crate (6 fields)
DJ crate container. Fields: `id`, `name`, `context`, `trackIds`, `createdAt`, `updatedAt`. Has `fromMap`/`toMap`.

### UserProfile (6 fields)
Fields: `id`, `displayName`, `preferredRegion`, `watchlist` (Set<String>), `savedCrates` (List<Crate>), `followedArtists`. Has `copyWith`, `fromMap`/`toMap`, `empty` factory.

### SessionState (6 fields)
Auth state. Fields: `userId`, `displayName`, `email`, `providerLabel`, `isAuthenticated`, `isDemo`. Has `demo()` factory.

### TrackFilters (5 fields, 1 method)
Filter state. Fields: `bpmRange`, `energyRange`, `genre`, `vibe`, `region`. Method: `matches(Track)`.

### TrendPoint (2 fields)
Fields: `label`, `score`. Simple trend history data point.

### SocialProfile (13 fields)
Community DJ profile. Fields: `userId`, `displayName`, `bio`, `photoUrl`, `genres`, `location`, `socialLinks` (Map), `uploadCount`, `followerCount`, `followingCount`, `createdAt`, `updatedAt`, `role`. Roles: DJ, MC, Producer, Artist. Has `fromMap`/`toMap`, `copyWith`.

### UploadedTrack (16 fields, 2 getters)
Community track upload. Fields: `id`, `title`, `artistName`, `audioUrl`, `artworkUrl`, `genre`, `bpm`, `keySignature`, `uploadedBy`, `uploaderName`, `uploadedAt`, `likeCount`, `playCount`, `featured`, `durationSeconds`, `tags`, `uploaderPhotoUrl`. Getters: `durationFormatted`, `timeAgo`.

### AppSection (enum, 20 values)
Navigation sections organized into groups: DISCOVER (forYou, home, trending, search, artists, regions, genres, playlists), COMMUNITY (community, myProfile, upload, discoverDJs), BUILD (greatestOf, setBuilder, aiCopilot), LIBRARY (library, duplicates, savedCrates, watchlist), EXPORT (exports), OTHER (settings).

---

## 4. Services (17 services)

### IngestService
- `triggerIngest()` -- authenticates with service account, POSTs to Cloud Function HTTP endpoint

### AiCopilotService
- `getApiKey()` / `setApiKey()` -- SharedPreferences + .env fallback
- `getModel()` / `setModel()` -- default: gpt-5.4
- `chat()` -- single-shot OpenAI completion with track context (up to 80 tracks)
- `chatStream()` -- SSE streaming response, token-by-token
- `parseCommand()` -- structured intent extraction (JSON mode), returns `AiCopilotCommand`
- Intents: `buildSet`, `findArtist`, `setReleaseRange`, `matchLibrary`, `cleanDuplicates`, `createCrate`, `general`
- `_simulateResponse()` -- offline fallback with genre-specific canned responses

### ExportService
- `exportRekordboxXml()` -- Pioneer Rekordbox XML (DJ_PLAYLISTS format)
- `exportSeratoCsv()` -- Serato-compatible CSV with extended metadata
- `exportM3u()` -- Standard M3U playlist
- `exportTraktorNml()` -- Native Instruments Traktor NML (v19)
- `exportVirtualDjXml()` -- VirtualDJ database XML (v8)
- `exportTidalAwareM3u()` -- M3U with TIDAL search hints for streaming
- `exportMissingManifest()` -- text manifest of tracks not in local library
- `exportAiCrateM3u()` / `exportAiCrateCsv()` / `exportAiCrateManifest()` -- AI crate exports with platform URLs
- `createPhysicalCrate()` -- copies/symlinks files to folder (CrateType: virtualOnly, copyFiles, aliasLinks)
- `getExportsPath()` -- ~/Desktop/VibeRadar Exports
- `revealInFinder()` / `openExportsFolder()` -- macOS Finder integration

### ArtistService
- `buildArtistCatalog()` -- groups tracks by artist, builds ArtistModel aggregates
- `getArtist()` -- single artist lookup by name
- Computes: genres, popularity, trend score, eras, BPM range, lead region, collaborators, vibe grouping, BPM buckets, greatest-of score, active sources, year range

### GreatestOfService
- `computeGreatestScore()` -- 8-dimension weighted score (0.0-1.0)
  - Dimensions: long_term_popularity (0.20), chart_legacy (0.15), replay_longevity (0.15), dj_usefulness (0.12), timelessness (0.10), familiarity (0.10), artist_influence (0.08), cross_source (0.10)
- `buildGreatestOfSet()` -- filter + rank with multi-genre, multi-artist, region, year range support
- `eraLabel()` / `groupByEra()` / `eraPresets` -- era bucketing helpers

### SetBuilderService
- `buildSet()` -- energy-arc-aware set construction
  - Filters by BPM range, genre, vibe, year range
  - Greedy selection optimizing: energy fit (0.35), BPM continuity (0.25), harmonic compatibility (0.20), trend score (0.20)
  - Full Camelot wheel implementation with standard key to Camelot conversion
  - Supports explicit track count or duration-based estimation

### DuplicateDetectorService
- `findDuplicates()` -- 3-tier detection: exact hash, same title+artist, Levenshtein <= 4
- `trashDuplicates()` -- move to macOS ~/.Trash (never deletes)
- `moveDuplicatesToReview()` -- move to review folder for manual inspection
- `batchCleanup()` -- process multiple groups with confidence threshold
- `compareQuality()` -- side-by-side quality comparison

### DjWorkflowService
- `detectVirtualDjPath()` / `getVirtualDjPath()` / `setVirtualDjPath()` -- VirtualDJ library detection
- `detectSeratoPath()` / `getSeratoPath()` / `setSeratoPath()` -- Serato library detection
- `placeInVirtualDj()` / `placeInSerato()` -- auto-place exports in DJ software folders
- `detectAll()` -- summary of all detected DJ software

### LibrarySafetySettings (nested in dj_workflow_service.dart)
- `getCrateMode()` / `setCrateMode()` -- 'copy' or 'alias'
- `getCleanupMode()` / `setCleanupMode()` -- 'trash' or 'review'
- `getConfirmActions()` / `setConfirmActions()` -- require confirmation before file ops
- `getCrateOutputPath()` / `setCrateOutputPath()` -- default output folder
- `getReviewFolderPath()` / `setReviewFolderPath()` -- duplicate review folder

### LibraryScannerService
- `scanDirectory()` -- scans up to 50,000 audio files, supports incremental caching
- Supported formats: `.mp3`, `.flac`, `.wav`, `.aac`, `.m4a`, `.ogg`, `.opus`, `.aiff`
- Uses macOS `mdls` for metadata extraction (batch of 50 files at a time, parallel)
- Extracts: title, artist, album, genre, BPM, key, duration, bitrate, sample rate, year
- Fast hash: path + size + mtime (no file I/O for hash)
- Fallback: filename parsing, genre guessing, simulated BPM/key from hash

### LibraryPersistenceService
- `save()` / `load()` / `clear()` -- JSON cache at ~/Documents/VibeRadar/library_cache.json

### LocalMatchService
- `matchSet()` -- matches radar tracks against local library in background isolate
- 4-tier matching: (1) exact artist+title index, (2) remix-stripped match, (3) filename contains, (4) fuzzy Levenshtein
- Pre-indexes library into 4 hash maps for O(1) exact lookups
- Match statuses: `found`, `fuzzyMatch`, `missing`, `duplicateVersions`, `uncertain`
- Picks best candidate by bitrate > file size > lossless format

### PlatformSearchService
- `search()` -- searches Spotify, Apple Music, YouTube in parallel; merges + deduplicates
- `searchByGenre()` -- 10 query variants for broader coverage, optional era filter
- `searchByArtist()` -- multi-artist support (comma-separated)
- Fuzzy YouTube title matching for cross-platform dedup

### PlaylistAggregationService
- `fetchPlaylists()` -- fetches from all 5 sources in parallel
- Sources: Spotify (featured + category playlists), Apple Music (charts + search), YouTube (Data API + fallback), Deezer (public chart API, no auth), Billboard (via Spotify proxy playlists)

### SpotifyArtistService
- Client Credentials OAuth flow
- `searchTracks()`, `searchArtistsByName()`, `findArtistId()`, `getTopTracks()`, `getAlbums()`, `getAlbumTracks()`, `getFullCatalogue()`, `getArtistProfile()`, `getArtistProfileByName()`, `getRelatedArtists()`, `getLatestRelease()`

### AppleMusicArtistService
- MusicKit REST API with pre-generated developer token (180-day JWT)
- `searchSongs()`, `findArtistId()`, `getTopSongs()`, `getAlbums()`, `getAlbumTracks()`, `getFullDiscography()`, `getTopTracksForArtist()`

### YoutubeSearchService
- YouTube Data API v3, filtered to Music category (videoCategoryId=10)
- `searchMusic()` -- returns cleaned titles/channels (strips "Official Video" etc.)

### ActionLogService
- Singleton with in-memory buffer (200 entries) + TSV file persistence
- `log()`, `logCrateCreation()`, `logExport()`, `logDuplicateCleanup()`
- Log file at ~/Documents/VibeRadar/Logs/action_log.tsv

---

## 5. State Management

All state is managed via **Riverpod** (flutter_riverpod 3.3.1).

### Providers in `app_state.dart`

| Provider | Type | Description |
|----------|------|-------------|
| `workspaceControllerProvider` | `NotifierProvider<WorkspaceController, WorkspaceState>` | Active section, search query, filters, selection, sort, detail panel |
| `sessionProvider` | `StreamProvider<SessionState>` | Firebase Auth session stream |
| `trackStreamProvider` | `StreamProvider<List<Track>>` | Firestore track data stream |
| `userProfileProvider` | `StreamProvider<UserProfile>` | User preferences + watchlist |
| `visibleTracksProvider` | `Provider<List<Track>>` | Filtered + sorted + searched tracks |
| `selectedTrackProvider` | `Provider<Track?>` | Currently selected track |
| `availableGenresProvider` | `Provider<List<String>>` | Dynamic genre list from data |
| `availableVibesProvider` | `Provider<List<String>>` | Dynamic vibe list from data |
| `availableRegionsProvider` | `Provider<List<String>>` | Dynamic region list from data |
| `sessionRepositoryActionsProvider` | `Provider<SessionRepository>` | Session repo for auth actions |

### WorkspaceState fields
`section` (AppSection), `searchQuery`, `filters` (TrackFilters), `selectedTrackIds` (Set), `primaryTrackId`, `sortColumn` (TrackSortColumn), `sortAscending`, `detailExpanded`

### TrackSortColumn enum
`title`, `artist`, `bpm`, `keySignature`, `genre`, `vibe`, `trendScore`, `region`

### Providers in `library_provider.dart`

| Provider | Type | Description |
|----------|------|-------------|
| `libraryProvider` | `NotifierProvider<LibraryNotifier, LibraryState>` | Library scan state, tracks, duplicates |
| `crateProvider` | `NotifierProvider<CrateNotifier, CrateState>` | Named crates with track IDs |
| `aiCrateProvider` | `NotifierProvider<AiCrateNotifier, AiCrateState>` | AI-generated crates with rich metadata |
| `libraryScannerServiceProvider` | `Provider<LibraryScannerService>` | Scanner instance |
| `duplicateDetectorServiceProvider` | `Provider<DuplicateDetectorService>` | Duplicate detector instance |
| `libraryPersistenceServiceProvider` | `Provider<LibraryPersistenceService>` | Persistence instance |

### LibraryState fields
`tracks`, `duplicateGroups`, `isScanning`, `isLoading`, `scanProgress`, `scanTotal`, `scannedPath`, `error`

### LibraryNotifier capabilities
- `scanDirectory()` -- scan with throttled progress updates (every 500ms)
- `_detectDuplicatesAsync()` -- background isolate duplicate detection (skips >10,000 tracks)
- `_enrichArtworkAsync()` -- fetches artwork from Spotify/Apple Music (batches of 20, rate-limited)
- `fetchAllArtwork()` -- user-triggered full artwork enrichment
- `removeTrack()` / `clearLibrary()`

### Repository Providers in `repositories.dart`
`trackRepositoryProvider`, `userRepositoryProvider`, `sessionRepositoryProvider` -- overridden at app startup with Firestore or Mock implementations.

---

## 6. UI Architecture

### Shell
`VibeShell` -- main app scaffold with collapsible sidebar navigation and content area. Routes to feature screens based on `AppSection` enum.

### Feature Screens (14 screens)

| Screen | Path | Description |
|--------|------|-------------|
| **HomeScreen** | `home` | Dashboard with stat cards, top tracks table |
| **ForYouScreen** | `forYou` | Personalized recommendations based on preferences |
| **TrendingScreen** | `trending` | Trending tracks by region/genre/vibe |
| **SearchScreen** | `search` | Multi-platform search (Spotify, Apple Music, YouTube) |
| **ArtistsScreen** | `artists` | Artist catalog with intelligence cards |
| **GreatestOfScreen** | `greatestOf` | Cultural impact-ranked tracks with 8D scoring |
| **AiCopilotScreen** | `aiCopilot` | GPT chat with structured command parsing |
| **LibraryScreen** | `library` | Local library browser with scan, enrich, export |
| **DuplicatesScreen** | `duplicates` | Duplicate groups with quality comparison + cleanup |
| **CommunityScreen** | `community` | Community feed of uploaded tracks |
| **ProfileScreen** | `myProfile` | User's social profile editor |
| **UploadScreen** | `upload` | Audio file upload to community |
| **DiscoverDJsScreen** | `discoverDJs` | Browse other DJ profiles |
| **ExportsScreen** | `exports` | Export history, format selection, DJ software detection |

### Shared Widgets (7 widgets)

| Widget | Description |
|--------|-------------|
| `DashboardCards` | Stat summary cards (total tracks, rising, genres, etc.) |
| `FilterBar` | Horizontal filter bar with BPM range, energy, genre, vibe, region dropdowns |
| `SidebarNav` | Collapsible sidebar with section groups and icons |
| `SourceBadges` | Colored badges showing track's platform sources |
| `TrackActionMenu` | Context menu: add to watchlist, add to crate, open on platform, export |
| `TrackDetailPanel` | Right-side panel showing trend chart, metadata, platform links |
| `TrackTable` | Sortable, selectable data table with artwork thumbnails |

---

## 7. Theme

**Dark-only** Material 3 theme using Google Fonts (Inter).

### Color Tokens

| Token | Hex | Usage |
|-------|-----|-------|
| `ink` | `#080914` | Scaffold background |
| `panel` | `#111425` | Card/surface background |
| `panelRaised` | `#191D33` | Elevated surfaces, inputs |
| `surface` | `#1E2340` | Secondary surfaces |
| `edge` | `#272D4E` | Borders, dividers |
| `cyan` | `#3AD7FF` | Secondary accent |
| `violet` | `#8F6CFF` | Primary accent, buttons, focus rings |
| `pink` | `#FF4DA6` | Tertiary accent |
| `lime` | `#4ADE80` | Success/positive |
| `amber` | `#FBBF24` | Warning |
| `orange` | `#FB923C` | Alert |
| `textPrimary` | `#EEF0F9` | Body text |
| `textSecondary` | `#9CA3C4` | Labels, subtitles |
| `textTertiary` | `#636B8C` | Hints, disabled |
| `sectionHeader` | `#6B74A0` | Sidebar section headers |

---

## 8. Cloud Functions (LOCKED)

**Runtime**: Firebase Cloud Functions v2, TypeScript, Node.js
**Schedule**: `every 30 minutes` (UTC), us-central1, 512MiB memory, 300s timeout

### Ingestion Pipeline

1. **Global sources** (run first, no region): Audius, Audiomack
2. **Per-region sources** (with 2s delay between regions): Spotify, YouTube, Apple Music, SoundCloud, Beatport, Deezer
3. **Billboard** (US-only, outside region loop)
4. **MusicBrainz enrichment** (post-merge metadata enrichment)
5. **Merge** into unified tracks via `mergeSignalsIntoTracks()`
6. **Write** to Firestore in batches of 499

### Source Clients (10 files)
`appleMusic.ts`, `audiomack.ts`, `audius.ts`, `beatport.ts`, `billboard.ts`, `deezer.ts`, `musicbrainz.ts`, `soundcloud.ts`, `spotify.ts`, `youtube.ts`

### TypeScript Types

**SourceTrackSignal** (13 fields): source (union of 9 platforms), sourceId, title, artist, artworkUrl?, genre?, bpm?, key?, keywords, region?, platformUrl, engagement, growthRate, recency, releasedAt?

**UnifiedTrackRecord** (16 fields): id, title, artist, artwork_url, bpm, key, genre, vibe, trend_score, region_scores, platform_links, created_at, updated_at, energy_level, trend_history, source_count, sources

**IngestionSummary** (4 fields): fetchedSignals, writtenTracks, regions, sources

### Endpoints
- `ingestTrackSignals` -- scheduled (every 30 min)
- `manualIngestTrackSignals` -- HTTP endpoint with Bearer token auth

### Retry Logic
`withRetry()` -- 2 retries with exponential backoff (1500ms * attempt)

---

## 9. Authentication

**Provider**: Firebase Auth
**Methods**:
1. **Email/Password** -- `createAccount()`, `signInWithEmail()`
2. **Google Sign-In** -- via `google_sign_in` package, macOS URL scheme registered
3. **Anonymous** -- `signInAnonymously()` for guest access

**Session Persistence**:
- "Remember me" preference stored in SharedPreferences
- Cold start: waits up to 3s for Firebase to restore session from Keychain
- Demo mode: hardcoded `SessionState.demo()` with `demo-dj` user

**Google OAuth Config**:
- Client ID: `927344201419-7daqi4nk04m84f3de0677eti4lmo15ll.apps.googleusercontent.com`
- URL scheme registered in Info.plist

---

## 10. Export Formats

### Local Library Exports (file-based)

| Format | Extension | Target Software |
|--------|-----------|-----------------|
| Rekordbox XML | `.xml` | Pioneer Rekordbox |
| Serato CSV | `.csv` | Serato DJ Pro |
| M3U Playlist | `.m3u` | Universal |
| Traktor NML | `.nml` | Native Instruments Traktor |
| VirtualDJ XML | `.xml` | VirtualDJ 8+ |
| TIDAL-Aware M3U | `.m3u` | TIDAL-integrated software |
| Missing Manifest | `.txt` | Human-readable |

### AI Crate Exports (metadata-only, with platform URLs)

| Format | Extension | Description |
|--------|-----------|-------------|
| AI M3U | `.m3u` | M3U with streaming URLs |
| AI CSV | `.csv` | Importable to DJ software |
| AI Manifest | `.txt` | Human-readable with status |

### Physical Crate Creation

| Mode | Description |
|------|-------------|
| `virtualOnly` | M3U playlist only, no file copy |
| `copyFiles` | Copies audio files to destination folder |
| `aliasLinks` | macOS symlinks to source files |

Output: `~/Desktop/VibeRadar Exports/`

---

## 11. AI Copilot Capabilities

**Model**: OpenAI GPT-5.4 (configurable via settings)
**Endpoint**: `https://api.openai.com/v1/chat/completions`
**API Key**: User-provided via settings or `.env` file

### Chat Features
- **Streaming**: SSE-based token-by-token streaming
- **Track context**: Up to 80 tracks injected into system prompt
- **Year filter awareness**: Active year filters included in prompt
- **Crate generation**: Parses ```crate JSON blocks from response to auto-create crates

### Structured Command Parsing
Uses `response_format: json_object` for reliable JSON extraction.

| Intent | Action |
|--------|--------|
| `buildSet` | Build a DJ set with genre/BPM/year filters |
| `findArtist` | Search for artist tracks |
| `setReleaseRange` | Apply year range filter |
| `matchLibrary` | Match radar tracks against local library |
| `cleanDuplicates` | Navigate to duplicate cleanup |
| `createCrate` | Create a named crate |
| `general` | General music/DJ advice |

### Offline Fallback
Genre-specific canned responses for Afrobeats, Amapiano, harmonic mixing, set building.

---

## 12. Community/Social Features

### SocialProfile
- Display name, bio, photo, genres, location, social links (Map)
- Role system: DJ, MC, Producer, Artist
- Follower/following counts, upload count
- Firestore-backed with Timestamp support

### UploadedTrack
- Audio file upload to Firebase Storage
- Metadata: title, artist, genre, BPM, key, duration, tags
- Engagement: like count, play count, featured flag
- Uploader attribution: name, photo, ID

### Screens
- **CommunityScreen**: Browse uploaded tracks feed
- **ProfileScreen**: Edit own DJ profile
- **UploadScreen**: Upload audio with metadata
- **DiscoverDJsScreen**: Browse other DJ profiles

---

## 13. Library Management Features

### Scanning
- Scans macOS directories for audio files (8 supported formats)
- Uses `mdls` for metadata extraction (batch parallel processing)
- Incremental scanning with mtime/size cache (skips unchanged files)
- Max 50,000 files per scan, max 2GB per file
- Progress reporting with 500ms UI throttling

### Artwork Enrichment
- Post-scan background enrichment from Spotify + Apple Music
- Deduplicates API calls by artist+title
- Batches UI updates every 20 tracks
- Rate limiting: 200ms delay every 5 API calls
- User-triggered "fetch all" mode (no cap)

### Duplicate Detection
- 3-tier detection: exact MD5 hash, same title+artist, Levenshtein <= 4
- Background isolate execution (skips >10,000 tracks)
- Confidence scoring: exact=1.0, title+artist=0.85, similar=0.5
- Auto-recommends best quality file to keep

### Crate Management
- Named crates with track ID lists
- Persisted to JSON at ~/Documents/VibeRadar/crates_cache.json
- AI crates with rich metadata (URLs, artwork, resolved status)
- AI crate persistence at ~/Documents/VibeRadar/ai_crates_cache.json

### Local Matching
- Matches VibeRadar trending tracks against local library
- Runs in background Dart isolate via `compute()`
- 4-tier matching with pre-indexed hash maps
- Match methods: exact, exact_duplicate, remix_stripped, filename, fuzzy
- Picks best file by bitrate > size > lossless format

---

## 14. Safety Features

### File Operations
- **Never deletes**: duplicate cleanup moves to macOS Trash or review folder
- **Confirmation required**: `LibrarySafetySettings.getConfirmActions()` default true
- **Action logging**: every file operation logged to TSV audit file
- **Missing track tracking**: physical crate creation reports missing files

### Settings (via LibrarySafetySettings)
- Crate creation mode: copy vs alias (symlink)
- Cleanup destination: Trash vs review folder
- Configurable output paths for crates and review folders
- All settings persisted via SharedPreferences

---

## 15. DJ Software Integration

### VirtualDJ
- Auto-detects: `~/Documents/VirtualDJ`, `~/Library/Application Support/VirtualDJ`, `~/Music/VirtualDJ`
- Auto-places exports in `VirtualDJ/Playlists/`
- VirtualDJ XML export format (v8)

### Serato
- Auto-detects: `~/Music/_Serato_`, `~/Music/Serato`, `~/Library/Application Support/Serato`, `~/Documents/Serato`
- Auto-places exports in `Serato/SubCrates/`
- Serato CSV export format

### Rekordbox
- Rekordbox XML export (DJ_PLAYLISTS v1.0.0)

### Traktor
- Traktor NML export (v19)

### TIDAL Integration
- TIDAL-aware M3U with search hints for streaming tracks

---

## 16. Dependencies

### Flutter/Dart
| Package | Version | Purpose |
|---------|---------|---------|
| flutter_riverpod | 3.3.1 | State management |
| google_fonts | 8.0.2 | Inter font family |
| fl_chart | 1.2.0 | Trend history charts |
| firebase_core | 4.6.0 | Firebase SDK |
| firebase_auth | 6.3.0 | Authentication |
| cloud_firestore | 6.2.0 | Database |
| firebase_storage | 13.2.0 | File uploads |
| google_sign_in | 7.2.0 | Google OAuth |
| window_manager | 0.3.9 | Desktop window control |
| go_router | 14.0.0 | Navigation |
| http | 1.2.1 | HTTP client |
| shared_preferences | 2.2.3 | Local key-value storage |
| cached_network_image | 3.3.1 | Image caching |
| flutter_animate | 4.5.0 | Animations |
| file_picker | 10.3.10 | File/folder selection |
| crypto | 3.0.7 | MD5 hashing |
| path_provider | 2.1.5 | App directories |
| flutter_dotenv | 5.2.1 | Environment variables |
| url_launcher | 6.3.2 | Open URLs in browser |
| uuid | 4.4.0 | UUID generation |
| collection | 1.19.1 | Collection utilities |
| path | 1.9.1 | Path manipulation |
| intl | 0.20.2 | Internationalization |
| logger | 2.3.0 | Logging |
| cupertino_icons | 1.0.8 | iOS-style icons |

### SDK
- Dart SDK: ^3.11.0

---

## 17. Build/Deploy Pipeline

### macOS App
- Bundle identifier set via Xcode project
- Google Sign-In URL scheme registered in Info.plist
- DMG distribution via `public/VibeRadar.dmg` on Firebase Hosting
- App icon: custom logo filling 90% of canvas

### Firebase
- **Firestore**: `tracks` collection, `users` collection, rules file
- **Storage**: rules for community uploads
- **Functions**: TypeScript, deployed from `functions/` directory
- **Hosting**: static landing page from `public/` directory

### Environment
- `.env` file bundled as Flutter asset
- Keys: OPENAI_API_KEY, OPENAI_MODEL, SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET, APPLE_MUSIC_TOKEN, YOUTUBE_DATA_API_KEY

---

## 18. Files Modified in This Session vs Locked Files

### Modified (working tree changes)
| File | Status |
|------|--------|
| `lib/services/local_match_service.dart` | Modified |
| `macos/Runner.xcodeproj/project.pbxproj` | Modified |
| `public/index.html` | Modified |
| `public/VibeRadar.dmg` | Modified |
| `.firebase/hosting.cHVibGlj.cache` | Modified |

### Locked (Cloud Functions -- do NOT modify)
| File | Description |
|------|-------------|
| `functions/src/index.ts` | Ingestion pipeline entry point |
| `functions/src/types.ts` | TypeScript interfaces |
| `functions/src/lib/config.ts` | Secret configuration |
| `functions/src/lib/normalize.ts` | Signal merge logic |
| `functions/src/clients/*.ts` | All 10 source client files |

---

## 19. Known Limitations

1. **macOS only** -- uses `mdls` for metadata, macOS Trash for cleanup, symlinks for alias crates
2. **Firestore cost optimization** -- uses single `.get()` fetches instead of live listeners; manual refresh required for new data
3. **Duplicate detection cap** -- skips libraries over 10,000 tracks to prevent isolate serialization freeze
4. **Artwork enrichment cap** -- defaults to 100 tracks per scan; user must trigger "fetch all" for complete coverage
5. **Apple Music token** -- pre-generated JWT with 180-day expiry; must be manually rotated
6. **Billboard** -- no public API; proxied through Spotify playlist search for Billboard-labeled playlists
7. **No real-time sync** -- Cloud Functions run on schedule (every 30 min); no WebSocket/push notifications
8. **Single-user crates** -- crates are local (JSON file) or Firestore user document; no shared/collaborative crates
9. **AI Copilot** -- requires OpenAI API key; no local LLM fallback beyond canned responses
10. **No iOS/Android** -- desktop-only Flutter app; no mobile builds configured
11. **Scan performance** -- parallel `mdls` calls can saturate I/O on very large libraries; batch size capped at 50
12. **Community features** -- social graph (follow/unfollow) is Firestore-based but no feed algorithm or notifications
