import 'dart:async';
import 'package:flutter/foundation.dart';
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

  final Track vibeTrack;
  final MatchStatus status;
  final String? localFilePath;
  final List<String> candidates;
  final double matchScore;
  final String matchMethod;
  final String? preferredCandidate;

  bool get isFound =>
      status == MatchStatus.found || status == MatchStatus.duplicateVersions;
  bool get isFuzzy => status == MatchStatus.fuzzyMatch;
  bool get isMissing => status == MatchStatus.missing;
  bool get isUncertain => status == MatchStatus.uncertain;
}

/// Matches VibeRadar [Track]s against local [LibraryTrack]s.
///
/// Performance: runs in a background isolate via compute().
/// Pre-indexes the library into hash maps for O(1) exact lookups.
/// Fuzzy matching only runs on the subset that didn't get exact hits.
class LocalMatchService {
  // ── public API ────────────────────────────────────────────────────────────

  /// Match a set of tracks against the local library.
  /// Runs entirely in a background isolate — will NOT freeze the UI.
  Future<List<TrackMatch>> matchSet(
    List<Track> setTracks,
    List<LibraryTrack> libraryTracks,
  ) async {
    if (setTracks.isEmpty || libraryTracks.isEmpty) {
      return setTracks
          .map((vt) => TrackMatch(
                vibeTrack: vt,
                status: MatchStatus.missing,
                matchScore: 0.0,
                matchMethod: 'none',
              ))
          .toList();
    }

    // Serialize data for the isolate (can't send complex objects directly)
    final setData = setTracks
        .map((t) => {
              'id': t.id,
              'title': t.title,
              'artist': t.artist,
            })
        .toList();

    final libData = libraryTracks
        .map((l) => {
              'id': l.id,
              'title': l.title,
              'artist': l.artist,
              'fileName': l.fileName,
              'filePath': l.filePath,
              'bitrate': l.bitrate,
              'fileSizeBytes': l.fileSizeBytes,
              'fileExtension': l.fileExtension,
            })
        .toList();

    // Run matching in background isolate
    final results = await compute(_matchInIsolate, {
      'setTracks': setData,
      'library': libData,
    });

    // Reconstruct TrackMatch objects with the original Track references
    return List.generate(setTracks.length, (i) {
      final r = results[i];
      return TrackMatch(
        vibeTrack: setTracks[i],
        status: MatchStatus.values[r['status'] as int],
        localFilePath: r['localFilePath'] as String?,
        candidates: (r['candidates'] as List?)?.cast<String>() ?? const [],
        matchScore: (r['matchScore'] as num).toDouble(),
        matchMethod: r['matchMethod'] as String? ?? '',
        preferredCandidate: r['preferredCandidate'] as String?,
      );
    });
  }
}

// ── Isolate entry point (top-level function) ──────────────────────────────

