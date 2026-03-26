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

  /// Matched via artist-title inversion or filename heuristics — lower confidence.
  uncertain,
}

class TrackMatch {
  const TrackMatch({
    required this.vibeTrack,
    required this.status,
    this.localFilePath,
    this.candidates = const [],
    required this.matchScore,
    this.matchMethod = '',
    this.preferredCandidate,
  });

  /// The VibeRadar [Track] being matched.
  final Track vibeTrack;

  final MatchStatus status;

  /// Path of the best-matching local file (null when [status] == missing).
  final String? localFilePath;

  /// All candidate file paths (populated for fuzzyMatch / duplicateVersions / uncertain).
  final List<String> candidates;

  /// Confidence 0.0–1.0 (1.0 = exact match).
  final double matchScore;

  /// How the match was found (e.g. 'exact', 'fuzzy', 'inverted', 'filename', 'remix').
  final String matchMethod;

  /// Preferred candidate among duplicates (highest quality file).
  final String? preferredCandidate;

  bool get isFound =>
      status == MatchStatus.found || status == MatchStatus.duplicateVersions;
  bool get isFuzzy => status == MatchStatus.fuzzyMatch;
  bool get isMissing => status == MatchStatus.missing;
  bool get isUncertain => status == MatchStatus.uncertain;
}

