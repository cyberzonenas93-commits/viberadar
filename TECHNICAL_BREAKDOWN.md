# VibeRadar — Technical Breakdown

> DJ trend intelligence platform. Aggregates signals from 9 music sources, scores them, and surfaces actionable insights for DJs in a desktop-grade Flutter app.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Flutter macOS App                            │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐   │
│  │ Riverpod │  │ Services │  │   UI     │  │  Local Store  │   │
│  │ State    │  │ (8)      │  │ (8 scr.) │  │ SharedPrefs   │   │
│  └────┬─────┘  └────┬─────┘  └──────────┘  │ File Cache    │   │
│       │              │                       └──────────────┘   │
│       └──────────────┴───────────────┐                          │
│                                      ▼                          │
│                            Cloud Firestore                      │
│                          (real-time streams)                    │
└─────────────────────────────────────────────────────────────────┘
                               ▲
                               │ writes every 30 min
┌─────────────────────────────────────────────────────────────────┐
│                   Firebase Cloud Functions (v2)                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Ingestion Pipeline (TypeScript)              │   │
│  │                                                           │   │
│  │  Spotify ──┐                                              │   │
│  │  YouTube ──┤                                              │   │
│  │  Apple   ──┤    ┌───────────┐    ┌─────────┐             │   │
│  │  Deezer  ──┼───►│ Normalize │───►│  Score  │──► Firestore│   │
│  │  Billboard─┤    │ & Merge   │    │ & Rank  │             │   │
│  │  SoundCloud┤    └───────────┘    └─────────┘             │   │
│  │  Beatport ─┤                                              │   │
│  │  Audius  ──┤                                              │   │
│  │  Audiomack─┘                                              │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Tech Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| Frontend | Flutter (Dart) | SDK ^3.11.0 |
| State | Riverpod | ^3.3.1 |
| Backend | Firebase Cloud Functions v2 | Node 20 |
| Database | Cloud Firestore | Real-time |
| Auth | Firebase Auth | Email + Google |
| AI | OpenAI API | gpt-5.4 |
| Desktop | window_manager | macOS native |
| Fonts | Google Fonts (Inter) | ^8.0.2 |

---

## Firebase Project

| Setting | Value |
|---------|-------|
| Project ID | `viberadar-462b8` |
| API Key | `AIzaSyCDZ2kVmhIQenh-YsI_sWXIYDPmWmMFmRE` |
| iOS Bundle ID | `com.viberadar.viberadar` |
| Functions Region | `us-central1` |
| Ingest Schedule | Every 30 minutes |
| Ingest Regions | US, GB, GH, NG, ZA, DE |

### Firestore Collections

**`/tracks/{trackId}`** — 1,900+ documents
```
id: string                          // SHA1 hash of canonical title::artist
title: string
artist: string
artwork_url: string
bpm: number
key: string                         // Camelot notation (e.g., "7A")
genre: string                       // Afrobeats, Amapiano, House, Hip-Hop, etc.
vibe: string                        // aggressive, club, afro-smooth, chill, lounge, hype
trend_score: number                 // 0–1, primary ranking metric
region_scores: {[region]: number}   // GH: 0.9, NG: 0.8, US: 0.5, etc.
platform_links: {[source]: string}  // spotify, youtube, apple, deezer, etc.
energy_level: number                // 0.12–0.99
trend_history: [{label, score}]     // Last 7 snapshots for momentum graph
source_count: number                // How many platforms feature this track
created_at: string                  // ISO 8601
updated_at: string                  // ISO 8601
```

**`/users/{userId}`**
```
display_name: string
preferences: {region: string}
watchlist: [trackId]
saved_crates: [{id, name, context, track_ids, created_at, updated_at}]
```

---

## Data Sources (9 total)

