import '../models/library_track.dart';
import '../models/track.dart';

enum MatchStatus {
  /// Artist + title both match exactly after normalisation.
  found,

  /// Title fuzzy-match (Levenshtein ≤ 3) with same artist.
  fuzzyMatch,

  /// No match found in the local library.
  missing,

  /// Multiple library files match — possible duplicate versions.
  duplicateVersions,
}

class TrackMatch {
  const TrackMatch({
    required this.vibeTrack,
    required this.status,
    this.localFilePath,
    this.candidates = const [],
    required this.matchScore,
  });

  /// The VibeRadar [Track] being matched.
  final Track vibeTrack;

  final MatchStatus status;

  /// Path of the best-matching local file (null when [status] == missing).
  final String? localFilePath;

  /// All candidate file paths (populated for fuzzyMatch / duplicateVersions).
  final List<String> candidates;

  /// Confidence 0.0–1.0 (1.0 = exact match).
  final double matchScore;

  bool get isFound =>
      status == MatchStatus.found || status == MatchStatus.duplicateVersions;
  bool get isFuzzy => status == MatchStatus.fuzzyMatch;
  bool get isMissing => status == MatchStatus.missing;
}

/// Matches a list of VibeRadar [Track]s against the local [LibraryTrack]
/// catalogue already loaded by [LibraryScannerService].
///
/// Matching tiers
/// ─────────────────────────────────────────────────────────────
/// 1. Exact   artist + title both match exactly (normalised)
/// 2. Fuzzy   Levenshtein distance ≤ 3 on normalised title + same artist
/// 3. Missing no match found
class LocalMatchService {
  // ── public API ────────────────────────────────────────────────────────────

  Future<List<TrackMatch>> matchSet(
    List<Track> setTracks,
    List<LibraryTrack> libraryTracks,
  ) async {
    return setTracks.map((vt) => _matchOne(vt, libraryTracks)).toList();
  }

  // ── private ───────────────────────────────────────────────────────────────

  TrackMatch _matchOne(Track vt, List<LibraryTrack> library) {
    final queryTitle = _normalise(vt.title);
    final queryArtist = _normalise(vt.artist);

    final exactMatches = <LibraryTrack>[];
    final fuzzyMatches = <_ScoredLib>[];

    for (final lib in library) {
      final libTitle = _normalise(lib.title.isNotEmpty ? lib.title : lib.fileName);
      final libArtist = _normalise(lib.artist);

      final artistMatch = queryArtist.isEmpty ||
          libArtist.isEmpty ||
          libArtist.contains(queryArtist) ||
          queryArtist.contains(libArtist);

      if (!artistMatch) continue;

      if (libTitle == queryTitle) {
        exactMatches.add(lib);
      } else {
        final dist = _levenshtein(queryTitle, libTitle);
        if (dist <= 3) {
          final score = 1.0 - (dist / (queryTitle.length.clamp(1, 999)));
          fuzzyMatches.add(_ScoredLib(lib, score.clamp(0.0, 1.0)));
        }
      }
    }

    if (exactMatches.length == 1) {
      return TrackMatch(
        vibeTrack: vt,
        status: MatchStatus.found,
        localFilePath: exactMatches.first.filePath,
        matchScore: 1.0,
      );
    }

    if (exactMatches.length > 1) {
      return TrackMatch(
        vibeTrack: vt,
        status: MatchStatus.duplicateVersions,
        localFilePath: exactMatches.first.filePath,
        candidates: exactMatches.map((l) => l.filePath).toList(),
        matchScore: 1.0,
      );
    }

    if (fuzzyMatches.isNotEmpty) {
      fuzzyMatches.sort((a, b) => b.score.compareTo(a.score));
      return TrackMatch(
        vibeTrack: vt,
        status: MatchStatus.fuzzyMatch,
        localFilePath: fuzzyMatches.first.lib.filePath,
        candidates: fuzzyMatches.map((s) => s.lib.filePath).toList(),
        matchScore: fuzzyMatches.first.score,
      );
    }

    return TrackMatch(
      vibeTrack: vt,
      status: MatchStatus.missing,
      matchScore: 0.0,
    );
  }

  /// Normalise a string for comparison: lowercase, strip feat/remix markers,
  /// collapse whitespace, remove punctuation noise.
  String _normalise(String input) {
    var s = input.toLowerCase();
    // Strip common parenthetical suffixes
    s = s.replaceAll(RegExp(r'\(feat[^)]*\)', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\(ft[^)]*\)', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\(remix[^)]*\)', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\(original[^)]*\)', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\(radio[^)]*\)', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\[.*?\]'), '');
    // Strip file extension if present
    s = s.replaceAll(RegExp(r'\.(mp3|flac|wav|aac|m4a|ogg|aiff)$'), '');
    // Collapse non-alphanumeric to space
    s = s.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    // Collapse whitespace
    return s.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Standard Levenshtein distance — capped at [maxDist] for performance.
  int _levenshtein(String a, String b, {int maxDist = 4}) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length.clamp(0, maxDist);
    if (b.isEmpty) return a.length.clamp(0, maxDist);

    // Early-exit if length diff already exceeds threshold
    if ((a.length - b.length).abs() > maxDist) return maxDist + 1;

    final prev = List<int>.generate(b.length + 1, (i) => i);
    final curr = List<int>.filled(b.length + 1, 0);

    for (var i = 1; i <= a.length; i++) {
      curr[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = [
          curr[j - 1] + 1,
          prev[j] + 1,
          prev[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      prev.setAll(0, curr);
    }
    return prev[b.length];
  }
}

class _ScoredLib {
  final LibraryTrack lib;
  final double score;
  const _ScoredLib(this.lib, this.score);
}
