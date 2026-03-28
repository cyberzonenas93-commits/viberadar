import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/dj_export_result.dart';
import '../services/dj_root_detection_service.dart';
import '../services/virtual_dj_export_service.dart';
import '../services/serato_export_service.dart';

// ── Service providers ─────────────────────────────────────────────────────────

final djRootDetectionServiceProvider =
    Provider<DjRootDetectionService>((_) => DjRootDetectionService());

final virtualDjExportServiceProvider =
    Provider<VirtualDjExportService>((_) => VirtualDjExportService());

final seratoExportServiceProvider =
    Provider<SeratoExportService>((_) => SeratoExportService());

// ── State ─────────────────────────────────────────────────────────────────────

class DjExportState {
  const DjExportState({
    this.vdjRoot,
    this.seratoRoot,
    this.isExporting = false,
    this.lastResult,
    this.error,
  });

  /// Confirmed VirtualDJ root folder (null until resolved).
  final String? vdjRoot;

  /// Confirmed Serato root folder (null until resolved).
  final String? seratoRoot;

  final bool isExporting;
  final DjExportResult? lastResult;
  final String? error;

  bool get hasVdjRoot => vdjRoot != null && vdjRoot!.isNotEmpty;
  bool get hasSeratoRoot => seratoRoot != null && seratoRoot!.isNotEmpty;

  DjExportState copyWith({
    Object? vdjRoot = _sentinel,
    Object? seratoRoot = _sentinel,
    bool? isExporting,
    Object? lastResult = _sentinel,
    Object? error = _sentinel,
  }) =>
      DjExportState(
        vdjRoot:
            identical(vdjRoot, _sentinel) ? this.vdjRoot : vdjRoot as String?,
        seratoRoot: identical(seratoRoot, _sentinel)
            ? this.seratoRoot
            : seratoRoot as String?,
        isExporting: isExporting ?? this.isExporting,
        lastResult: identical(lastResult, _sentinel)
            ? this.lastResult
            : lastResult as DjExportResult?,
        error: identical(error, _sentinel) ? this.error : error as String?,
      );
}

const _sentinel = Object();

// ── Notifier ──────────────────────────────────────────────────────────────────

class DjExportNotifier extends Notifier<DjExportState> {
  @override
  DjExportState build() {
    _init();
    return const DjExportState();
  }

  DjRootDetectionService get _detection =>
      ref.read(djRootDetectionServiceProvider);
  VirtualDjExportService get _vdj => ref.read(virtualDjExportServiceProvider);
  SeratoExportService get _serato => ref.read(seratoExportServiceProvider);

  Future<void> _init() async {
    final vdjRoot = await _detection.resolveVirtualDjRoot();
    final seratoRoot = await _detection.resolveSeratoRoot();
    state = state.copyWith(vdjRoot: vdjRoot, seratoRoot: seratoRoot);
  }

  // ── Root management ──────────────────────────────────────────────────────

  Future<bool> setVirtualDjRoot(String path) async {
    if (!_detection.validateVirtualDjRoot(path)) return false;
    await _detection.persistVirtualDjRoot(path);
    state = state.copyWith(vdjRoot: path);
    return true;
  }

  Future<bool> setSeratoRoot(String path) async {
    if (!_detection.validateSeratoRoot(path)) return false;
    await _detection.persistSeratoRoot(path);
    state = state.copyWith(seratoRoot: path);
    return true;

  }

  /// Accept an unvalidated path (user manually chose it — we still persist).
  Future<void> forceSetVirtualDjRoot(String path) async {
    await _detection.persistVirtualDjRoot(path);
    state = state.copyWith(vdjRoot: path, error: null);
  }

  Future<void> forceSetSeratoRoot(String path) async {
    await _detection.persistSeratoRoot(path);
    state = state.copyWith(seratoRoot: path, error: null);
  }

  // ── Exports ──────────────────────────────────────────────────────────────

  Future<DjExportResult?> exportToVirtualDj({
    required String crateName,
    required List<dynamic> tracks, // List<LibraryTrack>
  }) async {
    final root = state.vdjRoot;
    if (root == null) {
      state = state.copyWith(error: 'VirtualDJ root not set');
      return null;
    }
    state = state.copyWith(isExporting: true, error: null, lastResult: null);
    try {
      final result = await _vdj.exportCrate(
        vdjRoot: root,
        playlistName: crateName,
        tracks: List.from(tracks),
      );
      state = state.copyWith(isExporting: false, lastResult: result);
      return result;
    } catch (e) {
      state = state.copyWith(
          isExporting: false, error: 'VirtualDJ export failed: $e');
      return null;
    }
  }

  Future<DjExportResult?> exportToSerato({
    required String crateName,
    required List<dynamic> tracks, // List<LibraryTrack>
    String? parentCrateName,
  }) async {
    final root = state.seratoRoot;
    if (root == null) {
      state = state.copyWith(error: 'Serato root not set');
      return null;
    }
    state = state.copyWith(isExporting: true, error: null, lastResult: null);
    try {
      final result = await _serato.exportCrate(
        seratoRoot: root,
        crateName: crateName,
        tracks: List.from(tracks),
        parentCrateName: parentCrateName,
      );
      state = state.copyWith(isExporting: false, lastResult: result);
      return result;
    } catch (e) {
      state = state.copyWith(
          isExporting: false, error: 'Serato export failed: $e');
      return null;
    }
  }

  void clearResult() => state = state.copyWith(lastResult: null, error: null);
}

final djExportProvider =
    NotifierProvider<DjExportNotifier, DjExportState>(DjExportNotifier.new);
