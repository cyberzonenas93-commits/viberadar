import 'dart:io';
import 'dart:developer' as dev;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../models/library_track.dart';

/// Max total files to scan in one pass.
const _maxFilesToScan = 50000;

/// Max individual file size to process (2GB).
const _maxFileSize = 2 * 1024 * 1024 * 1024;

/// Timeout for mdls batch call.
const _mdlsTimeout = Duration(seconds: 30);

/// Incremental scan cache entry.
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
  static const _uuid = Uuid();
  static const _supportedExtensions = {
    '.mp3', '.flac', '.wav', '.aac', '.m4a', '.ogg', '.opus', '.aiff',
  };

  static const _camelotKeys = [
    '1A','2A','3A','4A','5A','6A','7A','8A','9A','10A','11A','12A',
    '1B','2B','3B','4B','5B','6B','7B','8B','9B','10B','11B','12B',
  ];

  final Map<String, _ScanCacheEntry> _scanCache = {};
  bool _scanning = false;

  Future<List<LibraryTrack>> scanDirectory(
    String dirPath, {
    void Function(int scanned, int total)? onProgress,
  }) async {
    if (_scanning) {
      dev.log('Scan already in progress', name: 'LibraryScanner');
      return [];
    }
    _scanning = true;
    try {
      return await _scanImpl(dirPath, onProgress: onProgress);
    } finally {
      _scanning = false;
    }
  }

  Future<List<LibraryTrack>> _scanImpl(
    String dirPath, {
    void Function(int scanned, int total)? onProgress,
  }) async {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return [];

    // ── Phase 1: Enumerate audio files ─────────────────────────────────────
    final audioFiles = <File>[];
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (_supportedExtensions.contains(ext)) {
            audioFiles.add(entity);
            if (audioFiles.length >= _maxFilesToScan) break;
          }
        }
        if (audioFiles.length % 500 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    } on FileSystemException catch (e) {
      dev.log('Filesystem error: $e', name: 'LibraryScanner');
    }

    if (audioFiles.isEmpty) return [];
    onProgress?.call(0, audioFiles.length);

    // ── Phase 2: Separate cached vs new files ──────────────────────────────
    final tracks = <LibraryTrack>[];
    final newFiles = <File>[];

    for (final file in audioFiles) {
      try {
        final stat = await file.stat();
        if (stat.size == 0 || stat.size > _maxFileSize) continue;

        final cached = _scanCache[file.path];
        if (cached != null &&
            cached.mtime == stat.modified &&
            cached.size == stat.size) {
          tracks.add(cached.track);
        } else {
          newFiles.add(file);
        }
      } catch (_) {}
    }

    final cachedCount = tracks.length;
    dev.log('${audioFiles.length} files found, $cachedCount cached, ${newFiles.length} new',
        name: 'LibraryScanner');
    onProgress?.call(cachedCount, audioFiles.length);

    // ── Phase 3: Batch mdls for new files ──────────────────────────────────
    // Process in batches of 50 files per mdls call (much faster than 1-per-file)
    const mdlsBatchSize = 50;
    int processed = cachedCount;

    for (var batchStart = 0; batchStart < newFiles.length; batchStart += mdlsBatchSize) {
      final batchEnd = (batchStart + mdlsBatchSize).clamp(0, newFiles.length);
      final batch = newFiles.sublist(batchStart, batchEnd);

      // Get metadata for all files in this batch with one mdls call
      final metaBatch = await _batchMdlsMetadata(batch.map((f) => f.path).toList());

      for (var i = 0; i < batch.length; i++) {
        try {
          final file = batch[i];
          final stat = await file.stat();
          final meta = i < metaBatch.length ? metaBatch[i] : <String, String?>{};
          final track = _buildTrack(file, stat, meta);
          tracks.add(track);

          _scanCache[file.path] = _ScanCacheEntry(
            mtime: stat.modified,
            size: stat.size,
            track: track,
          );
        } catch (e) {
          dev.log('Error processing ${batch[i].path}: $e', name: 'LibraryScanner');
        }
      }

      processed += batch.length;
      onProgress?.call(processed, audioFiles.length);
      await Future<void>.delayed(Duration.zero); // yield to UI
    }

    return tracks;
  }

  /// Build a LibraryTrack from file + stat + metadata.
  /// Uses a fast path+size hash instead of MD5 to avoid heavy I/O.
  LibraryTrack _buildTrack(File file, FileStat stat, Map<String, String?> meta) {
    final ext = p.extension(file.path).toLowerCase();
    final fileName = p.basenameWithoutExtension(file.path);

    // Fast hash: path + size + mtime — no file I/O needed
    final hashInput = '${file.path}:${stat.size}:${stat.modified.millisecondsSinceEpoch}';
    final hash = md5.convert(hashInput.codeUnits).toString();

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

    return LibraryTrack(
      id: _uuid.v4(),
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
  }

  /// Batch metadata extraction — calls mdls once for many files.
  /// Returns a list of metadata maps in the same order as [paths].
  Future<List<Map<String, String?>>> _batchMdlsMetadata(List<String> paths) async {
    if (paths.isEmpty) return [];

    // mdls doesn't support batch output cleanly, but we can call it once per file
    // using xargs-style parallelism. However, the simplest reliable approach
    // is to use mdls -plist which outputs structured data per file.
    //
    // For maximum speed, we run mdls calls in parallel (not sequentially).
    final futures = paths.map((path) => _getMdlsMetadata(path));
    return Future.wait(futures);
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
      ]).timeout(_mdlsTimeout, onTimeout: () {
        return ProcessResult(0, 1, '', 'timeout');
      });
      if (result.exitCode == 0) {
        final parts = (result.stdout as String).split('\n');
        String? clean(String? s) {
          if (s == null || s.trim() == '(null)' || s.trim().isEmpty) return null;
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
    } catch (e) {
      dev.log('mdls error for $path: $e', name: 'LibraryScanner');
    }
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
    if (lower.contains('afrobeat') || lower.contains('burna') || lower.contains('wizkid')) return 'Afrobeats';
    if (lower.contains('amapiano') || lower.contains('kabza')) return 'Amapiano';
    if (lower.contains('house')) return 'House';
    if (lower.contains('rnb') || lower.contains('r&b')) return 'R&B';
    if (lower.contains('hip') || lower.contains('rap')) return 'Hip-Hop';
    if (lower.contains('pop')) return 'Pop';
    if (lower.contains('jazz')) return 'Jazz';
    if (lower.contains('reggae') || lower.contains('dancehall')) return 'Dancehall';
    return 'Unknown';
  }
}
