import '../models/library_track.dart';

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
