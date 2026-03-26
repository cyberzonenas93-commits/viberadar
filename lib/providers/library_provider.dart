import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/library_track.dart';
import '../services/duplicate_detector_service.dart';
import '../services/library_persistence_service.dart';
import '../services/library_scanner_service.dart';
import '../services/spotify_artist_service.dart';
import '../services/apple_music_artist_service.dart';

// ── Services ──────────────────────────────────────────────────────────────────

final libraryScannerServiceProvider =
    Provider<LibraryScannerService>((_) => LibraryScannerService());

final duplicateDetectorServiceProvider =
    Provider<DuplicateDetectorService>((_) => DuplicateDetectorService());

final libraryPersistenceServiceProvider =
    Provider<LibraryPersistenceService>((_) => LibraryPersistenceService());

// ── Library State ─────────────────────────────────────────────────────────────

class LibraryState {
  const LibraryState({
    this.tracks = const [],
    this.duplicateGroups = const [],
    this.isScanning = false,
    this.isLoading = false,
    this.scanProgress = 0,
    this.scanTotal = 0,
    this.scannedPath,
    this.error,
  });

  final List<LibraryTrack> tracks;
  final List<DuplicateGroup> duplicateGroups;
  final bool isScanning;
  final bool isLoading;
  final int scanProgress;
  final int scanTotal;
  final String? scannedPath;
  final String? error;

  bool get hasLibrary => tracks.isNotEmpty;
  int get duplicateCount =>
      duplicateGroups.fold(0, (sum, g) => sum + g.tracks.length - 1);

  LibraryState copyWith({
    List<LibraryTrack>? tracks,
    List<DuplicateGroup>? duplicateGroups,
    bool? isScanning,
    bool? isLoading,
    int? scanProgress,
    int? scanTotal,
    Object? scannedPath = _sentinel,
    Object? error = _sentinel,
  }) {
    return LibraryState(
      tracks: tracks ?? this.tracks,
      duplicateGroups: duplicateGroups ?? this.duplicateGroups,
      isScanning: isScanning ?? this.isScanning,
      isLoading: isLoading ?? this.isLoading,
      scanProgress: scanProgress ?? this.scanProgress,
      scanTotal: scanTotal ?? this.scanTotal,
      scannedPath: identical(scannedPath, _sentinel)
          ? this.scannedPath
          : scannedPath as String?,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }
}

const _sentinel = Object();

// ── Library Notifier ──────────────────────────────────────────────────────────

class LibraryNotifier extends Notifier<LibraryState> {
  @override
  LibraryState build() {
    _loadFromCache();
    return const LibraryState(isLoading: true);
  }

  LibraryScannerService get _scanner =>
      ref.read(libraryScannerServiceProvider);
  LibraryPersistenceService get _persistence =>
      ref.read(libraryPersistenceServiceProvider);