| Source | Auth | Method | What it fetches |
|--------|------|--------|-----------------|
| **Spotify** | Client Credentials | Search + Recommendations | Genre-seeded tracks, 30/query, 6 regions |
| **YouTube** | API Key | Data API v3 | Top 20 music videos/region (category 10) |
| **Apple Music** | Developer Token (JWT) | Catalog Charts | Top songs per storefront |
| **Deezer** | None (free) | Charts + Search + Playlists | Regional charts, Afro Hits, Viral Afro |
| **Billboard** | None (GitHub JSON) | Hot 100 archive | Weekly chart positions |
| **SoundCloud** | OAuth Token | Trending search | Favorites, plays, comments |
| **Beatport** | Partner API Token | Feed endpoint | BPM, key, genre (most accurate) |
| **Audius** | None (free) | Trending endpoint | Decentralized platform trends |
| **Audiomack** | OAuth 1.0a | Trending feed | African/Caribbean music focus |

---

## Ingestion Pipeline

```
Every 30 minutes (or manual trigger):

1. FETCH — 5,500+ signals from 9 sources across 6 regions
   └─ Each signal: {source, title, artist, engagement, growthRate, recency, region}

2. FILTER — Blocklist removes non-DJ content
   └─ Blocked: BTS, BLACKPINK, K-pop, country, gospel, classical, metal, punk

3. MERGE — Canonical key = lowercase(title)::lowercase(artist)
   └─ Deduplicates across sources, merges platform links

4. GENRE-REGION AFFINITY — Post-merge scoring
   ├─ GH: Afrobeats (1.0), Dancehall (0.4), Amapiano (0.3) → all else blocked
   ├─ NG: Afrobeats (1.0), Dancehall (0.3) → all else blocked
   ├─ ZA: Amapiano (1.0), Gqom (0.9), House (0.15), Afrobeats (0.1)
   ├─ GB: Drill (0.9), UK Garage (0.9), House (0.6), Hip-Hop (0.5)
   ├─ US: Hip-Hop (0.8), R&B (0.8), Latin (0.6), House (0.4)
   └─ Threshold: score > 0.15 or region is dropped

5. SCORE — Weighted trend formula:
   ├─ growthRate:        40%
   ├─ engagement:        20%
   ├─ recency:           20%
   ├─ platformDiversity: 10%  (appears on more platforms = higher)
   └─ regionWeight:      10%  (popular in more regions = higher)

6. CLASSIFY
   ├─ Vibe: aggressive | club | afro-smooth | chill | lounge | hype
   └─ Energy: BPM 85→0.12, BPM 155→0.98 (linear + genre/keyword adjustments)

7. WRITE — 1,900+ UnifiedTrackRecords to Firestore /tracks/{id}
   └─ Merges with existing trend_history (keeps last 7 snapshots)
```

---

## Flutter App Structure

### File Count: 48 Dart files

