import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'platform_search_service.dart';

const _setBuilderBehaviorProfileKey = 'set_builder_behavior_profile_v1';

class SetBuilderBehaviorProfile {
  const SetBuilderBehaviorProfile({
    this.savedArtists = const {},
    this.rejectedArtists = const {},
    this.savedGenres = const {},
    this.rejectedTracks = const {},
    this.searchAgainCount = 0,
  });

  final Map<String, int> savedArtists;
  final Map<String, int> rejectedArtists;
  final Map<String, int> savedGenres;
  final Set<String> rejectedTracks;
  final int searchAgainCount;

  static const empty = SetBuilderBehaviorProfile();

  double affinityFor(PlatformTrackResult track) {
    final artist = _normalizeToken(track.artist);
    final titleKey = behaviorTrackKey(track.title, track.artist);
    var score = 0.0;
    score += (savedArtists[artist] ?? 0).clamp(0, 8) * 3.0;
    score -= (rejectedArtists[artist] ?? 0).clamp(0, 8) * 4.0;
    if (track.genre != null) {
      score +=
          (savedGenres[_normalizeToken(track.genre!)] ?? 0).clamp(0, 8) * 1.8;
    }
    if (rejectedTracks.contains(titleKey)) score -= 36;
    return score;
  }

  SetBuilderBehaviorProfile record({
    required SetBuilderBehaviorEvent event,
    PlatformTrackResult? track,
    String? genre,
  }) {
    final savedArtistsNext = Map<String, int>.from(savedArtists);
    final rejectedArtistsNext = Map<String, int>.from(rejectedArtists);
    final savedGenresNext = Map<String, int>.from(savedGenres);
    final rejectedTracksNext = Set<String>.from(rejectedTracks);
    var searchAgainNext = searchAgainCount;

    switch (event) {
      case SetBuilderBehaviorEvent.save:
      case SetBuilderBehaviorEvent.export:
        if (track != null) {
          _increment(savedArtistsNext, _normalizeToken(track.artist));
        }
        if (genre != null && genre.trim().isNotEmpty) {
          _increment(savedGenresNext, _normalizeToken(genre));
        }
      case SetBuilderBehaviorEvent.markWrong:
      case SetBuilderBehaviorEvent.delete:
        if (track != null) {
          _increment(rejectedArtistsNext, _normalizeToken(track.artist));
          rejectedTracksNext.add(behaviorTrackKey(track.title, track.artist));
        }
      case SetBuilderBehaviorEvent.reorder:
        if (track != null) {
          _increment(savedArtistsNext, _normalizeToken(track.artist));
        }
      case SetBuilderBehaviorEvent.searchAgain:
        searchAgainNext++;
    }

    return SetBuilderBehaviorProfile(
      savedArtists: savedArtistsNext,
      rejectedArtists: rejectedArtistsNext,
      savedGenres: savedGenresNext,
      rejectedTracks: rejectedTracksNext,
      searchAgainCount: searchAgainNext,
    );
  }

  Map<String, dynamic> toJson() => {
    'savedArtists': savedArtists,
    'rejectedArtists': rejectedArtists,
    'savedGenres': savedGenres,
    'rejectedTracks': rejectedTracks.toList(),
    'searchAgainCount': searchAgainCount,
  };

  factory SetBuilderBehaviorProfile.fromJson(Map<String, dynamic> json) {
    return SetBuilderBehaviorProfile(
      savedArtists: _intMap(json['savedArtists']),
      rejectedArtists: _intMap(json['rejectedArtists']),
      savedGenres: _intMap(json['savedGenres']),
      rejectedTracks: (json['rejectedTracks'] as List? ?? const [])
          .whereType<String>()
          .toSet(),
      searchAgainCount: (json['searchAgainCount'] as num?)?.toInt() ?? 0,
    );
  }

  static Map<String, int> _intMap(Object? value) {
    if (value is! Map) return const {};
    return value.map(
      (key, value) => MapEntry(key.toString(), (value as num?)?.toInt() ?? 0),
    );
  }

  static void _increment(Map<String, int> map, String key) {
    if (key.isEmpty) return;
    map[key] = (map[key] ?? 0) + 1;
  }
}

enum SetBuilderBehaviorEvent {
  save,
  delete,
  reorder,
  export,
  searchAgain,
  markWrong,
}

class SetBuilderBehaviorService {
  const SetBuilderBehaviorService();

  Future<SetBuilderBehaviorProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_setBuilderBehaviorProfileKey);
    if (raw == null || raw.isEmpty) return SetBuilderBehaviorProfile.empty;
    try {
      return SetBuilderBehaviorProfile.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return SetBuilderBehaviorProfile.empty;
    }
  }

  Future<SetBuilderBehaviorProfile> record({
    required SetBuilderBehaviorEvent event,
    PlatformTrackResult? track,
    String? genre,
  }) async {
    final current = await load();
    final next = current.record(event: event, track: track, genre: genre);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_setBuilderBehaviorProfileKey, jsonEncode(next));
    return next;
  }

  Future<SetBuilderBehaviorProfile> recordTracks({
    required SetBuilderBehaviorEvent event,
    required Iterable<PlatformTrackResult> tracks,
    String? genre,
  }) async {
    var next = await load();
    for (final track in tracks) {
      next = next.record(event: event, track: track, genre: genre);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_setBuilderBehaviorProfileKey, jsonEncode(next));
    return next;
  }
}

String behaviorTrackKey(String title, String artist) =>
    '${_normalizeToken(title)}::${_normalizeToken(artist)}';

String _normalizeToken(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), ' ')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
