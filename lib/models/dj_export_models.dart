import 'library_track.dart';
import 'track.dart';

// ── DJ export target ──────────────────────────────────────────────────────────

enum DjTarget { virtualDj, serato }

extension DjTargetLabel on DjTarget {
  String get label => switch (this) {
        DjTarget.virtualDj => 'VirtualDJ',
        DjTarget.serato => 'Serato',
      };
}

// ── Per-track resolution result ───────────────────────────────────────────────

enum DjTrackResolution {
  /// Matched to a file in the local library — real absolute path used.
  localMatch,

  /// Not in local library but a real TIDAL track ID was resolved (VDJ only).
  tidalFallback,

  /// Could not be resolved — skipped from the export.
  skipped,
}

class DjExportTrack {
  const DjExportTrack({
    this.cloudTrack,
    this.localTrack,
    required this.resolution,
    this.tidalId,
    this.skipReason,
  });

  /// The cloud-side [Track] (may be null for library-only flows).
  final Track? cloudTrack;

  /// The matched local [LibraryTrack] (null when not found locally).
  final LibraryTrack? localTrack;

  final DjTrackResolution resolution;

  /// Resolved TIDAL track ID (digits only), set when [resolution] is
  /// [DjTrackResolution.tidalFallback].
  final String? tidalId;

  /// Human-readable reason the track was skipped, set when
  /// [resolution] is [DjTrackResolution.skipped].
  final String? skipReason;

  // ── Convenience getters ──────────────────────────────────────────────────

  String get displayTitle =>
      cloudTrack?.title ?? localTrack?.title ?? 'Unknown';
  String get displayArtist =>
      cloudTrack?.artist ?? localTrack?.artist ?? 'Unknown';
  String get displayRemix => ''; // extended by callers when needed

  /// Absolute local file path (null when no local match).
  String? get localFilePath => localTrack?.filePath;

  /// VirtualDJ TIDAL path (e.g. `netsearch://td12345678`).
  String? get tidalPath => tidalId != null ? 'netsearch://td$tidalId' : null;

  /// The effective export path:
  ///   • local file path for [DjTrackResolution.localMatch]
  ///   • TIDAL path for [DjTrackResolution.tidalFallback]
  ///   • null for [DjTrackResolution.skipped]
  String? get exportPath => switch (resolution) {
        DjTrackResolution.localMatch => localFilePath,
        DjTrackResolution.tidalFallback => tidalPath,
        DjTrackResolution.skipped => null,
      };

  bool get isLocalMatch => resolution == DjTrackResolution.localMatch;
  bool get isTidalFallback => resolution == DjTrackResolution.tidalFallback;
  bool get isSkipped => resolution == DjTrackResolution.skipped;
}

// ── Export configuration ──────────────────────────────────────────────────────

class DjExportConfig {
  const DjExportConfig({
    required this.target,
    required this.djRoot,
    this.useTidal = false,
    this.parentCrateName,
    this.tidalIds = const {},
  });

  final DjTarget target;

  /// Validated root directory for the DJ software.
  final String djRoot;

  /// Whether to write TIDAL fallback entries (VirtualDJ only).
  final bool useTidal;

  /// Serato nested-crate parent name, e.g. `'LocalMusic'`.
  /// Null → top-level crate. Non-null → encoded with `%%` separator.
  final String? parentCrateName;

  /// Map of cloud track ID → TIDAL track ID (digits only).
  /// Populated by the caller after a TIDAL resolution step.
  final Map<String, String> tidalIds;
}

// ── Export result ─────────────────────────────────────────────────────────────

class DjExportResult {
  const DjExportResult({
    required this.target,
    required this.playlistName,
    required this.totalTracks,
    required this.localMatchCount,
    required this.tidalCount,
    required this.skippedCount,
    required this.outputPath,
    required this.djRoot,
    required this.tracks,
    this.warning,
  });

  final DjTarget target;
  final String playlistName;
  final int totalTracks;

  /// Tracks exported with a real local file path.
  final int localMatchCount;

  /// Tracks exported via TIDAL fallback (VirtualDJ only).
  final int tidalCount;

  /// Tracks skipped — could not be resolved.
  final int skippedCount;

  /// Absolute path of the file written on disk.
  final String outputPath;

  /// The DJ root directory used for this export.
  final String djRoot;

  /// Per-track resolution details.
  final List<DjExportTrack> tracks;

  /// Optional advisory for the user (e.g. "Restart Serato to see new crate").
  final String? warning;

  // ── Derived ──────────────────────────────────────────────────────────────

  List<DjExportTrack> get localTracks =>
      tracks.where((t) => t.isLocalMatch).toList();
  List<DjExportTrack> get tidalTracks =>
      tracks.where((t) => t.isTidalFallback).toList();
  List<DjExportTrack> get skippedTracks =>
      tracks.where((t) => t.isSkipped).toList();
}
