import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/library_track.dart';

/// Saves and restores the scanned library to/from a local JSON cache.
/// On desktop this used to live under Documents; using SharedPreferences keeps
/// the same app-level cache portable to Flutter Web.
class LibraryPersistenceService {
  static const _cacheKey = 'viberadar_library_cache_v1';

  Future<void> save(List<LibraryTrack> tracks, String? scannedPath) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode({
      'scannedPath': scannedPath,
      'savedAt': DateTime.now().toIso8601String(),
      'tracks': tracks.map(_trackToJson).toList(),
    });
    await prefs.setString(_cacheKey, json);
  }

  Future<({List<LibraryTrack> tracks, String? scannedPath})?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final tracks = (json['tracks'] as List)
          .map((e) => _trackFromJson(e as Map<String, dynamic>))
          .toList();
      return (tracks: tracks, scannedPath: json['scannedPath'] as String?);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
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
