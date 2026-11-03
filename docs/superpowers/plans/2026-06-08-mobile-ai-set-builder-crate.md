# Mobile AI Set Builder → Real Playable Crates — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the mobile AI Set Builder turn its suggested songs into real, playable crate entries (Spotify/Apple/YouTube links) that can be saved as a new setlist or appended to an existing one, syncing to desktop.

**Architecture:** Replace `Crate.trackIds: List<String>` with `Crate.tracks: List<CrateTrack>` (id-reference *or* self-contained rich entry), backward-compatible via a mirrored `track_ids` field. A shared `SetResolutionService` resolves AI songs (local-library match → Spotify → Apple → YouTube-as-fallback). Mobile UI gains "Resolve & add" + an "Add to crate…" picker. Also tune the previously-deployed decay sweep for cost.

**Tech Stack:** Flutter/Dart, Riverpod, cloud_firestore, cloud_functions; Firebase Functions (TypeScript) for the decay sweep.

**Note:** Working in the existing `main` checkout (not a worktree) because the repo already has extensive uncommitted work. Run `flutter analyze` + `flutter test` after each Dart task; `npx tsc --noEmit` + `npm test` (in `functions/`) for the backend task.

---

## File structure

**New:**
- `lib/models/crate_track.dart` — the `CrateTrack` value type (one responsibility: a crate entry + serialization).
- `lib/services/set_resolution_service.dart` — resolve draft songs → `CrateTrack`s.
- `test/models/crate_track_test.dart`, `test/models/crate_test.dart`, `test/providers/setlist_actions_test.dart`, `test/services/set_resolution_service_test.dart`.

**Modified:**
- `lib/models/crate.dart` — `tracks` field + compat getter + serialization.
- `lib/providers/setlist_provider.dart` — `addTracks`, `addTrack` wraps a reference entry.
- `lib/ui/mobile/setlist_editor.dart` — render rich entries, reorder/remove on `tracks`, open-link.
- `lib/ui/mobile/setlists_tab.dart` — track count uses `crate.tracks.length`.
- `lib/ui/mobile/ai_tab.dart` — resolve-on-tap + "Add to crate…" sheet.
- `lib/ui/features/ai_copilot/ai_copilot_screen.dart` — call shared resolver.
- `functions/src/lib/recency.ts`, `functions/src/decayTrending.ts`, `functions/test/recency.test.ts` — cost tuning.

---

## Task 1: `CrateTrack` model

**Files:**
- Create: `lib/models/crate_track.dart`
- Test: `test/models/crate_track_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/models/crate_track_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/crate_track.dart';

void main() {
  test('round-trips through toMap/fromMap', () {
    const t = CrateTrack(
      trackId: 'abc123', title: 'Essence', artist: 'Wizkid',
      bpm: 104, key: '8A', spotifyUrl: 'https://sp/1', artworkUrl: 'https://art/1',
    );
    final back = CrateTrack.fromMap(t.toMap());
    expect(back.trackId, 'abc123');
    expect(back.title, 'Essence');
    expect(back.artist, 'Wizkid');
    expect(back.bpm, 104);
    expect(back.key, '8A');
    expect(back.spotifyUrl, 'https://sp/1');
    expect(back.artworkUrl, 'https://art/1');
  });

  test('bestUrl prefers spotify, then apple, then youtube', () {
    expect(const CrateTrack(title: 't', artist: 'a', appleUrl: 'ap', youtubeUrl: 'yt').bestUrl, 'ap');
    expect(const CrateTrack(title: 't', artist: 'a', youtubeUrl: 'yt').bestUrl, 'yt');
    expect(const CrateTrack(title: 't', artist: 'a').hasUrl, false);
  });

  test('stableKey uses trackId when present, else artist|title lowercased', () {
    expect(const CrateTrack(trackId: 'id1', title: 'T', artist: 'A').stableKey, 'id1');
    expect(const CrateTrack(title: 'Essence', artist: 'Wizkid').stableKey, 'wizkid|essence');
  });

  test('reference factory builds an id-only entry', () {
    final r = CrateTrack.reference('xyz');
    expect(r.trackId, 'xyz');
    expect(r.title, '');
    expect(r.artist, '');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/crate_track_test.dart`