  Future<void> _loadFromCache() async {
    final cached = await _persistence.load();
    if (cached != null && cached.tracks.isNotEmpty) {
      // Show tracks immediately — don't block on duplicate detection
      state = state.copyWith(
        tracks: cached.tracks,
        scannedPath: cached.scannedPath,
        isLoading: false,
      );
      // Defer duplicate detection to a background isolate
      _detectDuplicatesAsync(cached.tracks);
    } else {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Runs duplicate detection in a background isolate so the UI never freezes.
  /// For very large libraries (>5000 tracks), skips detection entirely to
  /// prevent isolate serialization overhead from freezing the app.
  Future<void> _detectDuplicatesAsync(List<LibraryTrack> tracks) async {
    // Skip duplicate detection for very large libraries to prevent freeze
    if (tracks.length > 10000) {
      dev.log('Skipping duplicate detection: ${tracks.length} tracks exceeds safe limit', name: 'Library');
      return;
    }
    try {
      final dupes = await compute(_findDuplicatesIsolate, tracks);
      state = state.copyWith(duplicateGroups: dupes);
    } catch (e) {
      dev.log('Duplicate detection failed: $e', name: 'Library');
      // If isolate fails, run with empty duplicates rather than freeze
    }
  }

  /// Top-level function for compute() isolate — must not reference `this`.
  static List<DuplicateGroup> _findDuplicatesIsolate(List<LibraryTrack> tracks) {
    return DuplicateDetectorService().findDuplicates(tracks);
  }

  Future<void> scanDirectory(String path) async {
    state = state.copyWith(
      isScanning: true,
      scanProgress: 0,
      scanTotal: 0,
      scannedPath: path,
      error: null,
    );
    try {
      // Throttle UI updates to at most once per 500ms to prevent jank
      var lastUpdate = DateTime.now();
      final tracks = await _scanner.scanDirectory(
        path,
        onProgress: (scanned, total) {
          final now = DateTime.now();
          // Only update UI every 500ms or on completion
          if (now.difference(lastUpdate).inMilliseconds > 500 || scanned == total) {
            lastUpdate = now;
            state = state.copyWith(
              scanProgress: scanned,
              scanTotal: total,
              isScanning: true,
            );
          }
        },
      );

      // Show tracks immediately — scan is done, UI unblocks
      state = state.copyWith(
        tracks: tracks,
        isScanning: false,
        scanProgress: tracks.length,
        scanTotal: tracks.length,
      );

      // Save cache in parallel with duplicate detection + artwork enrichment
      _persistence.save(tracks, path);

      // Detect duplicates in background isolate (non-blocking)
      _detectDuplicatesAsync(tracks);

      // Enrich artwork from Spotify/Apple Music in background (non-blocking)
      _enrichArtworkAsync(tracks);
    } catch (e) {
      state = state.copyWith(isScanning: false, error: e.toString());
    }
  }

  /// Fetches album artwork from Spotify and Apple Music for tracks that
  /// don't have artwork yet. Runs in background, updates state in batches.
  Future<void> _enrichArtworkAsync(List<LibraryTrack> tracks, {int maxTracks = 100}) async {
    final needsArt = tracks.where((t) => t.artworkUrl == null).toList();
    if (needsArt.isEmpty) return;

    final toEnrich = needsArt.take(maxTracks).toList();
    dev.log('Enriching artwork for ${toEnrich.length} tracks', name: 'Library');

    final spotify = SpotifyArtistService();
    final apple = AppleMusicArtistService();

    // Deduplicate by artist+title to reduce API calls
    final seen = <String, String>{};
    final enriched = <String, String>{};
    int updated = 0;

    for (var i = 0; i < toEnrich.length; i++) {
      final t = toEnrich[i];
      final key = '${t.artist.toLowerCase().trim()}::${t.title.toLowerCase().trim()}';

      // Check if we already resolved this artist+title combo
      if (seen.containsKey(key)) {
        enriched[t.id] = seen[key]!;
        updated++;
        continue;
      }

      String? artworkUrl;
      final query = '${t.artist} ${t.title}'.trim();
      if (query.length < 3) continue;

      // Try Spotify first
      try {
        final results = await spotify.searchTracks(query, limit: 1)
            .timeout(const Duration(seconds: 5), onTimeout: () => []);
        if (results.isNotEmpty && (results.first.albumArt ?? '').isNotEmpty) {
          artworkUrl = results.first.albumArt;
        }
      } catch (_) {}

      // Fallback to Apple Music
      if (artworkUrl == null) {
        try {
          final results = await apple.searchSongs(query, limit: 1)
              .timeout(const Duration(seconds: 5), onTimeout: () => []);
          if (results.isNotEmpty && (results.first.artworkUrl ?? '').isNotEmpty) {
            artworkUrl = results.first.artworkUrl;
          }
        } catch (_) {}
      }

      if (artworkUrl != null) {
        seen[key] = artworkUrl;
        enriched[t.id] = artworkUrl;
        updated++;
      }

      // Flush updates to UI every 20 tracks
      if (updated > 0 && (updated % 20 == 0 || i == toEnrich.length - 1)) {
        final currentTracks = [...state.tracks];
        bool changed = false;
        for (var j = 0; j < currentTracks.length; j++) {
          final url = enriched[currentTracks[j].id];
          if (url != null && currentTracks[j].artworkUrl == null) {
            currentTracks[j] = currentTracks[j].copyWith(artworkUrl: url);
            changed = true;
          }
        }
        if (changed) {
          state = state.copyWith(tracks: currentTracks);
        }
        // Yield to event loop
        await Future<void>.delayed(Duration.zero);
      }

      // Small delay between API calls to avoid rate limiting
      if (i % 5 == 4) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }

    // Final save with enriched artwork
    if (updated > 0) {
      _persistence.save(state.tracks, state.scannedPath);
      dev.log('Artwork enrichment complete: $updated tracks updated', name: 'Library');
    }
  }

  /// User-triggered: fetch artwork for ALL tracks without art (no cap).
  /// Updates scan progress to show UI feedback.
  Future<void> fetchAllArtwork() async {
    final needsArt = state.tracks.where((t) => t.artworkUrl == null).toList();
    if (needsArt.isEmpty) {
      dev.log('All tracks already have artwork', name: 'Library');
      return;
    }
    dev.log('Fetching artwork for ${needsArt.length} tracks', name: 'Library');
    // Show scanning state for UI feedback
    state = state.copyWith(isScanning: true, scanProgress: 0, scanTotal: needsArt.length);
    await _enrichArtworkAsync(state.tracks, maxTracks: needsArt.length);
    state = state.copyWith(isScanning: false);
  }

  void removeTrack(String id) {
    final updated = state.tracks.where((t) => t.id != id).toList();
    state = state.copyWith(tracks: updated);
    _persistence.save(updated, state.scannedPath);
    // Re-detect duplicates in background
    _detectDuplicatesAsync(updated);
  }

  Future<void> clearLibrary() async {
    state = const LibraryState();
    await _persistence.clear();
  }
}

final libraryProvider =
    NotifierProvider<LibraryNotifier, LibraryState>(LibraryNotifier.new);

// ── Crate Persistence ─────────────────────────────────────────────────────────

Future<File> _getCratesCacheFile() async {
  final dir = await getApplicationDocumentsDirectory();
  final cacheDir = Directory(p.join(dir.path, 'VibeRadar'));
  await cacheDir.create(recursive: true);
  return File(p.join(cacheDir.path, 'crates_cache.json'));
}

Future<Map<String, List<String>>> _loadCratesFromDisk() async {
  try {
    final file = await _getCratesCacheFile();
    if (!file.existsSync()) return {};
    final raw = await file.readAsString();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return json.map(
      (k, v) => MapEntry(k, (v as List).cast<String>()),
    );
  } catch (_) {
    return {};
  }
}

Future<void> _saveCratesToDisk(Map<String, List<String>> crates) async {
  try {
    final file = await _getCratesCacheFile();
    await file.writeAsString(jsonEncode(crates));
  } catch (_) {}
}

// ── Crate State ───────────────────────────────────────────────────────────────

class CrateState {
  const CrateState({this.crates = const {}});
  final Map<String, List<String>> crates;
  List<String> get crateNames => crates.keys.toList();

  CrateState copyWith({Map<String, List<String>>? crates}) =>
      CrateState(crates: crates ?? this.crates);
}

class CrateNotifier extends Notifier<CrateState> {
  @override
  CrateState build() {
    // Load persisted crates asynchronously on first build
    _loadFromCache();
    return const CrateState();
  }

  Future<void> _loadFromCache() async {
    final loaded = await _loadCratesFromDisk();
    if (loaded.isNotEmpty) {
      state = CrateState(crates: loaded);
    }
  }

  void createCrate(String name) {
    if (state.crates.containsKey(name)) return;
    final updated = {...state.crates, name: <String>[]};
    state = state.copyWith(crates: updated);
    _saveCratesToDisk(updated);
  }

  void addTrackToCrate(String crateName, String trackId) {
    final current = Map<String, List<String>>.from(state.crates);
    current[crateName] = [...(current[crateName] ?? []), trackId];
    state = state.copyWith(crates: current);
    _saveCratesToDisk(current);
  }

  void removeTrackFromCrate(String crateName, String trackId) {
    final current = Map<String, List<String>>.from(state.crates);
    current[crateName] =
        (current[crateName] ?? []).where((id) => id != trackId).toList();
    state = state.copyWith(crates: current);
    _saveCratesToDisk(current);
  }

  void deleteCrate(String name) {
    final current = Map<String, List<String>>.from(state.crates);
    current.remove(name);
    state = state.copyWith(crates: current);
    _saveCratesToDisk(current);
  }
}

final crateProvider =
    NotifierProvider<CrateNotifier, CrateState>(CrateNotifier.new);

// ── AI Crate Track (rich metadata for AI-generated crates) ───────────────────

class AiCrateTrack {
  final String title;
  final String artist;
  final int bpm;
  final String key;
  final String? spotifyUrl;
  final String? appleUrl;
  final String? youtubeUrl;
  final String? artworkUrl;
  final bool resolved; // true if we found it on a platform

  const AiCrateTrack({
    required this.title,
    required this.artist,
    this.bpm = 0,
    this.key = '',
    this.spotifyUrl,
    this.appleUrl,
    this.youtubeUrl,
    this.artworkUrl,
    this.resolved = false,
  });

  String get bestUrl => spotifyUrl ?? appleUrl ?? youtubeUrl ?? '';
  bool get hasUrl => bestUrl.isNotEmpty;

  String get platformLabel {
    if (spotifyUrl != null) return 'Spotify';
    if (appleUrl != null) return 'Apple Music';
    if (youtubeUrl != null) return 'YouTube';
    return '';
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'artist': artist,
    'bpm': bpm,
    'key': key,
    'spotifyUrl': spotifyUrl,
    'appleUrl': appleUrl,
    'youtubeUrl': youtubeUrl,
    'artworkUrl': artworkUrl,
    'resolved': resolved,
  };

  factory AiCrateTrack.fromJson(Map<String, dynamic> m) => AiCrateTrack(
    title: m['title'] as String? ?? '',
    artist: m['artist'] as String? ?? '',
    bpm: m['bpm'] as int? ?? 0,
    key: m['key'] as String? ?? '',
    spotifyUrl: m['spotifyUrl'] as String?,
    appleUrl: m['appleUrl'] as String?,
    youtubeUrl: m['youtubeUrl'] as String?,
    artworkUrl: m['artworkUrl'] as String?,
    resolved: m['resolved'] as bool? ?? false,
  );
}

class AiCrateState {
  const AiCrateState({this.crates = const {}});
  /// crateName → list of rich tracks
  final Map<String, List<AiCrateTrack>> crates;

  AiCrateState copyWith({Map<String, List<AiCrateTrack>>? crates}) =>
      AiCrateState(crates: crates ?? this.crates);
}

class AiCrateNotifier extends Notifier<AiCrateState> {
  @override
  AiCrateState build() {
    _loadFromDisk();
    return const AiCrateState();
  }

  void setCrate(String name, List<AiCrateTrack> tracks) {
    final updated = {...state.crates, name: tracks};
    state = state.copyWith(crates: updated);
    _saveToDisk(updated);
  }

  void deleteCrate(String name) {
    final updated = {...state.crates}..remove(name);
    state = state.copyWith(crates: updated);
    _saveToDisk(updated);
  }

  Future<void> _loadFromDisk() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'VibeRadar', 'ai_crates_cache.json'));
      if (!file.existsSync()) return;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final loaded = <String, List<AiCrateTrack>>{};
      for (final entry in json.entries) {
        loaded[entry.key] = (entry.value as List)
            .map((t) => AiCrateTrack.fromJson(t as Map<String, dynamic>))
            .toList();
      }
      state = AiCrateState(crates: loaded);
    } catch (_) {}
  }

  Future<void> _saveToDisk(Map<String, List<AiCrateTrack>> crates) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory(p.join(dir.path, 'VibeRadar'));
      await folder.create(recursive: true);
      final file = File(p.join(folder.path, 'ai_crates_cache.json'));
      final json = crates.map((k, v) => MapEntry(k, v.map((t) => t.toJson()).toList()));
      await file.writeAsString(jsonEncode(json));
    } catch (_) {}
  }
}

final aiCrateProvider =
    NotifierProvider<AiCrateNotifier, AiCrateState>(AiCrateNotifier.new);
