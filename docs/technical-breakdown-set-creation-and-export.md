# VibeRadar — Set Creation & DJ Export: Technical Breakdown

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Set Building & Sequencing](#set-building--sequencing)
3. [Transition Engine](#transition-engine)
4. [Hot Cue Generation](#hot-cue-generation)
5. [Export Pipeline](#export-pipeline)
6. [VirtualDJ Export](#virtualdj-export)
7. [Serato Export (Binary TLV)](#serato-export-binary-tlv)
8. [Rekordbox XML Export](#rekordbox-xml-export)
9. [Traktor NML Export](#traktor-nml-export)
10. [Generic Formats (M3U / CSV / TIDAL-Aware M3U)](#generic-formats)
11. [DJ Root Detection](#dj-root-detection)
12. [VirtualDJ Cue Writer (Phase B)](#virtualdj-cue-writer-phase-b)
13. [State Management & Provider](#state-management--provider)
14. [Models Reference](#models-reference)
15. [UI Integration](#ui-integration)
16. [File Format Reference](#file-format-reference)
17. [Safety Contracts](#safety-contracts)

---

## Architecture Overview

```
┌──────────────────────┐
│  Exports Screen (UI)  │  crate list + match panel + format picker + physical crate
│  DJ Export Dialog      │  3-step modal: setup → root → result
└────────┬─────────────┘
         │ ref.read(djExportProvider.notifier)
         ▼
┌──────────────────────┐
│  DjExportProvider     │  Riverpod NotifierProvider — state machine
│  (dj_export_provider) │  idle → ready → exporting → done | error
└────────┬─────────────┘
         │
    ┌────┴────────────────────────┐
    ▼                             ▼
┌────────────────┐    ┌────────────────────┐
│ VirtualDJ Svc  │    │  Serato Svc        │
│ .vdjfolder XML │    │  .crate binary TLV │
└────────────────┘    └────────────────────┘
         │
         ▼
┌──────────────────────┐    ┌─────────────────────┐
│  DJ Root Detection    │    │  Export Service Hub  │
│  marker validation    │    │  Rekordbox / Traktor │
│  SharedPreferences    │    │  M3U / CSV / TIDAL   │
└──────────────────────┘    │  Physical Crate      │
                            └─────────────────────┘

┌──────────────────────┐    ┌─────────────────────┐
│  Set Builder Service  │    │  Transition Engine   │
│  greedy BPM+key+energy│    │  7 modes, 11 types   │
│  sequencing           │    │  multi-dim scoring   │
└──────────────────────┘    └─────────────────────┘

┌──────────────────────┐    ┌─────────────────────┐
│  Cue Analysis Svc    │    │  VDJ Cue Writer      │
│  5 genre templates   │    │  database.xml inject  │
│  optional AI ranking │    │  backup + atomic write│
└──────────────────────┘    └─────────────────────┘
```

### File Manifest

| File | Lines | Purpose |
|------|-------|---------|
| `lib/services/set_builder_service.dart` | 167 | Greedy set sequencing with harmonic/energy/BPM scoring |
| `lib/services/transition_engine_service.dart` | 638 | Multi-dimensional pair scoring, 7 modes, bridge finding |
| `lib/services/export_service.dart` | 489 | Central export hub (Rekordbox, Traktor, M3U, CSV, TIDAL, physical crate, AI crates) |
| `lib/services/virtual_dj_export_service.dart` | 135 | VirtualDJ `.vdjfolder` XML + `order` file writer |
| `lib/services/serato_export_service.dart` | 182 | Serato binary `.crate` TLV serializer |
| `lib/services/cue_analysis_service.dart` | 403 | Deterministic + AI-ranked hot cue generation |
| `lib/services/virtual_dj_cue_writer.dart` | 251 | VirtualDJ `database.xml` Poi injection with backup |
| `lib/services/dj_root_detection_service.dart` | 144 | Auto-detect & persist VDJ/Serato roots (macOS-first) |
| `lib/services/dj_workflow_service.dart` | 198 | Legacy DJ path detection + safety prefs |
| `lib/providers/dj_export_provider.dart` | 171 | Riverpod state machine for DJ export flow |
| `lib/models/dj_export_result.dart` | 107 | Export result model with per-track resolution |
| `lib/models/transition_score.dart` | 150 | Transition score, type, mode, dimension enums |
| `lib/models/hot_cue.dart` | 249 | HotCue (10 types), CueSource (6), VDJ color map |
| `lib/models/cue_generation_result.dart` | 117 | Cue generation result with status + serialization |
| `lib/models/crate.dart` | 43 | Crate container (name, trackIds, timestamps) |
| `lib/ui/features/exports/exports_screen.dart` | ~2000 | Full exports dashboard UI |

---

## Set Building & Sequencing

**File:** `lib/services/set_builder_service.dart` (167 lines)

### Algorithm: Greedy Selection with Harmonic Compatibility

```dart
List<Track> buildSet({
  required List<Track> tracks,
  required int durationMinutes,
  required String genre,        // "All" to skip
  required String vibe,         // "All" to skip
  required double minBpm,
  required double maxBpm,
  int? yearFrom,
  int? yearTo,
  int? trackCount,
})
```

**Phase 1 — Filter:** BPM range, genre, vibe, year range
**Phase 2 — Sort:** by energy level (ascending)
**Phase 3 — Greedy select:**
  - Target count = `trackCount` or `(durationMinutes / 4)` clamped to **6–200**
  - Seed with first (lowest-energy) track
  - For each remaining slot, score all remaining tracks and pick highest

### Scoring Function

```
finalScore = (energyFit × 0.35) + (bpmFit × 0.25) + (harmonicFit × 0.20) + (trendFit × 0.20)
```

| Dimension | Weight | Formula |
|-----------|--------|---------|
| **energyFit** | 35% | `1 - abs(candidateEnergy - desiredEnergy)` where `desiredEnergy = 0.35 + (progress × 0.55)` clamped [0.2, 0.95] |
| **bpmFit** | 25% | `1 - (abs(candidateBpm - currentBpm) / 24).clamp(0, 1)` |
| **harmonicFit** | 20% | Camelot wheel distance (see table below) |
| **trendFit** | 20% | `track.trendScore` (0–1) |

### Camelot Wheel Mapping

Standard key notation and Camelot notation both accepted.

**Major keys → B side:**

| Key | Camelot | Key | Camelot | Key | Camelot | Key | Camelot |
|-----|---------|-----|---------|-----|---------|-----|---------|
| C | 8B | D | 10B | E | 12B | F | 7B |
| G | 9B | A | 11B | B | 1B | Db | 3B |
| Eb | 5B | Gb | 2B | Ab | 4B | Bb | 6B |

**Minor keys → A side:**

| Key | Camelot | Key | Camelot | Key | Camelot | Key | Camelot |
|-----|---------|-----|---------|-----|---------|-----|---------|
| Am | 8A | Bm | 10A | Cm | 5A | Dm | 7A |
| Em | 9A | Fm | 4A | Gm | 6A | Abm | 1A |
| Bbm | 3A | Dbm | 12A | Ebm | 2A | Gbm | 11A |

### Harmonic Compatibility Scores

| Relationship | Score |
|---|---|
| Same number + same mode | 1.0 |
| Same number + different mode (A↔B) | 0.92 |
| Same mode, adjacent number (wrapped) | 0.88 |
| Different mode, adjacent number | 0.72 |
| Same mode, distance 2 | 0.6 |
| Fallback | 0.4 |

---

## Transition Engine

**File:** `lib/services/transition_engine_service.dart` (638 lines)

Full multi-dimensional scoring system for evaluating how well two tracks mix.

### Genre Families (7 groups)

| Index | Family |
|-------|--------|
| 0 | house, techno, edm, tech house, deep house, progressive house, minimal techno |
| 1 | trance, progressive trance, psytrance, uplifting trance |
| 2 | hip hop, hiphop, hip-hop, r&b, rnb, trap, rap, drill |
| 3 | pop, dance pop, dance-pop, electropop, synth-pop |
| 4 | afrobeats, afro, amapiano, afro house, afro tech |
| 5 | reggae, soul, funk, reggaeton, dancehall, gospel |
| 6 | dnb, drum and bass, drum & bass, jungle, neurofunk, liquid dnb |

### BPM Scoring

| Condition | Score |
|-----------|-------|
| Half-time ratio (fromBpm/toBpm ≈ 2.0, within 3%) | 0.80 |
| Double-time ratio (fromBpm/toBpm ≈ 0.5, within 3%) | 0.78 |
| Delta ≤ 1 BPM | 1.0 |
| Delta ≤ 3 | 0.95 |
| Delta ≤ 6 | 0.88 |
| Delta ≤ 10 | 0.75 |
| Delta ≤ 15 | 0.60 |
| Delta ≤ 20 | 0.42 |
| Delta ≤ 30 | 0.25 |
| Delta > 30 | 0.10 |
| Unknown BPM (≤ 0) | 0.5 (neutral) |

### Harmonic Scoring (Camelot)

| Relationship | Score |
|---|---|
| Same key + same mode | 1.0 |
| Same number, different mode (energy boost A↔B) | 0.85 |
| Adjacent number, same mode (perfect 4th/5th) | 0.92 |
| Distance 2, same mode | 0.65 |
| Distance 3, same mode | 0.40 |
| Distance ≥ 4 or cross-mode | 0.15 |
| Parse failure (unknown key) | 0.5 |

### Genre Scoring

| Relationship | Score |
|---|---|
| Same family | 0.9 |
| Adjacent families (index ±1) | 0.7 |
| Different families | 0.4 |
| Unknown genre | 0.5 |

### Energy/Vibe Scoring

| Energy Delta (to - from) | Score |
|---|---|
| +0.00 to +0.15 (small rise) | 0.95 |
| ±0.05 (flat) | 0.90 |
| +0.15 to +0.30 (moderate rise) | 0.80 |
| > +0.30 (large rise) | 0.55 |
| -0.00 to -0.15 (small drop) | 0.75 |
| < -0.15 (large drop) | 0.40 |

### Transition Modes (7) — Weight Distributions

| Mode | BPM | Harmonic | Genre | Vibe | Intro/Outro | Use Case |
|------|-----|----------|-------|------|-------------|----------|
| **smooth** | 0.25 | **0.30** | 0.20 | 0.15 | 0.10 | Subtle, low-friction blends |
| **clubFlow** | **0.30** | 0.25 | 0.15 | 0.20 | 0.10 | Momentum / crowd continuity |
| **peakTime** | 0.20 | 0.20 | 0.15 | **0.35** | 0.10 | Tolerate hard jumps for impact |
| **openFormat** | 0.25 | 0.20 | 0.10 | **0.30** | 0.15 | Genre pivots allowed |
| **warmUp** | 0.20 | 0.25 | 0.20 | 0.25 | 0.10 | Low-energy progression |
| **closing** | 0.15 | 0.20 | 0.20 | **0.30** | 0.15 | Graceful energy landing |
| **singalong** | 0.20 | 0.25 | 0.20 | 0.20 | 0.15 | Familiarity / hooks |

### Transition Types (11)

| Type | Label | Recommended Technique |
|------|-------|----------------------|
| `smoothBlend` | Smooth Blend | Long crossfade (8–16 bars) |
| `energyLift` | Energy Lift | EQ swap on drop / filter sweep |
| `energyDrop` | Energy Drop | Slow crossfade, fade out highs |
| `bridgeTransition` | Bridge Transition | Quick blend with EQ cut |
| `hardCutCandidate` | Hard Cut | Hard cut on phrase boundary (8/16 bars) |
| `riskyTransition` | Risky | Avoid, or use spoken word/sample buffer |
| `singalongBridge` | Singalong Bridge | Overlap on familiar hook |
| `genrePivot` | Genre Pivot | Announce pivot or genre-neutral break |
| `peakTimeSlam` | Peak Time Slam | Drop cut — maximize impact on beat 1 |
| `warmUpFlow` | Warm-Up Flow | Gentle crossfade (4–8 bars) |
| `closing` | Closing | Long smooth fade (16+ bars) |

### Score Labels

| Range | Label |
|-------|-------|
| ≥ 0.80 | Excellent |
| ≥ 0.65 | Good |
| ≥ 0.50 | OK |
| < 0.50 | Risky |

### Confidence Penalties

| Condition | Penalty |
|-----------|---------|
| BPM ≤ 0 (unknown) | −0.20 |
| Key is `--` or empty | −0.15 each |
| Genre is "Open Format" or empty | −0.10 each |
| **Floor** | 0.30 |

### Public API

```dart
TransitionScore scorePair(Track from, Track to, {TransitionMode mode = smooth})
List<Track> rankNextTracks(Track current, List<Track> candidates, {mode, maxResults: 10})
List<Track> findBridgeTracks(Track from, Track to, List<Track> pool, {mode})
List<Track> buildOptimalSequence(List<Track> tracks, {mode})
```

**`findBridgeTracks`** — finds tracks B such that both A→B and B→C score ≥ 0.55, sorted by average.

**`buildOptimalSequence`** — greedy nearest-neighbor: starts with the track that has the best average score to all others, then repeatedly picks the highest-scoring next.

---

## Hot Cue Generation

**File:** `lib/services/cue_analysis_service.dart` (403 lines)

### Design Contract

> **Deterministic-first.** All cue positions are mathematically derived from BPM grid + track duration + genre template. AI never fabricates timestamps — only re-ranks and adjusts confidence ±0.15 max.

### Public API

```dart
Future<CueGenerationResult> generateCues(LibraryTrack track)
Future<Map<String, CueGenerationResult>> generateCuesForTracks(List<LibraryTrack> tracks)
```

### Pipeline

```
1. Validate metadata (min BPM 40, min duration 30s)
2. Compute bar/phrase timing: barLen = 60/bpm × 4, phrase = barLen × 4
3. Classify genre → template group
4. Generate candidates from template (up to 8 cues)
5. Filter: remove negative/out-of-bounds, deduplicate within 3s, cap at 8
6. Optional AI ranking (re-order + adjust confidence)
7. Return CueGenerationResult
```

### Genre Classification

| Family | Matches | BPM Fallback |
|--------|---------|--------------|
| houseEdm | house, techno, edm, trance, dnb, electronic | 120–155 |
| amapiano | amapiano, log drum | 105–120 (with genre hint) |
| afrobeats | afrobeats, afropop | 95–120 |
| hipHopRnb | hip-hop, rap, r&b, soul, trap | 60–95 |
| latin | latin, reggaeton, salsa, bachata | — |
| unknown | fallback | — |

### Genre Templates (timing as bar offsets from track start)

**House/EDM:**
- Intro (0 bars), Mix In (8 bars), Drop (32 bars), Breakdown (64 bars), Re-Entry (96 bars), Mix Out (duration−32 bars), Outro (duration−8 bars)

**Amapiano:**
- Intro (0), Mix In (4), Vocal In (16), Hook (32), Breakdown (64), Re-Entry (80), Mix Out (duration−24)

**Afrobeats:**
- Intro (0), Mix In (4), Vocal In (8), Hook (24), Mid Break (48), Mix Out (duration−16)

**Hip-Hop/R&B:**
- Intro (0), Mix In (4), Verse 1 (8), Hook (24), Verse 2 (40), Outro (duration−8)

**Latin:**
- Intro (0), Mix In (8), Vocal In (16), Coro/Hook (32), Mix Out (duration−16)

**Unknown (percentage-based fallback):**
- Intro (0%), Mix In (5%), Hook (30%), Breakdown (55%), Mix Out (85%)

### Cue Types (10)

| Type | Emoji | VDJ Color |
|------|-------|-----------|
| intro | `🎬` | `#00FF00` (green) |
| mixIn | `🔀` | `#00CCFF` (cyan) |
| vocalIn | `🎤` | `#FFAA00` (amber) |
| hook | `🎣` | `#FF00FF` (magenta) |
| drop | `💥` | `#FF0000` (red) |
| breakdown | `🌊` | `#FFFFFF` (white) |
| reEntry | `⚡` | `#AA00FF` (purple) |
| mixOut | `🔄` | `#4488FF` (blue) |
| outro | `🏁` | `#FF8800` (orange) |
| marker | `📍` | `#888888` (grey) |

### Confidence Scoring

| Base | Condition |
|------|-----------|
| 0.75 | BPM known (> 0) |
| 0.45 | BPM unknown |

Template-specific multipliers: intro ×0.85, vocal ×0.80, breakdown ×0.75/0.80, outro ×0.82

Weak threshold: confidence < 0.6 → `hasWeakConfidence = true`

### Cue Sources (6)

`bpmHeuristic` · `durationHeuristic` · `genreTemplate` · `metadataHint` · `aiRanking` · `userDefined`

### Storage (Phase A)

Cues are JSON-serialized in SharedPreferences:
- Per-track key: `vr_cues_<trackId>`
- Global index: `vr_cues_index`

---

## Export Pipeline

**File:** `lib/services/export_service.dart` (489 lines)

### Core Types

```dart
enum CrateType { virtualOnly, copyFiles, aliasLinks }

class ExportCrate {
  final String name;
  final List<LibraryTrack> tracks;
}

class PhysicalCrateResult {
  final String cratePath;
  final int filesCopied;
  final int filesSkipped;
  final List<String> errors;
  final List<String> missingTracks;
}
```

### Supported Export Methods

| Method | Output Format | Output Location |
|--------|--------------|-----------------|
| `exportRekordboxXml()` | `.xml` | `~/Desktop/VibeRadar Exports/` |
| `exportSeratoCsv()` | `.csv` | `~/Desktop/VibeRadar Exports/` |
| `exportM3u()` | `.m3u` | `~/Desktop/VibeRadar Exports/` |
| `exportTraktorNml()` | `.nml` | `~/Desktop/VibeRadar Exports/` |
| `exportVirtualDjXml()` | `.xml` | `~/Desktop/VibeRadar Exports/` |
| `exportTidalAwareM3u()` | `.m3u` | `~/Desktop/VibeRadar Exports/` |
| `exportMissingManifest()` | `.txt` | `~/Desktop/VibeRadar Exports/` |
| `createPhysicalCrate()` | folder | User-chosen directory |
| `exportAiCrate*()` (6 variants) | various | `~/Desktop/VibeRadar Exports/` |

### macOS Sandbox Handling

```dart
static Future<String> getExportsPath() async {
  var home = Platform.environment['HOME'] ?? '';
  // Detect sandbox container path and extract real user
  final containerMatch = RegExp(r'/Users/([^/]+)/Library/Containers/').firstMatch(home);
  if (containerMatch != null) {
    home = '/Users/${containerMatch.group(1)!}';
  }
  if (home.isEmpty) home = '/tmp';
  return p.join(home, 'Desktop', 'VibeRadar Exports');
}
```

### XML Escaping

```dart
_esc(String s) → '&' → '&amp;', '"' → '&quot;', '<' → '&lt;', '>' → '&gt;'
_csv(String s) → '"' → '""'
_safeName(String s) → replaces [^a-zA-Z0-9_-] with '_'
```

---

## VirtualDJ Export

**File:** `lib/services/virtual_dj_export_service.dart` (135 lines)

### Output Paths

```
<VDJ_ROOT>/Folders/LocalMusic/<CrateName>.vdjfolder
<VDJ_ROOT>/Folders/LocalMusic/order
```

### `.vdjfolder` XML Format

```xml
<?xml version="1.0" encoding="UTF-8"?>
<VirtualFolder>
  <Song path="/Users/dj/Music/track.mp3"
        size="8294400"
        songlength="245"
        bpm="126.00"
        key="8A"
        artist="Artist Name"
        title="Track Title"
        idx="0"/>
</VirtualFolder>
```

All attributes are conditional on data availability. Skipped tracks (empty `exportPath`) are omitted.

### `order` File

Plain text, one playlist name per line. Updated **idempotently** — existing entries are never duplicated or removed.

### TIDAL Streaming Fallback

Tracks without local files but with a TIDAL ID use:
```
netsearch://td<tidalTrackId>
```
Serato does **not** support streaming — those tracks are skipped.

---

## Serato Export (Binary TLV)

**File:** `lib/services/serato_export_service.dart` (182 lines)

### Output Path

```
<SERATO_ROOT>/Subcrates/<CrateName>.crate
```

Nested crates use `%%`: `House%%Afro.crate`

### Binary Format (Tag-Length-Value)

All strings encoded as **UTF-16 Big Endian** (no BOM).

```
┌────────────────────────────────────────┐
│ vrsn chunk (version header)            │
│  tag:  "vrsn"             (4 bytes)    │
│  len:  0x00000038         (4 bytes BE) │
│  data: "1.0/Serato ScratchLive Crate"  │
│        (UTF-16 BE = 56 bytes)          │
├────────────────────────────────────────┤
│ otrk chunk (per track)                 │
│  tag:  "otrk"             (4 bytes)    │
│  len:  <payload>          (4 bytes BE) │
│  ┌──────────────────────────────┐      │
│  │ ptrk chunk (path)           │      │
│  │  tag: "ptrk"   (4 bytes)   │      │
│  │  len: <path>   (4 bytes BE)│      │
│  │  data: "/path/to/track.mp3"│      │
│  │        (UTF-16 BE)         │      │
│  └──────────────────────────────┘      │
├────────────────────────────────────────┤
│ otrk chunk (next track) ...            │
└────────────────────────────────────────┘
```

### Byte-Level Fixture (empty crate)

```
Offset   Hex                              Meaning
00-03    76 72 73 6E                      tag: "vrsn"
04-07    00 00 00 38                      length: 56
08-09    00 31                            '1' in UTF-16 BE
10-11    00 2E                            '.' in UTF-16 BE
...      (version string continues)
Total:   64 bytes
```

### Streaming Track Policy

Serato DJ Pro has **no documented path format** for streaming-only tracks in `.crate` files. Streaming entries are intentionally NOT written. Skipped tracks are reported in `DjExportResult.skippedCount` with warnings.

---

## Rekordbox XML Export

```xml
<?xml version="1.0" encoding="UTF-8"?>
<DJ_PLAYLISTS Version="1.0.0">
  <PRODUCT Name="VibeRadar" Version="1.0.0" Company="VibeRadar"/>
  <COLLECTION Entries="3">
    <TRACK TrackID="1"
           Name="Track Title"
           Artist="Artist Name"
           Album="Album"
           Genre="House"
           TotalTime="245"
           AverageBpm="126.00"
           Tonality="8A"
           Location="file:///Users/dj/Music/track.mp3"
           Size="8294400"/>
  </COLLECTION>
  <PLAYLISTS>
    <NODE Type="0" Name="ROOT" Count="1">
      <NODE Name="My Set" Type="1" KeyType="0" Entries="3">
        <TRACK Key="1"/>
        <TRACK Key="2"/>
        <TRACK Key="3"/>
      </NODE>
    </NODE>
  </PLAYLISTS>
</DJ_PLAYLISTS>
```

- `Location` uses `Uri.file()` for proper `file://` encoding
- `Tonality` carries the key in Camelot notation
- `AverageBpm` has 2-decimal precision
- Playlist TRACK Key references match COLLECTION TrackID

---

## Traktor NML Export

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<NML VERSION="19">
  <COLLECTION ENTRIES="3">
    <ENTRY TITLE="Track Title" ARTIST="Artist Name">
      <LOCATION DIR="/Users/dj/Music/" FILE="track.mp3" VOLUME="/" VOLUMEID=""/>
      <INFO GENRE="House" KEY="8A"/>
      <TEMPO BPM="126.000000" BPM_QUALITY="100"/>
    </ENTRY>
  </COLLECTION>
  <PLAYLISTS>
    <NODE TYPE="FOLDER" NAME="$ROOT">
      <SUBNODES COUNT="1">
        <NODE TYPE="PLAYLIST" NAME="My Set">
          <PLAYLIST ENTRIES="3" TYPE="LIST">
            <ENTRY><PRIMARYKEY TYPE="TRACK" KEY="/Users/dj/Music/track.mp3"/></ENTRY>
          </PLAYLIST>
        </NODE>
      </SUBNODES>
    </NODE>
  </PLAYLISTS>
</NML>
```

- `LOCATION` splits path into `DIR` (dirname + trailing `/`) and `FILE` (basename)
- `BPM` has 6-decimal precision
- PLAYLIST references use full file path as PRIMARYKEY

---

## Generic Formats

### Standard M3U

```
#EXTM3U
#PLAYLIST:My Set
#EXTINF:245,Artist Name - Track Title
/Users/dj/Music/track.mp3
```

### TIDAL-Aware M3U

```
#EXTM3U
#PLAYLIST:My Set
#EXTGRP:VibeRadar Export (TIDAL-aware)
#EXTINF:245,Artist Name - Track Title
#EXTVLCOPT:tidal-search=Artist%20Name%20Track%20Title
/Users/dj/Music/track.mp3

# ── Missing tracks (TIDAL search hints) ──
#EXTINF:-1,Missing Artist - Missing Track
#EXTVLCOPT:tidal-search=Missing%20Artist%20Missing%20Track
# NOT_IN_LOCAL_LIBRARY
```

### Serato CSV

```csv
name,artist,album,genre,bpm,key,duration,year,bitrate,filepath
"Track Title","Artist","Album","House","126","8A","4:05","2024","320","/path/to/track.mp3"
```

Double quotes in values are doubled per CSV convention.

---

## DJ Root Detection

**File:** `lib/services/dj_root_detection_service.dart` (144 lines)

### Default Candidate Paths (macOS)

| Software | Path |
|----------|------|
| VirtualDJ | `~/Library/Application Support/VirtualDJ` |
| Serato | `~/Music/_Serato_` |

### Validation Markers

| Software | Required Count | Markers |
|----------|---------------|---------|
| **VirtualDJ** | ≥ 2 | `database.xml`, `settings.xml`, `Folders/`, `Playlists/`, `History/` |
| **Serato** | ≥ 2 | `Subcrates/`, `database V2`, `History/`, `Metadata/` |

### Resolution Priority

```
1. Load persisted root from SharedPreferences → validate → use if valid
2. Auto-detect from candidate paths → use first valid
3. Return null (UI prompts user to pick manually)
```

### Persistence Keys

```dart
'dj_root_virtualdj'  // SharedPreferences key for VDJ root
'dj_root_serato'     // SharedPreferences key for Serato root
```

---

## VirtualDJ Cue Writer (Phase B)

**File:** `lib/services/virtual_dj_cue_writer.dart` (251 lines)

### Safety Contract

1. **Always** creates timestamped backup before writing (`database.xml.2026-03-28T04-30-00.bak`)
2. **Aborts** if backup creation fails
3. **Only** modifies the target track's Poi elements
4. Existing non-cue Poi elements and other Song entries are **preserved**
5. **Idempotent** — same cues produce identical output

### VirtualDJ Poi Element

```xml
<Song FilePath="/path/to/track.mp3">
  <Poi Pos="12340" Type="cue" Num="0" Name="Intro" Color="#00FF00"/>
  <Poi Pos="34560" Type="cue" Num="1" Name="Drop"  Color="#FF0000"/>
</Song>
```

| Attribute | Description |
|-----------|-------------|
| `Pos` | Milliseconds from track start (integer) |
| `Type` | Always `"cue"` for hot cues |
| `Num` | 0–7 (VirtualDJ's 8-pad limit) |
| `Name` | Label displayed on the pad |
| `Color` | Hex color for the pad LED |

### Write Flow

```
writeCues(vdjRoot, trackFilePath, cues)
  1. Check database.xml exists → databaseNotFound
  2. Create timestamped backup → backupFailed if fails
  3. Parse XML → parseError
  4. Find Song by FilePath (normalised comparison + basename fallback)
  5. Remove existing Type="cue" Poi elements
  6. Insert new Poi elements (skip cueIndex outside 0–7)
  7. Write XML back → writeError
  8. Return VdjCueWriteResult(success, backupPath, cuesWritten)
```

### Result Status Enum

`success` · `backupFailed` · `databaseNotFound` · `songNotFound` · `parseError` · `writeError`

---

## State Management & Provider

**File:** `lib/providers/dj_export_provider.dart` (171 lines)

### State

```dart
class DjExportState {
  final String? vdjRoot;       // Confirmed VirtualDJ path
  final String? seratoRoot;    // Confirmed Serato path
  final bool isExporting;
  final DjExportResult? lastResult;
  final String? error;

  bool get hasVdjRoot
  bool get hasSeratoRoot
}
```

### Service Providers

```dart
final djRootDetectionServiceProvider = Provider((_) => DjRootDetectionService());
final virtualDjExportServiceProvider = Provider((_) => VirtualDjExportService());
final seratoExportServiceProvider = Provider((_) => SeratoExportService());
final djExportProvider = NotifierProvider<DjExportNotifier, DjExportState>(...);
```

### Notifier Methods

```dart
// Root management
Future<bool> setVirtualDjRoot(String path)     // validates → persists → updates state
Future<bool> setSeratoRoot(String path)
Future<void> forceSetVirtualDjRoot(String path) // skips validation (manual override)
Future<void> forceSetSeratoRoot(String path)

// Exports
Future<DjExportResult?> exportToVirtualDj({crateName, tracks})
Future<DjExportResult?> exportToSerato({crateName, tracks, parentCrateName?})

// Lifecycle
void clearResult()
```

### Init Flow

On `build()`, the notifier auto-resolves both roots from persisted preferences or auto-detection.

---

## Models Reference

### DjExportResult

```dart
class DjExportResult {
  final DjExportTarget target;     // virtualDj | serato
  final String crateName;
  final String rootPath;
  final String outputPath;
  final List<DjTrackResolution> tracks;
  final DateTime exportedAt;
  final List<String> warnings;

  int get totalTracks / localCount / tidalCount / skippedCount
  String get summary   // "12 local, 2 TIDAL, 1 skipped"
}
```

### DjTrackResolution

```dart
class DjTrackResolution {
  final String title, artist;
  final DjTrackStatus status;     // local | tidal | skipped
  final String? localFilePath;
  final String? tidalTrackId;
  final String? skipReason;
  // + metadata: fileSizeBytes, durationSeconds, bpm, key

  String get exportPath  // local path, "netsearch://td<id>", or ""
}
```

### TransitionScore

```dart
class TransitionScore {
  final String fromTrackId, toTrackId;
  final double overallScore;       // 0.0–1.0
  final double confidence;
  final TransitionType type;
  final List<String> reasons;
  final List<String> warnings;
  final Map<TransitionDimension, double> dimensionScores;
  final String? recommendedTechnique;
  final bool isBridgeCandidate;

  String get scoreLabel  // "Excellent" / "Good" / "OK" / "Risky"
  Map<String, dynamic> toJson()
  factory fromJson(Map<String, dynamic>)
}
```

---

## UI Integration

### Exports Screen (`lib/ui/features/exports/exports_screen.dart`)

Three-panel layout:
- **Left** (240px): Crate list with create/select
- **Center**: Format selection, track matching panel, export actions
- **Right**: Physical crate creation (type picker, destination, progress)

DJ exports are triggered via a dialog:

```dart
// Inside exports_screen.dart
final notifier = ref.read(djExportProvider.notifier);
if (_isVdj) {
  result = await notifier.exportToVirtualDj(crateName: name, tracks: tracks);
} else {
  result = await notifier.exportToSerato(crateName: name, tracks: tracks, parentCrateName: parent);
}
```

The dialog shows:
- Root path (auto-detected or manual pick via FilePicker)
- Validation status
- Export button (disabled if no root)
- Result: stat grid (total / local / TIDAL / skipped) + output path

### Navigation Wiring

```
vibe_shell.dart → AppSection.exports → ExportsScreen()
```

---

## File Format Reference

| Target | Extension | Encoding | Structure | Streaming |
|--------|-----------|----------|-----------|-----------|
| Rekordbox | `.xml` | UTF-8 XML | `DJ_PLAYLISTS` → `COLLECTION` + `PLAYLISTS` | No |
| Serato | `.crate` | Binary (UTF-16 BE TLV) | `vrsn` + `otrk/ptrk` chunks | No |
| VirtualDJ | `.vdjfolder` | UTF-8 XML | `VirtualFolder` → `Song` elements | Yes (`netsearch://`) |
| Traktor | `.nml` | UTF-8 XML | `NML` → `COLLECTION` + `PLAYLISTS` | No |
| M3U | `.m3u` | UTF-8 text | `#EXTM3U` + `#EXTINF` lines | TIDAL hints via `EXTVLCOPT` |
| CSV | `.csv` | UTF-8 text | Header + comma-delimited rows | No |

---

## Safety Contracts

### VirtualDJ Cue Writer
- Backup before every write (timestamped `.bak`)
- Abort on backup failure
- Only modify target track's Poi elements
- Idempotent writes
- Never touches audio files

### Serato Export
- Streaming tracks skipped (format unsupported)
- UTF-16 BE encoding verified against community fixtures
- Filename sanitization for filesystem safety
- Skipped tracks reported with reasons

### Root Detection
- Marker-based validation (≥2 markers required)
- Persisted roots re-validated on load
- Manual override available (forceSet)
- Never writes to DJ software folders without explicit export

### Export Service
- macOS sandbox detection for correct home path
- Missing source files reported, not silently dropped
- XML escaping on all user-supplied values
- Action logging for every export

---

## Data Flow Summary

```
User selects crate in Exports Screen
        │
        ▼
Match tracks → LocalMatchService.matchSet(vibeTracks, library)
        │
        ▼
┌─────────────────────┐
│  Choose format:      │
│  VDJ / Serato /      │
│  Rekordbox / etc.    │
└────────┬────────────┘
         │
    ┌────┴────────────────┬──────────┐
    ▼                     ▼          ▼
  DJ Export Dialog   Export Service  Physical Crate
  (provider-based)   (file-based)   (copy/link)
    │                     │          │
    ▼                     ▼          ▼
 VDJ Root + VDJ Svc    ~/Desktop/   User dir/
 Serato Root + Serato   VibeRadar    crateName/
   .vdjfolder/.crate    Exports/     files...

Cue Generation (separate flow):
  Track → CueAnalysisService → CueGenerationResult (up to 8 cues)
                                      │
                                      ▼
                               VDJ Cue Writer → database.xml Poi injection
```
