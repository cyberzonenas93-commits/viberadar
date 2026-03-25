import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/library_track.dart';
import '../services/duplicate_detector_service.dart';
import '../services/library_persistence_service.dart';
import '../services/library_scanner_service.dart';

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
  DuplicateDetectorService get _detector =>
      ref.read(duplicateDetectorServiceProvider);
  LibraryPersistenceService get _persistence =>
      ref.read(libraryPersistenceServiceProvider);

  Future<void> _loadFromCache() async {
    final cached = await _persistence.load();
    if (cached != null && cached.tracks.isNotEmpty) {
      final dupes = _detector.findDuplicates(cached.tracks);
      state = state.copyWith(
        tracks: cached.tracks,
        duplicateGroups: dupes,
        scannedPath: cached.scannedPath,
        isLoading: false,
      );
    } else {
      state = state.copyWith(isLoading: false);
    }
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
      final tracks = await _scanner.scanDirectory(
        path,
        onProgress: (scanned, total) {
          state = state.copyWith(
            scanProgress: scanned,
            scanTotal: total,
            isScanning: true,
          );
        },
      );
      final dupes = _detector.findDuplicates(tracks);
      state = state.copyWith(
        tracks: tracks,
        duplicateGroups: dupes,
        isScanning: false,
        scanProgress: tracks.length,
        scanTotal: tracks.length,
      );
      await _persistence.save(tracks, path);
    } catch (e) {
      state = state.copyWith(isScanning: false, error: e.toString());
    }
  }

  void removeTrack(String id) {
    final updated = state.tracks.where((t) => t.id != id).toList();
    final dupes = _detector.findDuplicates(updated);
    state = state.copyWith(tracks: updated, duplicateGroups: dupes);
    _persistence.save(updated, state.scannedPath);
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