```
lib/
├── main.dart                           # Entry point, dotenv, window manager
├── app/
│   ├── app.dart                        # MaterialApp, dark theme
│   └── bootstrap.dart                  # Firebase init, repo injection, demo fallback
├── core/
│   ├── config/
│   │   └── firebase_runtime_config.dart  # Runtime Firebase config via dart-define
│   ├── theme/
│   │   └── app_theme.dart              # Dark theme, Google Fonts (Inter), color palette
│   └── utils/
│       └── formatters.dart             # Number/date formatters, regionScoreForTrack
├── data/
│   ├── repositories/
│   │   ├── track_repository.dart       # Firestore + Mock track streams
│   │   ├── user_repository.dart        # Firestore + Mock user profiles
│   │   └── session_repository.dart     # Firebase Auth + Demo sessions
│   └── sources/
│       └── mock_track_seed.dart        # 20+ realistic mock tracks for demo mode
├── models/
│   ├── track.dart                      # Core track model (BPM, key, score, regions)
│   ├── library_track.dart              # Local file metadata + DuplicateGroup
│   ├── user_profile.dart               # Preferences, watchlist, crates
│   ├── crate.dart                      # Playlist/set container
│   ├── trend_point.dart                # Historical score snapshot
│   ├── session_state.dart              # Auth state (user, email, provider)
│   ├── track_filters.dart              # BPM/energy/genre/vibe/region filters
│   └── app_section.dart                # Navigation enum (14 sections)
├── providers/
│   ├── app_state.dart                  # WorkspaceController, computed providers
│   ├── library_provider.dart           # LibraryNotifier, CrateNotifier
│   └── repositories.dart               # Provider wrappers for DI
├── services/
│   ├── ai_copilot_service.dart         # OpenAI chat + crate generation
│   ├── spotify_artist_service.dart     # Spotify artist catalog lookup
│   ├── ingest_service.dart             # Manual re-ingestion trigger
│   ├── set_builder_service.dart        # Algorithmic DJ set generation
│   ├── library_scanner_service.dart    # Local audio file scanner (macOS mdls)
│   ├── library_persistence_service.dart # Library cache to disk
│   ├── duplicate_detector_service.dart # MD5 + Levenshtein deduplication
│   └── export_service.dart             # Rekordbox XML, Serato CSV, M3U, Traktor NML
└── ui/
    ├── auth/
    │   ├── auth_gate.dart              # Auth routing
    │   ├── splash_screen.dart          # Loading state
    │   └── onboarding_screen.dart      # First-run setup
    ├── shell/
    │   └── vibe_shell.dart             # Main layout (sidebar + content + detail)
    ├── features/
    │   ├── home/home_screen.dart       # Dashboard: hero, grid, rising, regional
    │   ├── trending/trending_screen.dart  # Artwork grid, filters, ranked cards
    │   ├── artists/artists_screen.dart # Artist grid + Spotify catalog child view
    │   ├── greatest_of/greatest_of_screen.dart # Podium + ranked grid
    │   ├── ai_copilot/ai_copilot_screen.dart  # Chat + crate builder
    │   ├── library/library_screen.dart # Local file browser + scan
    │   ├── duplicates/duplicates_screen.dart # Duplicate detection
    │   └── exports/exports_screen.dart # Crate export to DJ software
    └── widgets/
        ├── sidebar_nav.dart            # Navigation + refresh button
        ├── track_table.dart            # Sortable multi-select PaginatedDataTable
        ├── track_detail_panel.dart     # Right-side info + momentum chart
        ├── track_action_menu.dart      # Context menu (play, add to crate, info)
        ├── dashboard_cards.dart        # KPI summary cards
        ├── filter_bar.dart             # BPM/energy/genre/vibe/region filters
        └── source_badges.dart          # Platform availability badges
```

### Cloud Functions Structure

```
functions/
├── src/
│   ├── index.ts                        # Cloud Function exports, orchestration
│   ├── types.ts                        # SourceTrackSignal, UnifiedTrackRecord
│   ├── clients/
│   │   ├── spotify.ts                  # Search + recommendations + genre seeds
│   │   ├── youtube.ts                  # Data API v3, trending music videos
│   │   ├── appleMusic.ts              # Catalog charts per storefront
│   │   ├── deezer.ts                  # Charts + search + editorial playlists
│   │   ├── billboard.ts               # Hot 100 JSON archive
│   │   ├── soundcloud.ts             # OAuth trending search
│   │   ├── beatport.ts               # Partner feed (optional)
│   │   ├── audius.ts                  # Decentralized trending
│   │   ├── audiomack.ts              # OAuth 1.0a trending
│   │   └── musicbrainz.ts            # Harmonic key enrichment
│   └── lib/
│       ├── normalize.ts               # Signal merge, blocklist, genre-region affinity
│       ├── scoring.ts                 # Min-max normalization, weighted trend formula
│       ├── classify.ts                # Vibe classification, energy derivation
│       └── config.ts                  # Secret definitions, region config
├── package.json
└── tsconfig.json
```

---

## State Management (Riverpod)

