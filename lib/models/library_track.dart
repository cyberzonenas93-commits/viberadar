class LibraryTrack {
  const LibraryTrack({
    required this.id,
    required this.filePath,
    required this.fileName,
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
    required this.bpm,
    required this.key,
    required this.durationSeconds,
    required this.fileSizeBytes,
    required this.fileExtension,
    required this.md5Hash,
    required this.bitrate,
    required this.sampleRate,
    this.year,
  });

  final String id;
  final String filePath;
  final String fileName;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final double bpm;
  final String key;
  final double durationSeconds;
  final int fileSizeBytes;
  final String fileExtension;
  final String md5Hash;
  final int bitrate;
  final int sampleRate;
  final int? year;

  /// Release year — alias for [year], used for client-side year-range filtering.
  int? get releaseYear => year;

  String get durationFormatted {
    final m = (durationSeconds / 60).floor();
    final s = (durationSeconds % 60).floor();
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get fileSizeFormatted {
    if (fileSizeBytes < 1024 * 1024) return '${(fileSizeBytes / 1024).toStringAsFixed(0)} KB';
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  LibraryTrack copyWith({String? md5Hash}) => LibraryTrack(
    id: id, filePath: filePath, fileName: fileName, title: title, artist: artist,
    album: album, genre: genre, bpm: bpm, key: key, durationSeconds: durationSeconds,
    fileSizeBytes: fileSizeBytes, fileExtension: fileExtension,
    md5Hash: md5Hash ?? this.md5Hash, bitrate: bitrate, sampleRate: sampleRate, year: year,
  );
}

// ── Duplicate group ───────────────────────────────────────────────────────────

class DuplicateGroup {
  DuplicateGroup({
    required this.tracks,
    required this.reason,
    LibraryTrack? recommended,
    double? confidence,
  })  : recommended = recommended ?? _pickRecommended(tracks),
        confidence = confidence ?? _computeConfidence(tracks, reason);

  final List<LibraryTrack> tracks;
  final String reason;

  /// The track recommended to keep (highest quality signal).
  final LibraryTrack? recommended;

  /// Confidence that this is a real duplicate group (0.0–1.0).
  final double confidence;

  String get reasonLabel {
    switch (reason) {
      case 'exact_hash':
        return 'Exact duplicate';
      case 'same_title_artist':
        return 'Same title & artist';
      case 'similar_name':
        return 'Similar filename';
      default:
        return 'Possible duplicate';
    }
  }

  // ── Recommendation logic ─────────────────────────────────────────────────

  /// Pick the track to keep: highest bitrate → largest file → most complete metadata.
  static LibraryTrack? _pickRecommended(List<LibraryTrack> tracks) {
    if (tracks.isEmpty) return null;

    return tracks.reduce((best, t) {
      // 1. Prefer higher bitrate
      if (t.bitrate > best.bitrate) return t;
      if (t.bitrate < best.bitrate) return best;

      // 2. Tie-break: larger file
      if (t.fileSizeBytes > best.fileSizeBytes) return t;
      if (t.fileSizeBytes < best.fileSizeBytes) return best;

      // 3. Tie-break: more complete metadata (non-empty title + artist + album)
      final tScore = _metaScore(t);
      final bScore = _metaScore(best);
      return tScore >= bScore ? t : best;
    });
  }

  static int _metaScore(LibraryTrack t) {
    int s = 0;
    if (t.title.isNotEmpty) s++;
    if (t.artist.isNotEmpty) s++;
    if (t.album.isNotEmpty) s++;
    if (t.genre.isNotEmpty) s++;
    if (t.year != null) s++;
    return s;
  }

  /// Higher confidence for exact-hash matches; lower for similar-name guesses.
  static double _computeConfidence(List<LibraryTrack> tracks, String reason) {
    switch (reason) {
      case 'exact_hash':
        return 1.0;
      case 'same_title_artist':
        return 0.85;
      case 'similar_name':
        return 0.5;
      default:
        return 0.4;
    }
  }
}