Expected: FAIL — `crate_track.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/models/crate_track.dart
/// One entry in a [Crate]. Either a reference to a real `tracks/{id}` document
/// (when [trackId] is set and title/artist are empty) or a self-contained rich
/// entry carrying its own metadata + playable platform links (e.g. an
/// AI-resolved song that may not exist in the trends library).
class CrateTrack {
  const CrateTrack({
    this.trackId,
    required this.title,
    required this.artist,
    this.bpm = 0,
    this.key = '',
    this.spotifyUrl,
    this.appleUrl,
    this.youtubeUrl,
    this.artworkUrl,
  });

  /// An id-only reference entry (resolved against the live tracks stream).
  factory CrateTrack.reference(String trackId) =>
      CrateTrack(trackId: trackId, title: '', artist: '');

  final String? trackId;
  final String title;
  final String artist;
  final int bpm;
  final String key;
  final String? spotifyUrl;
  final String? appleUrl;
  final String? youtubeUrl;
  final String? artworkUrl;

  String get bestUrl => spotifyUrl ?? appleUrl ?? youtubeUrl ?? '';
  bool get hasUrl => bestUrl.isNotEmpty;

  /// True for an id-only entry that must be resolved from the tracks stream.
  bool get isReference => (title.isEmpty && artist.isEmpty) && trackId != null;

  /// Stable identity for de-duplication and the legacy `track_ids` mirror.
  String get stableKey =>
      trackId ?? '${artist.toLowerCase()}|${title.toLowerCase()}';

  Map<String, dynamic> toMap() => {
        if (trackId != null) 'track_id': trackId,
        'title': title,
        'artist': artist,
        'bpm': bpm,
        'key': key,
        if (spotifyUrl != null) 'spotify_url': spotifyUrl,
        if (appleUrl != null) 'apple_url': appleUrl,
        if (youtubeUrl != null) 'youtube_url': youtubeUrl,
        if (artworkUrl != null) 'artwork_url': artworkUrl,
      };

  factory CrateTrack.fromMap(Map<String, dynamic> map) => CrateTrack(
        trackId: map['track_id'] as String?,
        title: map['title'] as String? ?? '',
        artist: map['artist'] as String? ?? '',
        bpm: (map['bpm'] as num?)?.toInt() ?? 0,
        key: map['key'] as String? ?? '',
        spotifyUrl: map['spotify_url'] as String?,
        appleUrl: map['apple_url'] as String?,
        youtubeUrl: map['youtube_url'] as String?,
        artworkUrl: map['artwork_url'] as String?,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/crate_track_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/models/crate_track.dart test/models/crate_track_test.dart
git commit -m "feat(crate): add CrateTrack entry model"
```

---

## Task 2: Migrate `Crate` to `tracks` (backward compatible)

**Files:**
- Modify: `lib/models/crate.dart`
- Test: `test/models/crate_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/models/crate_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/crate.dart';
import 'package:viberadar/models/crate_track.dart';

Crate _crate(List<CrateTrack> tracks) => Crate(
      id: 'c1', name: 'Set', context: 'AI set', tracks: tracks,
      createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026),
    );

void main() {
  test('legacy track_ids map to reference entries', () {
    final c = Crate.fromMap({
      'id': 'c1', 'name': 'Old', 'context': 'x',
      'track_ids': ['a', 'b'],
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
    });
    expect(c.tracks.length, 2);
    expect(c.tracks.first.trackId, 'a');
    expect(c.tracks.first.isReference, true);
  });

  test('new rich tracks array round-trips', () {
    final c = _crate([
      const CrateTrack(title: 'Essence', artist: 'Wizkid', spotifyUrl: 'sp'),
    ]);
    final back = Crate.fromMap(c.toMap());
    expect(back.tracks.single.title, 'Essence');
    expect(back.tracks.single.spotifyUrl, 'sp');
  });

  test('toMap mirrors track_ids for legacy/desktop readers', () {
    final map = _crate([
      const CrateTrack(trackId: 'realId', title: 'T', artist: 'A'),
      const CrateTrack(title: 'Essence', artist: 'Wizkid'),
    ]).toMap();
    expect(map['track_ids'], ['realId', 'wizkid|essence']);
  });

  test('trackIds getter stays available for read-only consumers', () {
    final c = _crate([CrateTrack.reference('z')]);
    expect(c.trackIds, ['z']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/crate_test.dart`
Expected: FAIL — `Crate` has no `tracks` parameter.

- [ ] **Step 3: Rewrite `lib/models/crate.dart`**