### Stream Providers (Real-time from Firestore)
| Provider | Source | Updates |
|----------|--------|---------|
| `sessionProvider` | Firebase Auth | On auth state change |
| `trackStreamProvider` | Firestore /tracks | Real-time (limit 500, ordered by trend_score) |
| `userProfileProvider` | Firestore /users/{uid} | Real-time |

### Computed Providers (Derived)
| Provider | Derives From | Purpose |
|----------|-------------|---------|
| `visibleTracksProvider` | tracks + workspace filters | Filtered & sorted track list |
| `selectedTrackProvider` | tracks + workspace.primaryTrackId | Currently selected track |
| `availableGenresProvider` | all tracks | Unique genre list for filter chips |
| `availableVibesProvider` | all tracks | Unique vibe list |
| `availableRegionsProvider` | all tracks | Unique region list |

### Notifiers (Mutable State)
| Notifier | State Class | Key Methods |
|----------|------------|-------------|
| `WorkspaceController` | `WorkspaceState` | setSection, setSearchQuery, updateFilters, sortBy, toggleSelection, activateTrack |
| `LibraryNotifier` | `LibraryState` | scanDirectory, clearLibrary |
| `CrateNotifier` | `CrateState` | createCrate, addTrackToCrate, removeTrackFromCrate, deleteCrate |

---

## Services

| Service | Purpose | Key Methods |
|---------|---------|-------------|
| `AiCopilotService` | OpenAI gpt-5.4 chat with crate generation | `chat(history, message, trackContext)` |
| `SpotifyArtistService` | Full artist discography from Spotify | `getFullCatalogue(artistName)` → albums + tracks |
| `IngestService` | Trigger cloud re-ingestion from app | `triggerIngest()` → authenticates + calls function |
| `SetBuilderService` | Algorithmic DJ set generation | `buildSet(tracks, duration, genre, vibe, bpmRange)` |
| `LibraryScannerService` | Scan local audio files (macOS) | `scanDirectory(path, onProgress)` |
| `LibraryPersistenceService` | Cache library to disk | `load()`, `save()`, `clear()` |
| `DuplicateDetectorService` | Find duplicate files | `findDuplicates(tracks)` → MD5 + Levenshtein |
| `ExportService` | Export crates to DJ software | Rekordbox XML, Serato CSV, M3U, Traktor NML |

---

## Theme System

### Color Palette
```
Background:  ink (#0A0D1A) → panel (#12162B) → panelRaised (#1A1F38) → surface (#1E2340)
Borders:     edge (#2A3155)
Accents:     cyan (#00D4FF) | violet (#8B5CF6) | pink (#FF4D8A) | lime (#4ADE80) | amber (#FBBF24)
Text:        primary (#EEF0F9) | secondary (#9CA3C4) | tertiary (#636B8C) | sectionHeader (#6B74A0)
```

### Typography: Google Fonts — Inter
- Display: 800 weight, -1.5 letter spacing
- Headlines: 700 weight, -0.5 to -0.8 letter spacing
- Titles: 600-700 weight
- Body: 400-500 weight, 1.4-1.5 line height

### Component Tokens
| Component | Border Radius | Background | Border |
|-----------|--------------|------------|--------|
| Cards | 16px | panel | edge @ 0.5 alpha |
| Inputs | 12px | panelRaised | edge @ 0.6 alpha |
| Chips | 999px (pill) | panelRaised | edge @ 0.5 alpha |
| Buttons | 10px | violet gradient | none |
| Track cards | 14px | panel → panelRaised on hover | edge @ 0.35–0.6 alpha |

---

## Scoring Algorithm

### Trend Score Formula
```
trendScore =
    normalizedGrowthRate   × 0.40
  + normalizedEngagement   × 0.20
  + normalizedRecency      × 0.20
  + normalizedPlatformDiv  × 0.10
  + normalizedRegionWeight × 0.10
```

