import 'dart:convert';
import 'dart:io';
import 'dart:developer' as dev;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../models/library_track.dart';

/// Max total files to scan in one pass.
const _maxFilesToScan = 50000;

// ── Pure-Dart embedded tag BPM reader ─────────────────────────────────────────

class _TagReader {
  /// Returns BPM from embedded tags in the first 256KB of the file.
  static Future<double?> readBpm(String filePath, String ext) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;
      final raf = await file.open();
      final bytes = await raf.read(262144); // 256KB
      await raf.close();

      switch (ext) {
        case '.mp3':
        case '.aiff':
          return _id3v2Bpm(bytes) ?? _id3v1Bpm(bytes);
        case '.flac':
        case '.ogg':
        case '.opus':
          return _vorbisCommentBpm(bytes);
        case '.m4a':
        case '.aac':
          return _itunesBpm(bytes);
        default:
          return _id3v2Bpm(bytes); // try anyway
      }
    } catch (_) {
      return null;
    }
  }

  /// ID3v2.3 / ID3v2.4: TBPM frame
  static double? _id3v2Bpm(Uint8List b) {
    if (b.length < 10) return null;
    if (b[0] != 0x49 || b[1] != 0x44 || b[2] != 0x33) return null; // "ID3"
    final version = b[3]; // 3 = v2.3, 4 = v2.4, 2 = v2.2

    // Syncsafe size
    final tagSize = ((b[6] & 0x7F) << 21) | ((b[7] & 0x7F) << 14) |
                    ((b[8] & 0x7F) << 7)  |  (b[9] & 0x7F);

    int pos = 10;
    final end = (10 + tagSize).clamp(0, b.length);

    while (pos < end - 10) {
      int frameSize;
      int headerSize;
      String frameId;

      if (version <= 2) {
        // ID3v2.2: 3-char frame ID, 3-byte size
        if (pos + 6 > end) break;
        frameId = String.fromCharCodes(b.sublist(pos, pos + 3));
        frameSize = (b[pos+3] << 16) | (b[pos+4] << 8) | b[pos+5];
        headerSize = 6;
      } else {
        // ID3v2.3 / v2.4: 4-char frame ID, 4-byte size
        if (pos + 10 > end) break;
        frameId = String.fromCharCodes(b.sublist(pos, pos + 4));
        if (version == 4) {
          // v2.4 uses syncsafe sizes for frames
          frameSize = ((b[pos+4] & 0x7F) << 21) | ((b[pos+5] & 0x7F) << 14) |
                      ((b[pos+6] & 0x7F) << 7)  |  (b[pos+7] & 0x7F);
        } else {
          frameSize = (b[pos+4] << 24) | (b[pos+5] << 16) |
                      (b[pos+6] << 8)  |  b[pos+7];
        }
        headerSize = 10;
      }

      if (frameSize <= 0 || frameSize > 65536) break;
      if (frameId.codeUnits.any((c) => c == 0)) break; // padding

      // TBPM (v2.3+) or TBP (v2.2)
      if (frameId == 'TBPM' || frameId == 'TBP') {
        final dataStart = pos + headerSize + 1; // skip encoding byte
        final dataEnd = (pos + headerSize + frameSize).clamp(0, b.length);
        if (dataStart < dataEnd) {
          final text = String.fromCharCodes(
            b.sublist(dataStart, dataEnd).where((c) => c > 0 && c < 128),
          ).trim();
          if (text.isNotEmpty) {
            final val = double.tryParse(text.split('.').first);
            if (val != null && val > 0 && val < 400) return val;
          }
        }
      }

      pos += headerSize + frameSize;
    }
    return null;
  }

  /// ID3v1: bytes 125-127 at end of file — ID3v1 doesn't store BPM, skip.
  static double? _id3v1Bpm(Uint8List b) => null;

  /// Vorbis comment (FLAC, OGG, Opus): look for BPM= or TEMPO= comment
  static double? _vorbisCommentBpm(Uint8List b) {
    // Convert bytes to Latin-1 string for searching comment field names
    // Vorbis comments are always ASCII for field names
    // Search for BPM= or TEMPO= (case-insensitive) in raw bytes
    final upper = String.fromCharCodes(
        b.map((byte) => byte >= 0x61 && byte <= 0x7A ? byte - 32 : byte));
    for (final key in ['BPM=', 'TEMPO=', 'BEATSPERMINUTE=']) {
      final idx = upper.indexOf(key);
      if (idx >= 0) {
        final start = idx + key.length;
        final end = upper.indexOf('\x00', start);
        final valueStr = (end > 0
                ? upper.substring(start, end)
                : upper.substring(start, (start + 10).clamp(0, upper.length)))
            .trim();
        final val = double.tryParse(valueStr.split('.').first);
        if (val != null && val > 0 && val < 400) return val;
      }
    }
    return null;
  }

  /// iTunes MP4 atoms: tmpo atom stores BPM as a 16-bit integer
  static double? _itunesBpm(Uint8List b) {
    // Search for the 'tmpo' FourCC in the file bytes
    for (int i = 0; i < b.length - 18; i++) {
      if (b[i] == 0x74 && b[i+1] == 0x6D && b[i+2] == 0x70 && b[i+3] == 0x6F) {
        // Found 'tmpo' — BPM is a 16-bit value after:
        // atom size (4) + 'tmpo' (4) + data atom header (~8) + type flags (4) + locale (4)
        // Try several offsets as the exact structure can vary
        for (final offset in [16, 20, 24]) {
          if (i + offset + 2 <= b.length) {
            final bpm = (b[i + offset] << 8) | b[i + offset + 1];
            if (bpm > 0 && bpm < 400) return bpm.toDouble();
          }
        }
      }
    }
    return null;
  }
}

