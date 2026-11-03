import 'package:flutter/services.dart';
import 'dart:developer' as dev;

enum AppleMusicAuthStatus { authorized, notDetermined, denied, restricted, unavailable }

class AppleMusicTrack {
  const AppleMusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    this.artworkUrl,
    this.durationMs,
    this.genre = '',
  });
  final String id;
  final String title;
  final String artist;
  final String album;
  final String? artworkUrl;
  final int? durationMs;
  final String genre;

  double get durationSeconds => durationMs != null ? durationMs! / 1000.0 : 0.0;
}

class AppleMusicService {
  static const _channel = MethodChannel('com.viberadar.musickit');
  Future<AppleMusicAuthStatus> getAuthorizationStatus() async {
    try {
      final s = await _channel.invokeMethod<String>('getAuthorizationStatus');
      return _parseStatus(s);
    } catch (_) {
      return AppleMusicAuthStatus.unavailable;
    }
  }

  Future<AppleMusicAuthStatus> requestAuthorization() async {
    try {
      final s = await _channel.invokeMethod<String>('requestAuthorization');
      return _parseStatus(s);
    } catch (_) {
      return AppleMusicAuthStatus.unavailable;
    }
  }

  Future<bool> checkSubscription() async {
    try {
      return await _channel.invokeMethod<bool>('checkSubscription') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<List<AppleMusicTrack>> search(String query, {int limit = 25}) async {
    try {
      final raw = await _channel.invokeMethod<List>('search', {'query': query, 'limit': limit});
      if (raw == null) return [];
      return raw.map((item) {
        final m = Map<String, dynamic>.from(item as Map);
        final artwork = m['artwork'] as Map?;
        return AppleMusicTrack(
          id: m['id'] as String? ?? '',
          title: m['title'] as String? ?? '',
          artist: m['artist'] as String? ?? '',
          album: m['album'] as String? ?? '',
          artworkUrl: artwork?['url'] as String?,
          durationMs: m['durationMs'] as int?,
          genre: m['genre'] as String? ?? '',
        );
      }).where((t) => t.id.isNotEmpty && t.title.isNotEmpty).toList();
    } catch (e) {
      dev.log('Apple Music search error: $e', name: 'AppleMusicService');
      return [];
    }
  }

  Future<void> play(String catalogId) async {
    await _channel.invokeMethod<void>('play', {'catalogId': catalogId});
  }

  Future<void> pause() async {
    await _channel.invokeMethod<void>('pause');
  }

  Future<void> resume() async {
    await _channel.invokeMethod<void>('resume');
  }

  Future<void> stop() async {
    await _channel.invokeMethod<void>('stop');
  }

  Future<void> seek(double positionSeconds) async {
    await _channel.invokeMethod<void>('seek', {'position': positionSeconds});
  }

  Future<void> setVolume(double volume) async {
    await _channel.invokeMethod<void>('setVolume', {'volume': volume});
  }

  Future<Map<String, dynamic>> getPlaybackState() async {
    try {
      final r = await _channel.invokeMethod<Map>('getPlaybackState');
      return r != null ? Map<String, dynamic>.from(r) : {};
    } catch (_) {
      return {};
    }
  }

  AppleMusicAuthStatus _parseStatus(String? s) {
    switch (s) {
      case 'authorized':
        return AppleMusicAuthStatus.authorized;
      case 'denied':
        return AppleMusicAuthStatus.denied;
      case 'restricted':
        return AppleMusicAuthStatus.restricted;
      case 'notDetermined':
        return AppleMusicAuthStatus.notDetermined;
      default:
        return AppleMusicAuthStatus.unavailable;
    }
  }
}
