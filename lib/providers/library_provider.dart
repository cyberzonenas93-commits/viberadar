import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/library_track.dart';
import '../services/library_scanner_service.dart';
import '../services/duplicate_detector_service.dart';

// ── Services ──────────────────────────────────────────────────────────────────

final libraryScannerServiceProvider =
    Provider<LibraryScannerService>((_) => LibraryScannerService());

final duplicateDetectorServiceProvider =
    Provider<DuplicateDetectorService>((_) => DuplicateDetectorService());

// ── Library State ─────────────────────────────────────────────────────────────

class LibraryState {
  const LibraryState({
    this.tracks = const [],
    this.duplicateGroups = const [],
    this.isScanning = false,
    this.scanProgress = 0,
    this.scanTotal = 0,
    this.scannedPath,
    this.error,
  });

  final List<LibraryTrack> tracks;
  final List<DuplicateGroup> duplicateGroups;
  final bool isScanning;
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
    int? scanProgress,
    int? scanTotal,
    Object? scannedPath = _sentinel,
    Object? error = _sentinel,
  }) {
    return LibraryState(
      tracks: tracks ?? this.tracks,
      duplicateGroups: duplicateGroups ?? this.duplicateGroups,
      isScanning: isScanning ?? this.isScanning,
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

// ── Library Notifier (Riverpod 3.x) ──────────────────────────────────────────

class LibraryNotifier extends Notifier<LibraryState> {
  @override
  LibraryState build() => const LibraryState();

  LibraryScannerService get _scanner =>
      ref.read(libraryScannerServiceProvider);
  DuplicateDetectorService get _detector =>
      ref.read(duplicateDetectorServiceProvider);

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
    } catch (e) {
      state = state.copyWith(isScanning: false, error: e.toString());
    }
  }

  void removeTrack(String id) {
    final updated = state.tracks.where((t) => t.id != id).toList();
    final dupes = _detector.findDuplicates(updated);
    state = state.copyWith(tracks: updated, duplicateGroups: dupes);
  }

  void clearLibrary() {
    state = const LibraryState();
  }
}

final libraryProvider =
    NotifierProvider<LibraryNotifier, LibraryState>(LibraryNotifier.new);

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
  CrateState build() => const CrateState();

  void createCrate(String name) {
    if (state.crates.containsKey(name)) return;
    state = state.copyWith(crates: {...state.crates, name: []});
  }

  void addTrackToCrate(String crateName, String trackId) {
    final current = Map<String, List<String>>.from(state.crates);
    current[crateName] = [...(current[crateName] ?? []), trackId];
    state = state.copyWith(crates: current);
  }

  void removeTrackFromCrate(String crateName, String trackId) {
    final current = Map<String, List<String>>.from(state.crates);
    current[crateName] =
        (current[crateName] ?? []).where((id) => id != trackId).toList();
    state = state.copyWith(crates: current);
  }

  void deleteCrate(String name) {
    final current = Map<String, List<String>>.from(state.crates);
    current.remove(name);
    state = state.copyWith(crates: current);
  }
}

final crateProvider =
    NotifierProvider<CrateNotifier, CrateState>(CrateNotifier.new);