/// Max individual file size to process (2GB).
const _maxFileSize = 2 * 1024 * 1024 * 1024;

/// Timeout for metadata tool calls.
const _metaTimeout = Duration(seconds: 15);

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
    // Video files (also contain audio metadata — BPM, key, duration)
    '.mp4', '.mov', '.m4v',
  };

  static const _camelotKeys = [
    '1A','2A','3A','4A','5A','6A','7A','8A','9A','10A','11A','12A',
    '1B','2B','3B','4B','5B','6B','7B','8B','9B','10B','11B','12B',
  ];

  final Map<String, _ScanCacheEntry> _scanCache = {};
  bool _scanning = false;

  // Cache whether ffprobe is available so we only check once.
  bool? _ffprobeAvailable;

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

    // ── Phase 1b: Check ffprobe availability once ───────────────────────────
    _ffprobeAvailable ??= await _checkFfprobe();
    dev.log('ffprobe available: $_ffprobeAvailable', name: 'LibraryScanner');

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

    // ── Phase 3: Batch metadata for new files ──────────────────────────────
    const batchSize = 50;
    int processed = cachedCount;

    for (var batchStart = 0; batchStart < newFiles.length; batchStart += batchSize) {
      final batchEnd = (batchStart + batchSize).clamp(0, newFiles.length);
      final batch = newFiles.sublist(batchStart, batchEnd);

      final metaBatch = await _batchMetadata(batch.map((f) => f.path).toList());

      for (var i = 0; i < batch.length; i++) {
        try {
          final file = batch[i];
          final stat = await file.stat();
          final meta = i < metaBatch.length ? metaBatch[i] : <String, String?>{};
          final embeddedBpm = await _TagReader.readBpm(
              file.path, p.extension(file.path).toLowerCase());
          final track = _buildTrack(file, stat, meta, embeddedBpm: embeddedBpm);
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

  // ── Metadata pipeline ─────────────────────────────────────────────────────

  /// Run metadata extraction for a batch of paths in parallel.
  Future<List<Map<String, String?>>> _batchMetadata(List<String> paths) async {
    if (paths.isEmpty) return [];
    return Future.wait(paths.map(_getCombinedMetadata));
  }

  /// For a single file: run ffprobe + mdls in parallel, prefer ffprobe values.
  Future<Map<String, String?>> _getCombinedMetadata(String path) async {
    final futures = [
      if (_ffprobeAvailable == true) _getFfprobeMetadata(path),
      _getMdlsMetadata(path),
    ];

    final results = await Future.wait(futures);
    final ffprobe = (_ffprobeAvailable == true) ? results[0] : <String, String?>{};
    final mdls    = (_ffprobeAvailable == true) ? results[1] : results[0];

    // Prefer ffprobe values (reads actual embedded tags).
    // Fall back to mdls for fields not found by ffprobe.
    return {
      'title':      ffprobe['title']      ?? mdls['title'],
      'artist':     ffprobe['artist']     ?? mdls['artist'],
      'album':      ffprobe['album']      ?? mdls['album'],
      'genre':      ffprobe['genre']      ?? mdls['genre'],
      'bpm':        ffprobe['bpm']        ?? mdls['bpm'],
      'key':        ffprobe['key']        ?? mdls['key'],
      'duration':   ffprobe['duration']   ?? mdls['duration'],
      'bitrate':    ffprobe['bitrate']    ?? mdls['bitrate'],
      'sampleRate': ffprobe['sampleRate'] ?? mdls['sampleRate'],
      'year':       ffprobe['year']       ?? mdls['year'],
    };
  }

  // ── ffprobe ───────────────────────────────────────────────────────────────

  Future<bool> _checkFfprobe() async {
    try {
      final r = await Process.run('ffprobe', ['-version'])
          .timeout(const Duration(seconds: 3), onTimeout: () => ProcessResult(0, 1, '', ''));
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Read all embedded tags via ffprobe -print_format json.
  /// ffprobe reads ID3v2 (TBPM/TKEY), Vorbis comments (BPM/KEY),
  /// iTunes atoms (tmpo/©key) — whatever the file contains.
  Future<Map<String, String?>> _getFfprobeMetadata(String path) async {
    try {
      final result = await Process.run('ffprobe', [
        '-v', 'quiet',
        '-print_format', 'json',
        '-show_format',
        '-show_streams',
        path,
      ]).timeout(_metaTimeout, onTimeout: () => ProcessResult(0, 1, '', 'timeout'));

      if (result.exitCode != 0) return {};

      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final format = json['format'] as Map<String, dynamic>? ?? {};
      final streams = (json['streams'] as List? ?? []).cast<Map<String, dynamic>>();

      // Collect all tags: format-level first (higher priority), then stream-level.
      final tags = <String, String>{};
      final audioStream = streams.firstWhere(
        (s) => s['codec_type'] == 'audio',
        orElse: () => <String, dynamic>{},
      );
      // Stream tags first (lower priority)
      for (final e in ((audioStream['tags'] as Map<String, dynamic>?) ?? {}).entries) {
        tags[e.key.toUpperCase()] = e.value.toString().trim();
      }
      // Format tags override stream tags
      for (final e in ((format['tags'] as Map<String, dynamic>?) ?? {}).entries) {
        tags[e.key.toUpperCase()] = e.value.toString().trim();
      }

      String? tag(List<String> keys) {
        for (final k in keys) {
          final v = tags[k.toUpperCase()];
          if (v != null && v.isNotEmpty && v != '0') return v;
        }
        return null;
      }

      // BPM: stored as TBPM (ID3v2), BPM (Vorbis/generic), TEMPO
      // Some encoders write "128" others "128.00" — we handle both.
      var bpmStr = tag(['TBPM', 'BPM', 'TEMPO', 'BEATSPERMINUTE']);
      // Some files store BPM as integer with extra decimals e.g. "128.000"
      if (bpmStr != null) {
        final d = double.tryParse(bpmStr);
        if (d != null && d > 0) {
          bpmStr = d.toStringAsFixed(d == d.truncateToDouble() ? 0 : 2);
        } else {
          bpmStr = null; // unparseable — discard
        }
      }

      // Key: TKEY (ID3v2), INITIALKEY (Traktor/Rekordbox), KEY
      final keyStr = tag(['TKEY', 'INITIALKEY', 'KEY', 'INITIAL KEY']);

      // Duration from format level (most accurate)
      final durationStr = format['duration']?.toString();

      // Bitrate: format bit_rate is in bits/sec (e.g. "320000")
      final bitrateStr = (format['bit_rate'] ?? audioStream['bit_rate'])?.toString();

      // Sample rate from audio stream
      final sampleRateStr = audioStream['sample_rate']?.toString();

      // Year: DATE tag may be "2023", "2023-01-15", etc. — extract first 4 digits.
      var yearStr = tag(['DATE', 'TDRC', 'TYER', 'YEAR', 'ORIGINALDATE']);
      if (yearStr != null) {
        final yearMatch = RegExp(r'\d{4}').firstMatch(yearStr);
        yearStr = yearMatch?.group(0);
      }

      return {
        'title':      tag(['TITLE', 'TIT2']),
        'artist':     tag(['ARTIST', 'TPE1', 'ALBUM_ARTIST', 'TPE2']),
        'album':      tag(['ALBUM', 'TALB']),
        'genre':      tag(['GENRE', 'TCON']),
        'bpm':        bpmStr,
        'key':        keyStr,
        'duration':   durationStr,
        'bitrate':    bitrateStr,
        'sampleRate': sampleRateStr,
        'year':       yearStr,
      };
    } catch (e) {
      dev.log('ffprobe error for $path: $e', name: 'LibraryScanner');
      return {};
    }
  }

  // ── mdls (macOS Spotlight) — fallback ─────────────────────────────────────

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
      ]).timeout(_metaTimeout, onTimeout: () {
        return ProcessResult(0, 1, '', 'timeout');
      });
      if (result.exitCode == 0) {
        final raw = result.stdout as String;
        final parts = raw.split('\x00');

        String? clean(String? s) {
          if (s == null) return null;
          final t = s.trim();
          if (t.isEmpty || t == '(null)' || t == 'null') return null;
          return t.replaceAll(RegExp(r'^["\(]|["\)]$'), '').trim();
        }

        String? extractAuthor(String? s) {
          if (s == null) return null;
          final match = RegExp(r'"([^"]+)"').firstMatch(s);
          if (match != null) return match.group(1);
          return clean(s);
        }

        // mdls -raw outputs fields in ALPHABETICAL order of attribute names,
        // regardless of the order -name flags were passed. Verified via xxd.
        // Alphabetical order of our requested fields:
        //   [0] kMDItemAlbum
        //   [1] kMDItemAudioBitRate
        //   [2] kMDItemAudioSampleRate
        //   [3] kMDItemAuthors
        //   [4] kMDItemDurationSeconds
        //   [5] kMDItemMusicalGenre
        //   [6] kMDItemMusicalKey
        //   [7] kMDItemRecordingYear
        //   [8] kMDItemTempo          ← BPM is here
        //   [9] kMDItemTitle
        return {
          'album':      clean(parts.isNotEmpty      ? parts[0] : null),
          'bitrate':    clean(parts.length > 1      ? parts[1] : null),
          'sampleRate': clean(parts.length > 2      ? parts[2] : null),
          'artist':     extractAuthor(parts.length > 3 ? parts[3] : null),
          'duration':   clean(parts.length > 4      ? parts[4] : null),
          'genre':      clean(parts.length > 5      ? parts[5] : null),
          'key':        clean(parts.length > 6      ? parts[6] : null),
          'year':       clean(parts.length > 7      ? parts[7] : null),
          'bpm':        clean(parts.length > 8      ? parts[8] : null),
          'title':      clean(parts.length > 9      ? parts[9] : null),
        };
      }
    } catch (e) {
      dev.log('mdls error for $path: $e', name: 'LibraryScanner');
    }
    return {};
  }

  // ── Build track ───────────────────────────────────────────────────────────

  LibraryTrack _buildTrack(File file, FileStat stat, Map<String, String?> meta, {double? embeddedBpm}) {
    final ext = p.extension(file.path).toLowerCase();
    final fileName = p.basenameWithoutExtension(file.path);

    final hashInput = '${file.path}:${stat.size}:${stat.modified.millisecondsSinceEpoch}';
    final hash = md5.convert(hashInput.codeUnits).toString();

    final title  = meta['title']  ?? _parseTitleFromName(fileName);
    final artist = meta['artist'] ?? _parseArtistFromName(fileName);

    // BPM priority:
    // 1. Embedded tag read directly from file bytes (most reliable)
    // 2. mdls/ffprobe kMDItemTempo / TBPM (from Spotlight / process metadata)
    // 3. 0 (unknown — never fake)
    final mdlsBpm = meta['bpm'] != null ? double.tryParse(meta['bpm']!) : null;
    final bpmRaw = embeddedBpm ?? (mdlsBpm != null && mdlsBpm > 0 ? mdlsBpm : null);
    final bpm = (bpmRaw != null && bpmRaw > 0 && bpmRaw < 400) ? bpmRaw : 0.0;

    // Key: use tagged value, fall back to Camelot simulation only if missing.
    final key = (meta['key'] != null && meta['key']!.isNotEmpty)
        ? _normaliseKey(meta['key']!)
        : _simulateKey(hash);

    final duration = meta['duration'] != null
        ? (double.tryParse(meta['duration']!) ?? 0.0)
        : 0.0;

    // Bitrate: ffprobe gives bits/sec ("320000"), mdls also bits/sec.
    final bitrateRaw = meta['bitrate'] != null ? int.tryParse(meta['bitrate']!) : null;
    final bitrate = bitrateRaw != null && bitrateRaw > 0 ? bitrateRaw : (ext == '.flac' ? 0 : 0);

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
      bpm: bpm,                          // 0 = not tagged; never faked
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

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _parseTitleFromName(String name) {
    final match = RegExp(r'^.+\s+-\s+(.+)$').firstMatch(name);
    if (match != null) return match.group(1)?.trim() ?? name;
    return name.replaceAll(RegExp(r'^\d+[\s._-]+'), '').trim();
  }

  String _parseArtistFromName(String name) {
    final match = RegExp(r'^(.+?)\s+-\s+.+$').firstMatch(name);
    return match?.group(1)?.trim() ?? '';
  }

  /// Normalise a key string into standard Camelot notation (e.g. "1A", "11B").
  /// Handles: "Am", "C#m", "Bb", "F#", Traktor "1d"/"1m", Open Key "1m"/"1d".
  String _normaliseKey(String raw) {
    final s = raw.trim();

    // Already Camelot format (e.g. "8A", "11B")
    if (RegExp(r'^\d{1,2}[ABab]$').hasMatch(s)) {
      return s.toUpperCase();
    }

    // Traktor / Open Key numeric format (e.g. "8d" = 8A minor, "8m" = 8B major)
    final traktor = RegExp(r'^(\d{1,2})([dm])$', caseSensitive: false).firstMatch(s);
    if (traktor != null) {
      final num = traktor.group(1)!;
      final mode = traktor.group(2)!.toLowerCase() == 'd' ? 'A' : 'B';
      return '$num$mode';
    }

    // Musical notation → Camelot
    const noteMap = {
      'B':  {'maj': '1B',  'min': '10A'},
      'F#': {'maj': '2B',  'min': '11A'},
      'Gb': {'maj': '2B',  'min': '11A'},
      'C#': {'maj': '3B',  'min': '12A'},
      'Db': {'maj': '3B',  'min': '12A'},
      'G#': {'maj': '4B',  'min': '1A'},
      'Ab': {'maj': '4B',  'min': '1A'},
      'D#': {'maj': '5B',  'min': '2A'},
      'Eb': {'maj': '5B',  'min': '2A'},
      'Bb': {'maj': '6B',  'min': '3A'},
      'A#': {'maj': '6B',  'min': '3A'},
      'F':  {'maj': '7B',  'min': '4A'},
      'C':  {'maj': '8B',  'min': '5A'},
      'G':  {'maj': '9B',  'min': '6A'},
      'D':  {'maj': '10B', 'min': '7A'},
      'A':  {'maj': '11B', 'min': '8A'},
      'E':  {'maj': '12B', 'min': '9A'},
    };

    // Match "Abm", "F#", "Cm", "A minor", "G major" etc.
    final musicalMatch = RegExp(
      r'^([A-Ga-g][#b]?)\s*(m(?:in(?:or)?)?|maj(?:or)?)?$',
      caseSensitive: false,
    ).firstMatch(s);

    if (musicalMatch != null) {
      var note = musicalMatch.group(1)!;
      // Capitalise: first letter upper, accidental lower
      note = note[0].toUpperCase() + (note.length > 1 ? note.substring(1).toLowerCase() : '');
      // Normalise 'b' suffix to lowercase (Db, Eb, etc.)
      final modeStr = (musicalMatch.group(2) ?? '').toLowerCase();
      final isMinor = modeStr.startsWith('m');
      final entry = noteMap[note];
      if (entry != null) {
        return isMinor ? entry['min']! : entry['maj']!;
      }
    }

    // Return as-is if we can't parse it (beats leaving it empty)
    return s;
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
