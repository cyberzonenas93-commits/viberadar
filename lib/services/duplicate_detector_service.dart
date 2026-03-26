import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/library_track.dart';

/// Result of a batch cleanup operation.
class CleanupResult {
  const CleanupResult({
    required this.movedCount,
    required this.skippedCount,
    required this.errors,
  });
  final int movedCount;
  final int skippedCount;
  final List<String> errors;

  String get summary =>
      '$movedCount moved, $skippedCount skipped'
      '${errors.isNotEmpty ? ', ${errors.length} errors' : ''}';
}

class DuplicateDetectorService {
  List<DuplicateGroup> findDuplicates(List<LibraryTrack> tracks) {
    final groups = <DuplicateGroup>[];
    final used = <String>{};

    // 1. Exact hash duplicates
    final byHash = <String, List<LibraryTrack>>{};
    for (final t in tracks) {
      byHash.putIfAbsent(t.md5Hash, () => []).add(t);
    }
    for (final entry in byHash.entries) {
      if (entry.value.length > 1) {
        groups.add(DuplicateGroup(tracks: entry.value, reason: 'exact_hash'));
        used.addAll(entry.value.map((t) => t.id));
      }
    }

    // 2. Same title + artist
    final byTitleArtist = <String, List<LibraryTrack>>{};
    for (final t in tracks) {
      if (used.contains(t.id)) continue;
      final key = '${_normalize(t.title)}||${_normalize(t.artist)}';
      byTitleArtist.putIfAbsent(key, () => []).add(t);
    }
    for (final entry in byTitleArtist.entries) {
      if (entry.value.length > 1) {
        groups.add(DuplicateGroup(tracks: entry.value, reason: 'same_title_artist'));
        used.addAll(entry.value.map((t) => t.id));
      }
    }

    // 3. Similar filenames (Levenshtein <= 4)
    final remaining = tracks.where((t) => !used.contains(t.id)).toList();
    final paired = <String>{};
    for (var i = 0; i < remaining.length; i++) {
      final group = [remaining[i]];
      for (var j = i + 1; j < remaining.length; j++) {
        if (paired.contains(remaining[j].id)) continue;
        final dist = _levenshtein(
          _normalize(remaining[i].fileName),
          _normalize(remaining[j].fileName),
        );
        if (dist <= 4) {
          group.add(remaining[j]);
          paired.add(remaining[j].id);
        }
      }
      if (group.length > 1) {
        groups.add(DuplicateGroup(tracks: group, reason: 'similar_name'));
        paired.add(remaining[i].id);
      }
    }

    return groups;
  }

  /// Move duplicate files (excluding the recommended keeper) to the macOS Trash.
  /// Never deletes files — always moves to Trash for safety.
  /// Returns a [CleanupResult] with counts and errors.
  Future<CleanupResult> trashDuplicates(
    DuplicateGroup group, {
    LibraryTrack? keepFile,
  }) async {
    final keeper = keepFile ?? group.recommended;
    if (keeper == null) {
      return const CleanupResult(movedCount: 0, skippedCount: 0, errors: ['No keeper selected']);
    }

    int moved = 0;
    int skipped = 0;
    final errors = <String>[];

    for (final t in group.tracks) {
      if (t.id == keeper.id) continue; // keep this one

      try {
        final file = File(t.filePath);
        if (!file.existsSync()) {
          skipped++;
          continue;
        }
        // Move to macOS Trash via rename to ~/.Trash/
        final trashPath = p.join(
          Platform.environment['HOME'] ?? '/tmp',
          '.Trash',
          p.basename(t.filePath),
        );
        await file.rename(trashPath);
        moved++;
      } catch (e) {
        errors.add('${t.fileName}: $e');
        skipped++;
      }
    }

    return CleanupResult(movedCount: moved, skippedCount: skipped, errors: errors);
  }

  /// Move duplicate files to a review folder instead of Trash.
  /// Safer than trashing — user can review before permanent deletion.
  Future<CleanupResult> moveDuplicatesToReview(
    DuplicateGroup group, {
    required String reviewFolderPath,
    LibraryTrack? keepFile,
  }) async {
    final keeper = keepFile ?? group.recommended;
    if (keeper == null) {
      return const CleanupResult(movedCount: 0, skippedCount: 0, errors: ['No keeper selected']);
    }

    final reviewDir = Directory(reviewFolderPath);
    await reviewDir.create(recursive: true);

    int moved = 0;
    int skipped = 0;
    final errors = <String>[];

    for (final t in group.tracks) {
      if (t.id == keeper.id) continue;

      try {
        final file = File(t.filePath);
        if (!file.existsSync()) {
          skipped++;
          continue;
        }
        final destPath = p.join(reviewFolderPath, p.basename(t.filePath));
        await file.rename(destPath);
        moved++;
      } catch (e) {
        errors.add('${t.fileName}: $e');
        skipped++;
      }
    }

    return CleanupResult(movedCount: moved, skippedCount: skipped, errors: errors);
  }

  /// Batch cleanup: process multiple groups at once.
  /// Only processes groups above the [minConfidence] threshold.
  /// For each group, keeps the recommended file and moves others.
  Future<CleanupResult> batchCleanup(
    List<DuplicateGroup> groups, {
    double minConfidence = 0.85,
    String? reviewFolderPath,
  }) async {
    int totalMoved = 0;
    int totalSkipped = 0;
    final allErrors = <String>[];

    for (final group in groups) {
      if (group.confidence < minConfidence) continue;

      final result = reviewFolderPath != null
          ? await moveDuplicatesToReview(group, reviewFolderPath: reviewFolderPath)
          : await trashDuplicates(group);

      totalMoved += result.movedCount;
      totalSkipped += result.skippedCount;
      allErrors.addAll(result.errors);
    }

    return CleanupResult(
      movedCount: totalMoved,
      skippedCount: totalSkipped,
      errors: allErrors,
    );
  }

  /// Compare two files and return a quality comparison map.
  Map<String, String> compareQuality(LibraryTrack a, LibraryTrack b) {
    return {
      'bitrate': '${a.bitrate} vs ${b.bitrate} kbps',
      'size': '${a.fileSizeFormatted} vs ${b.fileSizeFormatted}',
      'format': '${a.fileExtension} vs ${b.fileExtension}',
      'metadata': '${_metaScore(a)} vs ${_metaScore(b)} fields',
      'recommended': _metaScore(a) >= _metaScore(b) ? a.fileName : b.fileName,
    };
  }

  int _metaScore(LibraryTrack t) {
    int score = 0;
    if (t.title.isNotEmpty) score++;
    if (t.artist.isNotEmpty) score++;
    if (t.album.isNotEmpty) score++;
    if (t.genre.isNotEmpty) score++;
    if (t.year != null && t.year! > 0) score++;
    if (t.bpm > 0) score++;
    if (t.key.isNotEmpty) score++;
    return score;
  }

  String _normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final dp = List.generate(
      a.length + 1,
      (i) => List.generate(b.length + 1, (j) => 0),
    );
    for (var i = 0; i <= a.length; i++) { dp[i][0] = i; }
    for (var j = 0; j <= b.length; j++) { dp[0][j] = j; }
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        dp[i][j] = a[i - 1] == b[j - 1]
            ? dp[i - 1][j - 1]
            : 1 + [dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]]
                .reduce((x, y) => x < y ? x : y);
      }
    }
    return dp[a.length][b.length];
  }
}