List<Map<String, dynamic>> _matchInIsolate(Map<String, dynamic> args) {
  final setTracks = args['setTracks'] as List;
  final library = args['library'] as List;

  // ── Step 1: Pre-index the library for O(1) exact lookups ──
  // Key: "normalised_artist||normalised_title"
  final exactIndex = <String, List<Map<String, dynamic>>>{};
  // Key: "normalised_title" (for artist-flexible matches)
  final titleIndex = <String, List<Map<String, dynamic>>>{};
  // Key: stripped title (no remix markers)
  final strippedTitleIndex = <String, List<Map<String, dynamic>>>{};
  // All normalised filenames for filename-based matching
  final filenameIndex = <String, List<Map<String, dynamic>>>{};

  for (final lib in library) {
    final libMap = lib;
    final title = libMap['title'] as String? ?? '';
    final artist = libMap['artist'] as String? ?? '';
    final fileName = libMap['fileName'] as String? ?? '';

    final normTitle = _normalise(title.isNotEmpty ? title : fileName);
    final normArtist = _normalise(artist);
    final normFileName = _normalise(fileName);

    // Cache normalised values on the map for later use
    libMap['_normTitle'] = normTitle;
    libMap['_normArtist'] = normArtist;
    libMap['_normFileName'] = normFileName;
    libMap['_strippedTitle'] = _stripRemixMarkers(normTitle);

    // Index by artist||title
    final exactKey = '$normArtist||$normTitle';
    exactIndex.putIfAbsent(exactKey, () => []).add(libMap);

    // Index by title only
    if (normTitle.isNotEmpty) {
      titleIndex.putIfAbsent(normTitle, () => []).add(libMap);
    }

    // Index by stripped title
    final stripped = libMap['_strippedTitle'] as String;
    if (stripped.length > 3) {
      strippedTitleIndex.putIfAbsent(stripped, () => []).add(libMap);
    }

    // Index by filename
    if (normFileName.isNotEmpty) {
      filenameIndex.putIfAbsent(normFileName, () => []).add(libMap);
    }
  }

  // ── Step 2: Match each set track using the indices ──
  final results = <Map<String, dynamic>>[];

  for (final st in setTracks) {
    final stMap = st as Map<String, dynamic>;
    final queryTitle = _normalise(stMap['title'] as String? ?? '');
    final queryArtist = _normalise(stMap['artist'] as String? ?? '');
    final queryStripped = _stripRemixMarkers(queryTitle);

    // ── Tier 1: Exact match via index (O(1)) ──
    final exactKey = '$queryArtist||$queryTitle';
    final exactHits = exactIndex[exactKey];
    if (exactHits != null && exactHits.isNotEmpty) {
      if (exactHits.length == 1) {
        results.add({
          'status': MatchStatus.found.index,
          'localFilePath': exactHits.first['filePath'],
          'candidates': <String>[],
          'matchScore': 1.0,
          'matchMethod': 'exact',
          'preferredCandidate': null,
        });
        continue;
      } else {
        final preferred = _pickBestFileMap(exactHits);
        results.add({
          'status': MatchStatus.duplicateVersions.index,
          'localFilePath': preferred['filePath'],
          'candidates': exactHits.map((h) => h['filePath'] as String).toList(),
          'matchScore': 1.0,
          'matchMethod': 'exact_duplicate',
          'preferredCandidate': preferred['filePath'],
        });
        continue;
      }
    }

    // ── Tier 1b: Title match with flexible artist (O(1) lookup) ──
    final titleHits = titleIndex[queryTitle];
    if (titleHits != null) {
      final artistFiltered = titleHits
          .where((h) => _artistsMatch(queryArtist, h['_normArtist'] as String))
          .toList();
      if (artistFiltered.length == 1) {
        results.add({
          'status': MatchStatus.found.index,
          'localFilePath': artistFiltered.first['filePath'],
          'candidates': <String>[],
          'matchScore': 1.0,
          'matchMethod': 'exact',
          'preferredCandidate': null,
        });
        continue;
      } else if (artistFiltered.length > 1) {
        final preferred = _pickBestFileMap(artistFiltered);
        results.add({
          'status': MatchStatus.duplicateVersions.index,
          'localFilePath': preferred['filePath'],
          'candidates': artistFiltered.map((h) => h['filePath'] as String).toList(),
          'matchScore': 1.0,
          'matchMethod': 'exact_duplicate',
          'preferredCandidate': preferred['filePath'],
        });
        continue;
      }
    }

    // ── Tier 2: Remix-stripped match (O(1) lookup) ──
    if (queryStripped.length > 3) {
      final strippedHits = strippedTitleIndex[queryStripped];
      if (strippedHits != null) {
        final artistFiltered = strippedHits
            .where((h) => _artistsMatch(queryArtist, h['_normArtist'] as String))
            .toList();
        if (artistFiltered.isNotEmpty) {
          results.add({
            'status': MatchStatus.fuzzyMatch.index,
            'localFilePath': artistFiltered.first['filePath'],
            'candidates': artistFiltered.map((h) => h['filePath'] as String).toList(),
            'matchScore': 0.9,
            'matchMethod': 'remix_stripped',
            'preferredCandidate': null,
          });
          continue;
        }
      }
    }

    // ── Tier 3: Filename contains both artist + title (O(n) but only for misses) ──
    Map<String, dynamic>? filenameHit;
    double filenameScore = 0.0;
    for (final entry in filenameIndex.entries) {
      if (entry.key.contains(queryTitle) && entry.key.contains(queryArtist)) {
        filenameHit = entry.value.first;
        filenameScore = 0.7;
        break;
      }
    }

    // ── Tier 4: Fuzzy Levenshtein (only on title-indexed subset, not full library) ──
    // Only check titles that are similar in length (±3 chars)
    Map<String, dynamic>? fuzzyHit;
    double fuzzyScore = 0.0;
    if (queryTitle.length > 2) {
      for (final entry in titleIndex.entries) {
        final diff = (entry.key.length - queryTitle.length).abs();
        if (diff > 3) continue; // Skip — can't be within Levenshtein 3

        final dist = _levenshtein(queryTitle, entry.key);
        if (dist <= 3) {
          final artistFiltered = entry.value
              .where((h) => _artistsMatch(queryArtist, h['_normArtist'] as String))
              .toList();
          if (artistFiltered.isNotEmpty) {
            final score = 1.0 - (dist / queryTitle.length.clamp(1, 999));
            if (score > fuzzyScore) {
              fuzzyHit = artistFiltered.first;
              fuzzyScore = score.clamp(0.0, 1.0);
            }
          }
        }
      }
    }

    // Return best match found
    if (fuzzyHit != null && fuzzyScore >= (filenameScore + 0.1)) {
      results.add({
        'status': MatchStatus.fuzzyMatch.index,
        'localFilePath': fuzzyHit['filePath'],
        'candidates': <String>[fuzzyHit['filePath'] as String],
        'matchScore': fuzzyScore,
        'matchMethod': 'fuzzy',
        'preferredCandidate': null,
      });
    } else if (filenameHit != null) {
      results.add({
        'status': MatchStatus.uncertain.index,
        'localFilePath': filenameHit['filePath'],
        'candidates': <String>[filenameHit['filePath'] as String],
        'matchScore': filenameScore,
        'matchMethod': 'filename',
        'preferredCandidate': null,
      });
    } else {
      results.add({
        'status': MatchStatus.missing.index,
        'localFilePath': null,
        'candidates': <String>[],
        'matchScore': 0.0,
        'matchMethod': 'none',
        'preferredCandidate': null,
      });
    }
  }

  return results;
}

