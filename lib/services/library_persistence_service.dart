import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/library_track.dart';

/// Saves and restores the scanned library to/from a local JSON cache.
/// Cache lives at ~/Documents/VibeRadar/library_cache.json
class LibraryPersistenceService {
  static const _cacheFile = 'library_cache.json';

  Future<File> _getCacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory(p.join(dir.path, 'VibeRadar'));
    await cacheDir.create(recursive: true);
    return File(p.join(cacheDir.path, _cacheFile));
  }

  Future<void> save(List<LibraryTrack> tracks, String? scannedPath) async {
    try {
      final file = await _getCacheFile();
      final json = jsonEncode({
        'scannedPath': scannedPath,
        'savedAt': DateTime.now().toIso8601String(),
        'tracks': tracks.map(_trackToJson).toList(),
      });
      await file.writeAsString(json);
      dev.log('Library saved: ${tracks.length} tracks to ${file.path}', name: 'LibraryPersistence');
    } catch (e) {
      dev.log('Library save error: $e', name: 'LibraryPersistence');
    }
  }

  Future<({List<LibraryTrack> tracks, String? scannedPath})?> load() async {
    try {
      final file = await _getCacheFile();
      dev.log('Library cache path: ${file.path}', name: 'LibraryPersistence');
      if (!file.existsSync()) {
        dev.log('Library cache file does not exist', name: 'LibraryPersistence');
        return null;
      }
      final raw = await file.readAsString();
      dev.log('Library cache loaded: ${raw.length} bytes', name: 'LibraryPersistence');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final tracks = (json['tracks'] as List)
          .map((e) => _trackFromJson(e as Map<String, dynamic>))
          .toList();
      dev.log('Library cache parsed: ${tracks.length} tracks', name: 'LibraryPersistence');
      return (tracks: tracks, scannedPath: json['scannedPath'] as String?);
    } catch (e, st) {
      dev.log('Library cache load error: $e\n$st', name: 'LibraryPersistence');
      return null;
    }
  }

  Future<void> clear() async {
    final file = await _getCacheFile();
    if (file.existsSync()) await file.delete();
  }

  Map<String, dynamic> _trackToJson(LibraryTrack t) => {
        'id': t.id,
        'filePath': t.filePath,
        'fileName': t.fileName,
        'title': t.title,
        'artist': t.artist,
        'album': t.album,
        'genre': t.genre,
        'bpm': t.bpm,
        'key': t.key,
        'durationSeconds': t.durationSeconds,
        'fileSizeBytes': t.fileSizeBytes,
        'fileExtension': t.fileExtension,
        'md5Hash': t.md5Hash,
        'bitrate': t.bitrate,
        'sampleRate': t.sampleRate,
        'year': t.year,
        if (t.artworkUrl != null) 'artworkUrl': t.artworkUrl,
      };

  LibraryTrack _trackFromJson(Map<String, dynamic> j) => LibraryTrack(
        id: j['id'] as String,
        filePath: j['filePath'] as String,
        fileName: j['fileName'] as String,
        title: j['title'] as String,
        artist: j['artist'] as String,
        album: j['album'] as String,
        genre: j['genre'] as String,
        bpm: (j['bpm'] as num).toDouble(),
        key: j['key'] as String,
        durationSeconds: (j['durationSeconds'] as num).toDouble(),
        fileSizeBytes: j['fileSizeBytes'] as int,
        fileExtension: j['fileExtension'] as String,
        md5Hash: j['md5Hash'] as String,
        bitrate: j['bitrate'] as int,
        sampleRate: j['sampleRate'] as int,
        year: j['year'] as int?,
        artworkUrl: j['artworkUrl'] as String?,
      );
}