```dart
import 'crate_track.dart';

class Crate {
  const Crate({
    required this.id,
    required this.name,
    required this.context,
    required this.tracks,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String context;
  final List<CrateTrack> tracks;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Legacy read-only view used by exporters/desktop that still think in ids.
  List<String> get trackIds => tracks.map((t) => t.stableKey).toList();

  Crate copyWith({
    String? name,
    String? context,
    List<CrateTrack>? tracks,
    DateTime? updatedAt,
  }) {
    return Crate(
      id: id,
      name: name ?? this.name,
      context: context ?? this.context,
      tracks: tracks ?? this.tracks,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'context': context,
      'tracks': tracks.map((t) => t.toMap()).toList(),
      // Mirror for any unmodified legacy/desktop reader.
      'track_ids': tracks.map((t) => t.stableKey).toList(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Crate.fromMap(Map<String, dynamic> map) {
    final rich = map['tracks'] as List?;
    final List<CrateTrack> tracks;
    if (rich != null && rich.isNotEmpty) {
      tracks = rich
          .map((e) => CrateTrack.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } else {
      tracks = List<String>.from(map['track_ids'] as List? ?? const [])
          .map(CrateTrack.reference)
          .toList();
    }
    return Crate(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Untitled crate',
      context: map['context'] as String? ?? 'Open format',
      tracks: tracks,
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/crate_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Fix compile breaks in `trackIds` *writers* only**

`crate.trackIds` is now read-only. Build to find writers:
Run: `flutter analyze` — Expected: errors only where code *constructs* `Crate(trackIds:)` or assigns. Fix each by switching to `tracks:` with `CrateTrack`s. Known sites updated in later tasks (`ai_tab.dart` Task 6, `setlist_provider.dart` Task 3, `setlist_editor.dart` Task 5). For any *other* writer found, wrap ids: `tracks: ids.map(CrateTrack.reference).toList()`.

- [ ] **Step 6: Commit**

```bash
git add lib/models/crate.dart test/models/crate_test.dart
git commit -m "feat(crate): store rich CrateTrack entries, keep track_ids mirror"
```

---

## Task 3: `SetlistActions.addTracks` + reference `addTrack`

**Files:**
- Modify: `lib/providers/setlist_provider.dart`
- Test: `test/providers/setlist_actions_test.dart`

- [ ] **Step 1: Write the failing test** (pure dedupe/merge helper, no Firestore)

```dart
// test/providers/setlist_actions_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/crate.dart';
import 'package:viberadar/models/crate_track.dart';
import 'package:viberadar/providers/setlist_provider.dart';