// ── Top-level helper functions (must be top-level for isolate) ─────────────

Map<String, dynamic> _pickBestFileMap(List<Map<String, dynamic>> candidates) {
  return candidates.reduce((best, current) {
    final cBitrate = current['bitrate'] as int? ?? 0;
    final bBitrate = best['bitrate'] as int? ?? 0;
    if (cBitrate > bBitrate) return current;
    if (cBitrate < bBitrate) return best;
    final cSize = current['fileSizeBytes'] as int? ?? 0;
    final bSize = best['fileSizeBytes'] as int? ?? 0;
    if (cSize > bSize) return current;
    if (cSize < bSize) return best;
    final lossless = {'flac', 'wav', 'aiff'};
    final cExt = (current['fileExtension'] as String? ?? '').toLowerCase();
    final bExt = (best['fileExtension'] as String? ?? '').toLowerCase();
    if (lossless.contains(cExt) && !lossless.contains(bExt)) return current;
    return best;
  });
}

bool _artistsMatch(String queryArtist, String libArtist) {
  if (queryArtist.isEmpty || libArtist.isEmpty) return true;
  return libArtist.contains(queryArtist) || queryArtist.contains(libArtist);
}

// Pre-compiled regex patterns (created once, reused)
final _featRegex = RegExp(r'\(feat[^)]*\)', caseSensitive: false);
final _ftRegex = RegExp(r'\(ft[^)]*\)', caseSensitive: false);
final _remixParenRegex = RegExp(r'\(remix[^)]*\)', caseSensitive: false);
final _origParenRegex = RegExp(r'\(original[^)]*\)', caseSensitive: false);
final _radioParenRegex = RegExp(r'\(radio[^)]*\)', caseSensitive: false);
final _bracketRegex = RegExp(r'\[.*?\]');
final _extRegex = RegExp(r'\.(mp3|flac|wav|aac|m4a|ogg|aiff)$');
final _nonAlphaRegex = RegExp(r'[^a-z0-9 ]');
final _multiSpaceRegex = RegExp(r'\s+');
final _remixWordRegex = RegExp(
    r'\b(remix|edit|version|mix|extended|radio|original|instrumental|acoustic|live|clean|explicit|remaster)\b');

String _normalise(String input) {
  var s = input.toLowerCase();
  s = s.replaceAll(_featRegex, '');
  s = s.replaceAll(_ftRegex, '');
  s = s.replaceAll(_remixParenRegex, '');
  s = s.replaceAll(_origParenRegex, '');
  s = s.replaceAll(_radioParenRegex, '');
  s = s.replaceAll(_bracketRegex, '');
  s = s.replaceAll(_extRegex, '');
  s = s.replaceAll(_nonAlphaRegex, ' ');
  return s.trim().replaceAll(_multiSpaceRegex, ' ');
}

String _stripRemixMarkers(String normalised) {
  return normalised
      .replaceAll(_remixWordRegex, '')
      .replaceAll(_multiSpaceRegex, ' ')
      .trim();
}

int _levenshtein(String a, String b, {int maxDist = 4}) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length.clamp(0, maxDist);
  if (b.isEmpty) return a.length.clamp(0, maxDist);
  if ((a.length - b.length).abs() > maxDist) return maxDist + 1;

  final prev = List<int>.generate(b.length + 1, (i) => i);
  final curr = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    curr[0] = i;
    var rowMin = i; // Track min in row for early exit
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      final val = [
        curr[j - 1] + 1,
        prev[j] + 1,
        prev[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
      curr[j] = val;
      if (val < rowMin) rowMin = val;
    }
    // Early exit: if every cell in this row exceeds threshold, no point continuing
    if (rowMin > maxDist) return maxDist + 1;
    prev.setAll(0, curr);
  }
  return prev[b.length];
}