### Genre-Region Affinity Matrix
| Region | Afrobeats | Dancehall | Amapiano | Gqom | House | Hip-Hop | R&B | Drill | UK Garage | Pop | Everything Else |
|--------|-----------|-----------|----------|------|-------|---------|-----|-------|-----------|-----|----------------|
| **GH** | 1.0 | 0.4 | 0.3 | — | — | — | — | — | — | — | 0.02 (blocked) |
| **NG** | 1.0 | 0.3 | — | — | — | 0.05 | 0.05 | — | — | — | 0.02 (blocked) |
| **ZA** | 0.1 | — | 1.0 | 0.9 | 0.15 | — | — | — | — | — | 0.02 (blocked) |
| **GB** | 0.4 | — | — | — | 0.6 | 0.5 | 0.4 | 0.9 | 0.9 | 0.2 | 0.02 |
| **US** | 0.2 | — | — | — | 0.4 | 0.8 | 0.8 | — | — | 0.3 | 0.02 |
| **DE** | 0.1 | — | — | — | 0.8 | 0.3 | — | — | — | 0.2 | 0.02 |

Threshold: region score must be > 0.15 or it's dropped entirely.

### Vibe Classification
| Vibe | Conditions |
|------|-----------|
| Aggressive | BPM ≥ 145 OR drill/rage keywords |
| Afro-smooth | Amapiano genre + BPM < 120 |
| Club | House/dance + BPM > 126, OR Amapiano + BPM ≥ 120 |
| Hype | BPM ≥ 135 OR party/hype keywords |
| Chill | R&B/soul genre OR BPM < 100 |
| Lounge | BPM < 122 (default) |

### Energy Level
Linear mapping: BPM 85 → 0.12, BPM 155 → 0.98, with genre/keyword adjustments (±0.1).

---

## Environment & Secrets

### Local (.env — decrypted from .env.encrypted)
```
OPENAI_API_KEY=sk-proj-...          # AI Copilot
OPENAI_MODEL=gpt-5.4                # Default model
SPOTIFY_CLIENT_ID=c22011...         # Artist catalog lookup
SPOTIFY_CLIENT_SECRET=8c1d3d...     # Artist catalog lookup
```

### Firebase Secret Manager (Cloud Functions)
```
SPOTIFY_CLIENT_ID                    # Ingestion pipeline
SPOTIFY_CLIENT_SECRET                # Ingestion pipeline
YOUTUBE_API_KEY                      # YouTube Data API v3
APPLE_MUSIC_DEVELOPER_TOKEN          # Apple Music JWT
SOUNDCLOUD_CLIENT_ID                 # SoundCloud OAuth
SOUNDCLOUD_OAUTH_TOKEN               # SoundCloud OAuth
BEATPORT_API_TOKEN                   # Beatport partner feed
AUDIOMACK_CONSUMER_KEY               # Audiomack OAuth 1.0a
AUDIOMACK_CONSUMER_SECRET            # Audiomack OAuth 1.0a
```

### Firebase Parameters
```
INGEST_REGIONS=US,GB,GH,NG,ZA,DE    # Markets to fetch from
BEATPORT_API_BASE_URL=               # Optional partner endpoint
```

---

## Setup (New Machine)

```bash
git clone https://github.com/cyberzonenas93-commits/viberadar.git
cd viberadar
./scripts/setup.sh    # Decrypts .env, installs dependencies
flutter run -d macos  # Launch app
```

The setup script:
1. Decrypts `.env.encrypted` → `.env` (passphrase: `VibeRadar2026`)
2. Runs `flutter pub get`
3. Runs `cd functions && npm install`

---

## Key Metrics

| Metric | Value |
|--------|-------|
| Dart files | 48 |
| TypeScript files | 15 |
| Data sources | 9 |
| Signals per ingestion | ~5,500 |
| Tracks in Firestore | ~1,900 |
| Regions monitored | 6 (US, GB, GH, NG, ZA, DE) |
| Ingestion frequency | Every 30 minutes |
| Flutter dependencies | 24 |
| Cloud Function secrets | 9 |
| Export formats | 4 (Rekordbox, Serato, M3U, Traktor) |