void main() {
  test('mergeTracks appends new entries and dedupes by stableKey', () {
    final existing = [
      const CrateTrack(trackId: 'a', title: '', artist: ''),
      const CrateTrack(title: 'Essence', artist: 'Wizkid'),
    ];
    final incoming = [
      const CrateTrack(title: 'Essence', artist: 'Wizkid'), // dup by key
      const CrateTrack(title: 'Calm Down', artist: 'Rema'), // new
    ];
    final merged = mergeTracks(existing, incoming);
    expect(merged.length, 3);
    expect(merged.last.title, 'Calm Down');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/setlist_actions_test.dart`
Expected: FAIL — `mergeTracks` undefined.

- [ ] **Step 3: Implement** — add the pure helper + actions to `lib/providers/setlist_provider.dart`

Add the import `import 'crate_track.dart'... ` (it comes via `crate.dart`; add `import '../models/crate_track.dart';`). Add the top-level helper and replace `createWithTrack`/`addTrack`:

```dart
/// Appends [incoming] to [existing], skipping entries whose stableKey already
/// appears. Pure — exposed for unit testing.
List<CrateTrack> mergeTracks(
  List<CrateTrack> existing,
  List<CrateTrack> incoming,
) {
  final seen = existing.map((t) => t.stableKey).toSet();
  final out = [...existing];
  for (final t in incoming) {
    if (seen.add(t.stableKey)) out.add(t);
  }
  return out;
}
```

Inside `SetlistActions`, replace the old `createWithTrack`/`addTrack` with:

```dart
  Future<void> createWithTrack(String name, String trackId) {
    final now = DateTime.now();
    return save(Crate(
      id: const Uuid().v4(),
      name: name,
      context: 'Open format',
      tracks: [CrateTrack.reference(trackId)],
      createdAt: now,
      updatedAt: now,
    ));
  }

  /// Appends a library track (by id, resolved from the tracks stream).
  Future<void> addTrack(Crate setlist, String trackId) =>
      addTracks(setlist, [CrateTrack.reference(trackId)]);

  /// Appends rich entries (e.g. AI-resolved songs), de-duplicated.
  Future<void> addTracks(Crate setlist, List<CrateTrack> tracks) {
    final merged = mergeTracks(setlist.tracks, tracks);
    if (merged.length == setlist.tracks.length) return Future.value();
    return save(setlist.copyWith(tracks: merged));
  }
```

Also update `create(String name)` to use `tracks: const []`.

- [ ] **Step 4: Run test + analyze**

Run: `flutter test test/providers/setlist_actions_test.dart` — Expected: PASS.
Run: `flutter analyze lib/providers/setlist_provider.dart` — Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/setlist_provider.dart test/providers/setlist_actions_test.dart
git commit -m "feat(setlist): addTracks with dedupe; addTrack wraps a reference entry"
```

---

## Task 4: `SetResolutionService`

**Files:**
- Create: `lib/services/set_resolution_service.dart`
- Test: `test/services/set_resolution_service_test.dart`

Resolver order per song: **local library → Spotify → Apple → YouTube (only if all miss)**. The service takes injected platform services so tests use fakes. Reuse the public service methods confirmed in the codebase: `SpotifyArtistService.searchTracks(q, {limit})` → `SpotifyTrackInfo{spotifyUrl, albumArt}`; `AppleMusicArtistService.searchSongs(q, {limit})` → `AppleMusicTrack{appleUrl, artworkUrl}`; `YoutubeSearchService.searchMusic(q, {limit})` → `YoutubeVideoResult{youtubeUrl, thumbnailUrl}`.

- [ ] **Step 1: Write the failing test**

```dart
// test/services/set_resolution_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/track.dart';
import 'package:viberadar/services/set_resolution_service.dart';

class _Calls { int spotify = 0, apple = 0, youtube = 0; }

void main() {
  Track lib(String id, String title, String artist) => Track(
        id: id, title: title, artist: artist, artworkUrl: 'art',
        bpm: 100, keySignature: '8A', genre: 'Afrobeats', vibe: 'Warm',
        trendScore: 0.5, regionScores: const {}, platformLinks: const {'spotify': 'sp-lib'},
        createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026),
        energyLevel: 0.5, trendHistory: const [], sources: const [],
      );

  test('local library match wins and makes no platform calls', () async {
    final calls = _Calls();
    final svc = SetResolutionService.test(
      searchSpotify: (q) async { calls.spotify++; return null; },
      searchApple: (q) async { calls.apple++; return null; },
      searchYoutube: (q) async { calls.youtube++; return null; },
    );
    final out = await svc.resolve(
      [(title: 'Essence', artist: 'Wizkid', bpm: 0, key: '')],
      library: [lib('realId', 'Essence', 'Wizkid')],
    );
    expect(out.single.trackId, 'realId');
    expect(out.single.spotifyUrl, 'sp-lib');
    expect(calls.spotify, 0);
    expect(calls.apple, 0);
    expect(calls.youtube, 0);
  });

  test('youtube only called when spotify and apple miss', () async {
    final calls = _Calls();
    final svc = SetResolutionService.test(
      searchSpotify: (q) async { calls.spotify++; return null; },
      searchApple: (q) async { calls.apple++; return null; },
      searchYoutube: (q) async { calls.youtube++; return (url: 'yt', art: 'yart'); },
    );
    final out = await svc.resolve(
      [(title: 'Deep Cut', artist: 'Nobody', bpm: 0, key: '')],
      library: const [],
    );
    expect(out.single.youtubeUrl, 'yt');
    expect(calls.spotify, 1);
    expect(calls.apple, 1);
    expect(calls.youtube, 1);
  });

  test('spotify hit short-circuits before apple/youtube', () async {
    final calls = _Calls();
    final svc = SetResolutionService.test(
      searchSpotify: (q) async { calls.spotify++; return (url: 'sp', art: 'a'); },
      searchApple: (q) async { calls.apple++; return null; },
      searchYoutube: (q) async { calls.youtube++; return null; },
    );
    final out = await svc.resolve(
      [(title: 'Hit', artist: 'Star', bpm: 0, key: '')], library: const []);
    expect(out.single.spotifyUrl, 'sp');
    expect(calls.apple, 0);
    expect(calls.youtube, 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/set_resolution_service_test.dart`
Expected: FAIL — service does not exist.

- [ ] **Step 3: Implement `lib/services/set_resolution_service.dart`**

```dart
import '../models/crate_track.dart';
import '../models/track.dart';
import 'apple_music_artist_service.dart';
import 'spotify_artist_service.dart';
import 'youtube_search_service.dart';

typedef Draft = ({String title, String artist, int bpm, String key});
typedef _UrlArt = ({String url, String art})?;
typedef _Search = Future<_UrlArt> Function(String query);

String _canon(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// Resolves AI/draft songs into [CrateTrack]s with playable links.
/// Order per song: local library → Spotify → Apple → YouTube (fallback only).
class SetResolutionService {
  SetResolutionService({
    SpotifyArtistService? spotify,
    AppleMusicArtistService? apple,
    YoutubeSearchService? youtube,
  })  : _searchSpotify = _spotifyAdapter(spotify ?? SpotifyArtistService()),
        _searchApple = _appleAdapter(apple ?? AppleMusicArtistService()),
        _searchYoutube = _youtubeAdapter(youtube ?? YoutubeSearchService());

  /// Test seam: inject pure search functions.
  SetResolutionService.test({
    required _Search searchSpotify,
    required _Search searchApple,
    required _Search searchYoutube,
  })  : _searchSpotify = searchSpotify,
        _searchApple = searchApple,
        _searchYoutube = searchYoutube;

  final _Search _searchSpotify;
  final _Search _searchApple;
  final _Search _searchYoutube;

  Future<List<CrateTrack>> resolve(
    List<Draft> drafts, {
    List<Track> library = const [],
    void Function(int found, int total)? onProgress,
  }) async {
    final index = <String, Track>{
      for (final t in library) '${_canon(t.artist)}|${_canon(t.title)}': t,
    };
    final out = <CrateTrack>[];
    var found = 0;
    for (var i = 0; i < drafts.length; i++) {
      final d = drafts[i];
      final local = index['${_canon(d.artist)}|${_canon(d.title)}'];
      CrateTrack entry;
      if (local != null) {
        entry = CrateTrack(
          trackId: local.id, title: d.title, artist: d.artist,
          bpm: d.bpm == 0 ? local.bpm : d.bpm, key: d.key.isEmpty ? local.keySignature : d.key,
          spotifyUrl: local.platformLinks['spotify'],
          appleUrl: local.platformLinks['apple'],
          youtubeUrl: local.platformLinks['youtube'],
          artworkUrl: local.artworkUrl.isEmpty ? null : local.artworkUrl,
        );
      } else {
        final q = '${d.artist} ${d.title}';
        final sp = await _searchSpotify(q);
        final ap = sp == null ? await _searchApple(q) : null;
        final yt = (sp == null && ap == null) ? await _searchYoutube(q) : null;
        entry = CrateTrack(
          title: d.title, artist: d.artist, bpm: d.bpm, key: d.key,
          spotifyUrl: sp?.url, appleUrl: ap?.url, youtubeUrl: yt?.url,
          artworkUrl: sp?.art ?? ap?.art ?? yt?.art,
        );
      }
      if (entry.hasUrl || entry.trackId != null) found++;
      out.add(entry);
      onProgress?.call(found, drafts.length);
    }
    return out;
  }

  static _Search _spotifyAdapter(SpotifyArtistService s) => (q) async {
        final r = await s.searchTracks(q, limit: 1).catchError((_) => <SpotifyTrackInfo>[]);
        if (r.isEmpty || r.first.spotifyUrl.isEmpty) return null;
        return (url: r.first.spotifyUrl, art: r.first.albumArt ?? '');
      };

  static _Search _appleAdapter(AppleMusicArtistService s) => (q) async {
        final r = await s.searchSongs(q, limit: 1).catchError((_) => <AppleMusicTrack>[]);
        if (r.isEmpty || (r.first.appleUrl ?? '').isEmpty) return null;
        return (url: r.first.appleUrl!, art: r.first.artworkUrl ?? '');
      };

  static _Search _youtubeAdapter(YoutubeSearchService s) => (q) async {
        final r = await s.searchMusic(q, limit: 1).catchError((_) => <YoutubeVideoResult>[]);
        if (r.isEmpty || r.first.youtubeUrl.isEmpty) return null;
        return (url: r.first.youtubeUrl, art: r.first.thumbnailUrl ?? '');
      };
}
```

NOTE for implementer: verify `YoutubeVideoResult` exposes `youtubeUrl` and `thumbnailUrl` (grep `lib/services/youtube_search_service.dart`); if names differ, adjust the adapter only. The `(url:..., art:...)` empty-art string maps to a non-null artworkUrl; if you prefer null when empty, coalesce in the adapter.

- [ ] **Step 4: Run test + analyze**

Run: `flutter test test/services/set_resolution_service_test.dart` — Expected: PASS (3 tests).
Run: `flutter analyze lib/services/set_resolution_service.dart` — Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add lib/services/set_resolution_service.dart test/services/set_resolution_service_test.dart
git commit -m "feat(resolve): shared SetResolutionService (local→spotify→apple→youtube-fallback)"
```

---

## Task 5: Setlist editor + tab render rich entries

**Files:**
- Modify: `lib/ui/mobile/setlist_editor.dart`
- Modify: `lib/ui/mobile/setlists_tab.dart`

- [ ] **Step 1: Update the reorder helper test name + logic**

In `setlist_editor.dart`, rename `reorderTrackIds` → `reorderTracks` and change its type to `List<CrateTrack>`:

```dart
List<CrateTrack> reorderTracks(List<CrateTrack> tracks, int oldIndex, int newIndex) {
  final list = List<CrateTrack>.from(tracks);
  final adjustedNew = newIndex > oldIndex ? newIndex - 1 : newIndex;
  final item = list.removeAt(oldIndex);
  list.insert(adjustedNew, item);
  return list;
}
```

If `test/mobile/` has a `reorderTrackIds` test, update it to `reorderTracks` with `CrateTrack.reference('a')` entries. (Grep: `git grep -n reorderTrackIds test/`.)

- [ ] **Step 2: Convert editor state from ids to tracks**

Replace `late List<String> _trackIds;` with `late List<CrateTrack> _tracks;`. In `initState`: `_tracks = List<CrateTrack>.from(widget.crate.tracks);`. Update `_current`, `_onReorder`, `_removeTrack`, `_commitRename`, `_buildList` to use `_tracks` and `crate.copyWith(tracks: _tracks, ...)`. Empty check: `_tracks.isEmpty`.

- [ ] **Step 3: Render rich vs reference entries in `_TrackRow`**

`_buildList`:
```dart
itemBuilder: (context, index) {
  final entry = _tracks[index];
  final resolved = entry.isReference ? trackMap[entry.trackId] : null;
  return _TrackRow(
    key: ValueKey(entry.stableKey),
    index: index,
    entry: entry,
    resolved: resolved, // Track? from the stream for reference entries
    onDelete: () => _removeTrack(index),
  );
},
```

`_TrackRow` (replace fields/build): compute display from the rich entry, falling back to the resolved library Track for reference entries:
```dart
final title = entry.title.isNotEmpty ? entry.title : (resolved?.title ?? 'Unknown track');
final artist = entry.artist.isNotEmpty ? entry.artist : (resolved?.artist ?? '');
final bpm = entry.bpm != 0 ? entry.bpm : (resolved?.bpm ?? 0);
final subtitle = [if (artist.isNotEmpty) artist, if (bpm > 0) '$bpm BPM'].join('  ·  ');
final url = entry.hasUrl ? entry.bestUrl : (resolved?.platformLinks.values.firstOrNull ?? '');
```
Add a trailing open-link `IconButton` (icon `Icons.open_in_new`, only when `url.isNotEmpty`) that calls `launchUrl` (package `url_launcher` is already a dep — confirm via `git grep launchUrl lib/`) before the existing delete button.

- [ ] **Step 4: `setlists_tab.dart` track count**

Change `crate.trackIds.length` → `crate.tracks.length` (line ~129).

- [ ] **Step 5: Verify**

Run: `flutter analyze lib/ui/mobile/setlist_editor.dart lib/ui/mobile/setlists_tab.dart` — Expected: clean.
Run: `flutter test test/mobile/` — Expected: PASS (fix any reorder test name).

- [ ] **Step 6: Commit**

```bash
git add lib/ui/mobile/setlist_editor.dart lib/ui/mobile/setlists_tab.dart test/mobile/
git commit -m "feat(setlist-ui): render rich crate entries + open-link, reorder on tracks"
```

---

## Task 6: Mobile AI tab — resolve + add-to-crate

**Files:**
- Modify: `lib/ui/mobile/ai_tab.dart`

- [ ] **Step 1: Add the resolver + tracks providers**

At top, add a provider:
```dart
final setResolutionServiceProvider =
    Provider<SetResolutionService>((ref) => SetResolutionService());
```
Imports: `set_resolution_service.dart`, `crate_track.dart`, `app_state.dart` (for `trackStreamProvider`), `setlist_provider.dart` (already).

- [ ] **Step 2: Replace the draft-save flow**

Add state: `bool _resolving = false; List<CrateTrack> _resolved = const []; int _foundCount = 0;`.

Replace the single "Save as setlist" button block with: when `_resolved.isEmpty`, show **"Resolve & add"** (calls `_resolve`); when resolved, show **"Save as new setlist"** and **"Add to crate…"**. `_resolve`:
```dart
Future<void> _resolve() async {
  setState(() { _resolving = true; _foundCount = 0; });
  final library = ref.read(trackStreamProvider).value ?? const <Track>[];
  final drafts = _draftTracks
      .map((t) => (title: t.title, artist: t.artist, bpm: t.bpm, key: t.key))
      .toList();
  final resolved = await ref.read(setResolutionServiceProvider).resolve(
        drafts, library: library,
        onProgress: (f, _) { if (mounted) setState(() => _foundCount = f); },
      );
  if (!mounted) return;
  setState(() { _resolving = false; _resolved = resolved; });
}
```

- [ ] **Step 3: New-setlist save uses resolved tracks**

`_onSave` builds `Crate(... tracks: _resolved ...)` instead of synthesized `trackIds`. Remove `_DraftTrack.synthesizedId` usage.

- [ ] **Step 4: "Add to crate…" sheet**

```dart
Future<void> _addToExisting() async {
  final crates = ref.read(setlistsProvider);
  final picked = await showModalBottomSheet<Crate>(
    context: context,
    backgroundColor: AppTheme.panel,
    builder: (_) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        for (final c in crates)
          ListTile(
            title: Text(c.name, style: const TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text('${c.tracks.length} tracks',
                style: const TextStyle(color: AppTheme.textTertiary)),
            onTap: () => Navigator.pop(context, c),
          ),
      ]),
    ),
  );
  if (picked == null) return;
  await ref.read(setlistActionsProvider).addTracks(picked, _resolved);
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added ${_resolved.length} to "${picked.name}"')));
  }
}
```

- [ ] **Step 5: Reset resolved state on a new build**

In `_onBuild`'s `setState`, also reset `_resolved = const []; _foundCount = 0;`.

- [ ] **Step 6: Verify**

Run: `flutter analyze lib/ui/mobile/ai_tab.dart` — Expected: clean (remove now-unused `_DraftTrack.synthesizedId`, `uuid` import if unused).
Run: `flutter test test/` — Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/mobile/ai_tab.dart
git commit -m "feat(ai-tab): resolve AI songs to playable links; save new or add to existing crate"
```

