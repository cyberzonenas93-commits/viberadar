import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../models/library_track.dart';

/// Incremental scan cache entry — stores file identity so we can skip
/// re-hashing files that haven't changed between scans.
class _ScanCacheEntry {
  const _ScanCacheEntry({
    required this.mtime,
    required this.size,
    required this.track,
  });
  final DateTime mtime;
  final int size;
  final LibraryTrack track;
}

class LibraryScannerService {
  static const _supportedExtensions = {
    '.mp3', '.flac', '.wav', '.aac', '.m4a', '.ogg', '.opus', '.aiff',
  };

  static const _camelotKeys = [
    '1A','2A','3A','4A','5A','6A','7A','8A','9A','10A','11A','12A',
    '1B','2B','3B','4B','5B','6B','7B','8B','9B','10B','11B','12B',
  ];

  /// In-memory incremental cache keyed by absolute file path.
  /// Survives for the lifetime of the service instance (i.e. the app session).
  /// Tracks that haven't changed (same mtime + size) skip MD5 computation.
  final Map<String, _ScanCacheEntry> _scanCache = {};

  Future<List<LibraryTrack>> scanDirectory(
    String dirPath, {
    void Function(int scanned, int total)? onProgress,
  }) async {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return [];

    final audioFiles = <File>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        if (_supportedExtensions.contains(ext)) {
          audioFiles.add(entity);
        }
      }
    }

    final tracks = <LibraryTrack>[];
    for (var i = 0; i < audioFiles.length; i++) {
      onProgress?.call(i + 1, audioFiles.length);
      try {
        final track = await _processFile(audioFiles[i]);
        if (track != null) tracks.add(track);
      } catch (_) {}
    }
    return tracks;
  }

  Future<LibraryTrack?> _processFile(File file) async {
    final stat = await file.stat();

    // ── Incremental cache check ───────────────────────────────────────────
    // If this file's mtime and size match what we saw last time, reuse the
    // cached LibraryTrack and skip expensive MD5 hashing + mdls calls.
    final cached = _scanCache[file.path];
    if (cached != null &&
        cached.mtime == stat.modified &&
        cached.size == stat.size) {
      return cached.track;
    }

    final ext = p.extension(file.path).toLowerCase();
    final fileName = p.basenameWithoutExtension(file.path);
    final meta = await _getMdlsMetadata(file.path);

    // MD5 only for new/changed files
    final bytes = await file.readAsBytes();
    final hash = md5.convert(bytes).toString();

    final title = meta['title'] ?? _parseTitleFromName(fileName);
    final artist = meta['artist'] ?? _parseArtistFromName(fileName);
    final bpm = meta['bpm'] != null
        ? (double.tryParse(meta['bpm']!) ?? _simulateBpm(fileName))
        : _simulateBpm(fileName);
    final key = meta['key'] ?? _simulateKey(hash);
    final duration = meta['duration'] != null
        ? (double.tryParse(meta['duration']!) ?? 0.0)
        : 0.0;
    final bitrate = meta['bitrate'] != null
        ? (int.tryParse(meta['bitrate']!) ?? 320)
        : (ext == '.flac' ? 0 : 320);
    final sampleRate = meta['sampleRate'] != null
        ? (int.tryParse(meta['sampleRate']!) ?? 44100)
        : 44100;
    final year = meta['year'] != null ? int.tryParse(meta['year']!) : null;

    final track = LibraryTrack(
      id: hash,
      filePath: file.path,
      fileName: p.basename(file.path),
      title: title.isNotEmpty ? title : fileName,
      artist: artist.isNotEmpty ? artist : 'Unknown Artist',
      album: meta['album'] ?? 'Unknown Album',
      genre: meta['genre'] ?? _guessGenre(fileName),
      bpm: bpm.clamp(60, 200),
      key: key,
      durationSeconds: duration,
      fileSizeBytes: stat.size,
      fileExtension: ext,
      md5Hash: hash,
      bitrate: bitrate,
      sampleRate: sampleRate,
      year: year,
    );

    // Store in incremental cache for future scans
    _scanCache[file.path] = _ScanCacheEntry(
      mtime: stat.modified,
      size: stat.size,
      track: track,
    );

    return track;
  }

  Future<Map<String, String?>> _getMdlsMetadata(String path) async {
    try {
      final result = await Process.run('mdls', [
        '-raw',
        '-name', 'kMDItemTitle',
        '-name', 'kMDItemAuthors',
        '-name', 'kMDItemAlbum',
        '-name', 'kMDItemMusicalGenre',
        '-name', 'kMDItemTempo',
        '-name', 'kMDItemMusicalKey',
        '-name', 'kMDItemDurationSeconds',
        '-name', 'kMDItemAudioBitRate',
        '-name', 'kMDItemAudioSampleRate',
        '-name', 'kMDItemRecordingYear',
        path,
      ]);
      if (result.exitCode == 0) {
        final parts = (result.stdout as String).split('\n');
        String? clean(String? s) {
          if (s == null || s.trim() == '(null)' || s.trim().isEmpty) {
            return null;
          }
          return s.trim().replaceAll(RegExp(r'^["\(]|["\)]$'), '').trim();
        }
        return {
          'title': clean(parts.isNotEmpty ? parts[0] : null),
          'artist': clean(parts.length > 1
              ? parts[1].replaceAll(RegExp(r'[\(\)"\\]'), '').split(',').first
              : null),
          'album': clean(parts.length > 2 ? parts[2] : null),
          'genre': clean(parts.length > 3 ? parts[3] : null),
          'bpm': clean(parts.length > 4 ? parts[4] : null),
          'key': clean(parts.length > 5 ? parts[5] : null),
          'duration': clean(parts.length > 6 ? parts[6] : null),
          'bitrate': clean(parts.length > 7 ? parts[7] : null),
          'sampleRate': clean(parts.length > 8 ? parts[8] : null),
          'year': clean(parts.length > 9 ? parts[9] : null),
        };
      }
    } catch (_) {}
    return {};
  }

  String _parseTitleFromName(String name) {
    final match = RegExp(r'^.+\s+-\s+(.+)$').firstMatch(name);
    if (match != null) return match.group(1)?.trim() ?? name;
    return name.replaceAll(RegExp(r'^\d+[\s._-]+'), '').trim();
  }

  String _parseArtistFromName(String name) {
    final match = RegExp(r'^(.+?)\s+-\s+.+$').firstMatch(name);
    return match?.group(1)?.trim() ?? '';
  }

  double _simulateBpm(String seed) {
    final h = seed.codeUnits.fold(0, (a, b) => a + b);
    return 80.0 + (h % 80);
  }

  String _simulateKey(String hash) {
    final idx =
        hash.codeUnits.take(4).fold(0, (a, b) => a + b) % _camelotKeys.length;
    return _camelotKeys[idx];
  }

  String _guessGenre(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('afrobeat') ||
        lower.contains('burna') ||
        lower.contains('wizkid')) {
      return 'Afrobeats';
    }
    if (lower.contains('amapiano') || lower.contains('kabza')) {
      return 'Amapiano';
    }
    if (lower.contains('house')) { return 'House'; }
    if (lower.contains('rnb') || lower.contains('r&b')) { return 'R&B'; }
    return 'Unknown';
  }
}
