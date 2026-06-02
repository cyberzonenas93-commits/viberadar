import 'dart:io';
import 'dart:developer' as dev;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../core/utils/concurrency_limiter.dart';
import '../models/library_track.dart';

/// Max total files to scan in one pass.
const _maxFilesToScan = 50000;

/// Max individual file size to process (2GB).
const _maxFileSize = 2 * 1024 * 1024 * 1024;

/// Timeout for mdls batch call.
const _mdlsTimeout = Duration(seconds: 30);

/// Max concurrent `mdls` subprocesses when extracting metadata for a batch
/// of audio files. Unbounded parallelism here (one subprocess per file over
/// batches of 50) can exhaust OS file-descriptor / process limits on large
/// libraries. File I/O is cheap relative to external-API work, so we keep
/// this higher than the cue-analysis budget of 4.
const int _scanConcurrency = 8;

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
  static const _supportedExtensions = {
    '.mp3', '.flac', '.wav', '.aac', '.m4a', '.ogg', '.opus', '.aiff',
  };

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
      } catch (e, st) {
        dev.log('Failed to stat file during scan: ${file.path}', name: 'LibraryScanner', error: e, stackTrace: st);
      }
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

    // Stable hash: path + size only — dropping mtime keeps the ID consistent
    // across rescans as long as the file hasn't been replaced with a different
    // sized file, covering the vast majority of real-world DJ library cases.
    final hashInput = '${file.path}:${stat.size}';
    final hash = md5.convert(hashInput.codeUnits).toString();

    final title = meta['title'] ?? _parseTitleFromName(fileName);
    final artist = meta['artist'] ?? _parseArtistFromName(fileName);
    // Never fabricate analysis fields. BPM and key come from the file's real
    // tags (via mdls) when present; otherwise they are left as the app-wide
    // "unknown" sentinels (0 / empty string), which the UI renders as "—".
    // macOS rarely tags BPM/key, so most files legitimately show no value
    // rather than an invented one. Likewise bitrate is 0 ("unknown") when the
    // file carries no bitrate tag, instead of assuming 320 kbps.
    final realBpm = double.tryParse(meta['bpm'] ?? '') ?? 0.0;
    final double bpm = realBpm > 0 ? realBpm.clamp(60.0, 200.0).toDouble() : 0.0;
    final key = meta['key'] ?? '';
    final duration = double.tryParse(meta['duration'] ?? '') ?? 0.0;
    // mdls reports bitrate in bits/sec (e.g. 320000); store kbps.
    final rawBitrate = int.tryParse(meta['bitrate'] ?? '') ?? 0;
    final bitrate = rawBitrate > 10000 ? rawBitrate ~/ 1000 : rawBitrate;
    final sampleRate = int.tryParse(meta['sampleRate'] ?? '') ?? 44100;
    final year = meta['year'] != null ? int.tryParse(meta['year']!) : null;

    return LibraryTrack(
      id: hash,
      filePath: file.path,
      fileName: p.basename(file.path),
      title: title.isNotEmpty ? title : fileName,
      artist: artist.isNotEmpty ? artist : 'Unknown Artist',
      album: meta['album'] ?? 'Unknown Album',
      genre: meta['genre'] ?? _guessGenre(fileName),
      bpm: bpm,
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
    // Parallelism is bounded by [_scanConcurrency] to avoid spawning 50
    // simultaneous `mdls` subprocesses per batch, which on large libraries
    // can hit the OS file-descriptor ceiling.
    return runLimited<Map<String, String?>>(
      paths.map((path) => () => _getMdlsMetadata(path)),
      maxConcurrent: _scanConcurrency,
    );
  }

  Future<Map<String, String?>> _getMdlsMetadata(String path) async {
    try {
      final result = await Process.run('mdls', [
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
        // Parse mdls' default "key = value" output BY KEY (not by position).
        // Positional parsing of `-raw` output is fragile: null fields and the
        // array-valued kMDItemAuthors shift every later field into the wrong
        // slot (e.g. the duration value landing in the BPM column). Matching
        // each attribute name explicitly is robust to missing/array values.
        final out = result.stdout as String;
        String? attr(String key) {
          final m = RegExp('^$key\\s*=\\s*(.*?)\\s*\$', multiLine: true)
              .firstMatch(out);
          if (m == null) return null;
          var v = m.group(1)!.trim();
          if (v.isEmpty || v == '(null)') return null;
          if (v == '(') {
            // Array form, e.g. kMDItemAuthors = (\n  "Name"\n). Take first item.
            final arr =
                RegExp('$key\\s*=\\s*\\(\\s*"([^"]*)"').firstMatch(out);
            return arr?.group(1)?.trim();
          }
          if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
            v = v.substring(1, v.length - 1);
          }
          return v.trim().isEmpty ? null : v.trim();
        }

        return {
          'title': attr('kMDItemTitle'),
          'artist': attr('kMDItemAuthors'),
          'album': attr('kMDItemAlbum'),
          'genre': attr('kMDItemMusicalGenre'),
          'bpm': attr('kMDItemTempo'),
          'key': attr('kMDItemMusicalKey'),
          'duration': attr('kMDItemDurationSeconds'),
          'bitrate': attr('kMDItemAudioBitRate'),
          'sampleRate': attr('kMDItemAudioSampleRate'),
          'year': attr('kMDItemRecordingYear'),
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