---

## Task 7: Desktop copilot uses the shared resolver

**Files:**
- Modify: `lib/ui/features/ai_copilot/ai_copilot_screen.dart`

- [ ] **Step 1: Route resolution through the shared service**

Replace the body of `_resolveTracksOnPlatforms` so it calls `SetResolutionService().resolve(aiTracks, library: ref.read(trackStreamProvider).value ?? const [])`, then maps each `CrateTrack` → the existing `AiCrateTrack` (same fields: title, artist, bpm, key, spotifyUrl, appleUrl, youtubeUrl, artworkUrl, resolved: `c.hasUrl`). Keep the existing status messages and `aiCrateProvider.setCrate(...)`/navigation. Delete the now-dead private `_searchSpotify`/`_searchApple` helpers if unused.

- [ ] **Step 2: Verify**

Run: `flutter analyze lib/ui/features/ai_copilot/` — Expected: clean.
Run: `flutter test test/` — Expected: PASS (desktop copilot tests, if any, still green).

- [ ] **Step 3: Commit**

```bash
git add lib/ui/features/ai_copilot/ai_copilot_screen.dart
git commit -m "refactor(copilot): desktop resolution via shared SetResolutionService"
```

---

## Task 8: Decay-sweep cost tuning (backend)

**Files:**
- Modify: `functions/src/lib/recency.ts`, `functions/src/decayTrending.ts`, `functions/test/recency.test.ts`

