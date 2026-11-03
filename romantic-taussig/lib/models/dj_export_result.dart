// ── DJ Export target ──────────────────────────────────────────────────────────

enum DjExportTarget { virtualDj, serato }

extension DjExportTargetLabel on DjExportTarget {
  String get label => switch (this) {
        DjExportTarget.virtualDj => 'VirtualDJ',
        DjExportTarget.serato => 'Serato',
      };
}

// ── Per-track resolution ──────────────────────────────────────────────────────

enum DjTrackStatus {
  /// Track was found in the local library and will be exported with real path.
  local,

  /// Track was not found locally but resolved to a TIDAL track ID (VirtualDJ
  /// netsearch:// only — never for Serato).
  tidal,

  /// Track could not be resolved and was skipped.
  skipped,
}

class DjTrackResolution {
  const DjTrackResolution({
    required this.title,
    required this.artist,
    required this.status,
    this.localFilePath,
    this.tidalTrackId,
    this.fileSizeBytes = 0,
    this.durationSeconds = 0.0,
    this.bpm = 0.0,
    this.key = '',
    this.skipReason,
  });

  final String title;
  final String artist;
  final DjTrackStatus status;
  final String? localFilePath;

  /// TIDAL numeric track ID — only populated for [DjTrackStatus.tidal].
  final String? tidalTrackId;

  // Metadata forwarded into the DJ software record.
  final int fileSizeBytes;
  final double durationSeconds;
  final double bpm;
  final String key;
  final String? skipReason;

  bool get isLocal => status == DjTrackStatus.local;
  bool get isTidal => status == DjTrackStatus.tidal;
  bool get isSkipped => status == DjTrackStatus.skipped;

  /// The path string to write into the DJ software record.
  /// For local tracks: absolute filesystem path.
  /// For TIDAL tracks:  netsearch://td<trackId>
  String get exportPath {
    if (isLocal) return localFilePath ?? '';
    if (isTidal) return 'netsearch://td$tidalTrackId';
    return '';
  }
}

// ── Full export result ────────────────────────────────────────────────────────

class DjExportResult {
  const DjExportResult({
    required this.target,
    required this.crateName,
    required this.rootPath,
    required this.outputPath,
    required this.tracks,
    required this.exportedAt,
    this.warnings = const [],
  });

  final DjExportTarget target;
  final String crateName;

  /// Detected/confirmed root folder of the DJ software.
  final String rootPath;

  /// Exact file(s) written — e.g. the .vdjfolder path or .crate path.
  final String outputPath;

  final List<DjTrackResolution> tracks;
  final DateTime exportedAt;
  final List<String> warnings;

  int get totalTracks => tracks.length;
  int get localCount => tracks.where((t) => t.isLocal).length;
  int get tidalCount => tracks.where((t) => t.isTidal).length;
  int get skippedCount => tracks.where((t) => t.isSkipped).length;

  String get summary {
    final parts = <String>['$localCount local'];
    if (tidalCount > 0) parts.add('$tidalCount TIDAL');
    if (skippedCount > 0) parts.add('$skippedCount skipped');
    return parts.join(', ');
  }
}