/// Matches a list of VibeRadar [Track]s against the local [LibraryTrack]
/// catalogue already loaded by [LibraryScannerService].
///
/// Matching tiers (in priority order)
/// ─────────────────────────────────────────────────────────────
/// 1. Exact        artist + title both match exactly (normalised)
/// 2. Inverted     title contains artist or vice versa (filename patterns)
/// 3. Remix/Edit   stripped remix markers match
/// 4. Fuzzy        Levenshtein distance ≤ 3 on normalised title + same artist
/// 5. Filename     filename-only heuristic (no metadata)
/// 6. Missing      no match found
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
    final invertedMatches = <LibraryTrack>[];
    final remixMatches = <_ScoredLib>[];
    final fuzzyMatches = <_ScoredLib>[];
    final filenameMatches = <_ScoredLib>[];

    final queryTitleStripped = _stripRemixMarkers(queryTitle);

    for (final lib in library) {
      final libTitle = _normalise(lib.title.isNotEmpty ? lib.title : lib.fileName);
      final libArtist = _normalise(lib.artist);

      // ── Tier 1: Exact artist+title ──
      final artistMatch = _artistsMatch(queryArtist, libArtist);
      if (artistMatch && libTitle == queryTitle) {
        exactMatches.add(lib);
        continue;
      }

      // ── Tier 2: Inverted match (title and artist swapped, common in filenames) ──
      if (artistMatch) {
        // Check if query title appears in lib artist or vice versa
        if (libArtist.isNotEmpty && libArtist.contains(queryTitle) ||
            queryTitle.contains(libArtist) && libTitle.contains(queryArtist)) {
          invertedMatches.add(lib);
          continue;
        }
      }

      // ── Tier 3: Remix/Edit stripped match ──
      if (artistMatch) {
        final libTitleStripped = _stripRemixMarkers(libTitle);
        if (libTitleStripped == queryTitleStripped && libTitleStripped.length > 3) {
          final score = libTitle == queryTitle ? 1.0 : 0.9;
          remixMatches.add(_ScoredLib(lib, score));
          continue;
        }
      }

      // ── Tier 4: Fuzzy Levenshtein ──
      if (artistMatch) {
        final dist = _levenshtein(queryTitle, libTitle);
        if (dist <= 3) {
          final score = 1.0 - (dist / (queryTitle.length.clamp(1, 999)));
          fuzzyMatches.add(_ScoredLib(lib, score.clamp(0.0, 1.0)));
          continue;
        }
      }

      // ── Tier 5: Filename heuristic (no metadata match) ──
      final libFileName = _normalise(lib.fileName);
      if (libFileName.contains(queryTitle) && libFileName.contains(queryArtist)) {
        filenameMatches.add(_ScoredLib(lib, 0.7));
      } else if (libFileName.contains(queryTitle) && queryTitle.length > 5) {
        filenameMatches.add(_ScoredLib(lib, 0.5));
      }
    }

    // ── Return results in priority order ──

    if (exactMatches.length == 1) {
      return TrackMatch(
        vibeTrack: vt,
        status: MatchStatus.found,
        localFilePath: exactMatches.first.filePath,
        matchScore: 1.0,
        matchMethod: 'exact',
      );
    }

    if (exactMatches.length > 1) {
      final preferred = _pickBestFile(exactMatches);
      return TrackMatch(
        vibeTrack: vt,
        status: MatchStatus.duplicateVersions,
        localFilePath: preferred.filePath,
        candidates: exactMatches.map((l) => l.filePath).toList(),
        matchScore: 1.0,
        matchMethod: 'exact_duplicate',
        preferredCandidate: preferred.filePath,
      );
    }

    if (remixMatches.isNotEmpty) {
      remixMatches.sort((a, b) => b.score.compareTo(a.score));
      return TrackMatch(
        vibeTrack: vt,
        status: MatchStatus.fuzzyMatch,
        localFilePath: remixMatches.first.lib.filePath,
        candidates: remixMatches.map((s) => s.lib.filePath).toList(),
        matchScore: remixMatches.first.score,
        matchMethod: 'remix_stripped',
      );
    }

    if (invertedMatches.isNotEmpty) {
      return TrackMatch(
        vibeTrack: vt,
        status: MatchStatus.uncertain,
        localFilePath: invertedMatches.first.filePath,
        candidates: invertedMatches.map((l) => l.filePath).toList(),
        matchScore: 0.7,
        matchMethod: 'inverted',
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
        matchMethod: 'fuzzy',
      );
    }

    if (filenameMatches.isNotEmpty) {
      filenameMatches.sort((a, b) => b.score.compareTo(a.score));
      return TrackMatch(
        vibeTrack: vt,
        status: MatchStatus.uncertain,
        localFilePath: filenameMatches.first.lib.filePath,
        candidates: filenameMatches.map((s) => s.lib.filePath).toList(),
        matchScore: filenameMatches.first.score,
        matchMethod: 'filename',
      );
    }

    return TrackMatch(
      vibeTrack: vt,
      status: MatchStatus.missing,
      matchScore: 0.0,
      matchMethod: 'none',
    );
  }

  /// Check if two normalised artist strings match (substring or exact).
  bool _artistsMatch(String queryArtist, String libArtist) {
    if (queryArtist.isEmpty || libArtist.isEmpty) return true;
    return libArtist.contains(queryArtist) ||
        queryArtist.contains(libArtist);
  }

  /// Among duplicate files, pick the one with best quality.
  LibraryTrack _pickBestFile(List<LibraryTrack> candidates) {
    return candidates.reduce((best, current) {
      // Prefer highest bitrate
      if (current.bitrate > best.bitrate) return current;
      if (current.bitrate < best.bitrate) return best;
      // Prefer largest file
      if (current.fileSizeBytes > best.fileSizeBytes) return current;
      if (current.fileSizeBytes < best.fileSizeBytes) return best;
      // Prefer FLAC/WAV over MP3
      final lossless = {'flac', 'wav', 'aiff'};
      if (lossless.contains(current.fileExtension.toLowerCase()) &&
          !lossless.contains(best.fileExtension.toLowerCase())) return current;
      return best;
    });
  }

  /// Strip remix/edit markers for comparison (e.g. "song radio edit" → "song").
  String _stripRemixMarkers(String normalised) {
    return normalised
        .replaceAll(RegExp(r'\b(remix|edit|version|mix|extended|radio|original|instrumental|acoustic|live|clean|explicit|remaster)\b'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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