- [ ] **Step 1: Add the failing epsilon test** — append to `functions/test/recency.test.ts`:

```ts
// No write when the score barely moved (within WRITE_EPSILON) and base is set.
assert.equal(
  planTrackDecay({ trendScore: 0.5, baseScore: 0.5, updatedAt: iso(NOW - 0.2 * H) }, NOW),
  null,
  "sub-epsilon decay on a base-set doc → null (skip write)",
);
// Still retires past the window even if score is already tiny.
assert.deepEqual(
  planTrackDecay({ trendScore: 0.001, baseScore: 0.5, updatedAt: iso(NOW - 100 * H) }, NOW),
  { trendScore: 0, baseScore: 0.5, clearRegions: true },
  "stale still retires regardless of epsilon",
);
```

- [ ] **Step 2: Run to verify it fails**

Run (in `functions/`): `npx ts-node --project tsconfig.json test/recency.test.ts`
Expected: FAIL on the sub-epsilon assertion (currently any delta writes).

- [ ] **Step 3: Add `WRITE_EPSILON` to `planTrackDecay`** in `functions/src/lib/recency.ts`

Add to `RECENCY_DEFAULTS`: `writeEpsilon: 0.01`. In `planTrackDecay`, replace the change check:
```ts
const epsilon = opts.writeEpsilon ?? RECENCY_DEFAULTS.writeEpsilon;
const scoreChanged = Math.abs(newTrend - Number(track.trendScore.toFixed(4))) >= epsilon;
if (hasBase && !scoreChanged && !retire) return null;
```
Add `writeEpsilon?: number;` to `RecencyOptions`.

- [ ] **Step 4: Run to verify it passes**

Run: `npx ts-node --project tsconfig.json test/recency.test.ts` — Expected: "all assertions passed".

- [ ] **Step 5: Make the sweep hourly**

In `functions/src/decayTrending.ts`, change `schedule: "15,45 * * * *"` → `schedule: "15 * * * *"`. Update the doc comment ("offset … hourly").

- [ ] **Step 6: Typecheck + commit**

Run: `npx tsc --noEmit` — Expected: exit 0.
```bash
git add functions/src/lib/recency.ts functions/src/decayTrending.ts functions/test/recency.test.ts
git commit -m "perf(decay): skip sub-epsilon writes, run hourly (~$8/mo -> ~$1-2/mo)"
```

---

## Task 9: Full verification + deploy

- [ ] **Step 1: Dart suite + analyze**

Run: `flutter analyze` — Expected: "No issues found!".
Run: `flutter test` — Expected: all pass (prior 366 + new).

- [ ] **Step 2: Functions suite**

Run (in `functions/`): `npx tsc --noEmit && npm test` — Expected: tsc exit 0; all test files pass.

- [ ] **Step 3: Manual smoke (mobile)** — per `run` skill or simulator: build a set in the AI tab → "Resolve & add" shows progress → "Save as new setlist" → open it in Setlists → rows show real title/artist + open-link (not "Unknown track"). Then build again → "Add to crate…" → pick the setlist → confirm appended + deduped.

- [ ] **Step 4: Deploy the tuned sweep** (only after user OK — production)

Run: `firebase deploy --only functions:decayTrendingScores` — Expected: "Successful update". Verify next run logs "Trend decay sweep complete" with a lower write count.

---

## Self-review notes
- Spec coverage: CrateTrack (T1), Crate compat (T2), addTracks/dedupe (T3), resolver w/ YouTube-fallback (T4), editor/tab render (T5), mobile flow new+existing (T6), desktop parity via shared service (T7), sync rides `toMap()` (T2, unchanged pairing), decay tuning (T8), verification/deploy (T9). All spec sections mapped.
- Types consistent: `CrateTrack`, `Crate.tracks`, `mergeTracks`, `reorderTracks`, `SetResolutionService.resolve(drafts, library:, onProgress:)`, `RECENCY_DEFAULTS.writeEpsilon` used identically across tasks.
- Risk flagged inline: confirm `YoutubeVideoResult` field names (T4), confirm `url_launcher`/`launchUrl` availability (T5).
