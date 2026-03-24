import 'package:cloud_firestore/cloud_firestore.dart';

import 'trend_point.dart';

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.artworkUrl,
    required this.bpm,
    required this.keySignature,
    required this.genre,
    required this.vibe,
    required this.trendScore,
    required this.regionScores,
    required this.platformLinks,
    required this.createdAt,
    required this.updatedAt,
    required this.energyLevel,
    required this.trendHistory,
  });

  final String id;
  final String title;
  final String artist;
  final String artworkUrl;
  final int bpm;
  final String keySignature;
  final String genre;
  final String vibe;
  final double trendScore;
  final Map<String, double> regionScores;
  final Map<String, String> platformLinks;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double energyLevel;
  final List<TrendPoint> trendHistory;

  String get leadRegion {
    if (regionScores.isEmpty) {
      return 'Global';
    }

    final sortedEntries = regionScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sortedEntries.first.key;
  }

  bool get isRisingFast {
    if (trendHistory.length < 2) {
      return trendScore > 0.82;
    }

    final delta = trendHistory.last.score - trendHistory.first.score;
    return delta >= 0.18 || trendScore >= 0.84;
  }

  factory Track.fromMap(Map<String, dynamic> map, {String? id}) {
    return Track(
      id: id ?? map['id'] as String? ?? '',
      title: map['title'] as String? ?? 'Untitled',
      artist: map['artist'] as String? ?? 'Unknown',
      artworkUrl: map['artwork_url'] as String? ?? '',
      bpm: (map['bpm'] as num?)?.round() ?? 0,
      keySignature: map['key'] as String? ?? '--',
      genre: map['genre'] as String? ?? 'Open Format',
      vibe: map['vibe'] as String? ?? 'club',
      trendScore: (map['trend_score'] as num?)?.toDouble() ?? 0,
      regionScores: _parseDoubleMap(map['region_scores']),
      platformLinks: Map<String, String>.from(
        map['platform_links'] as Map? ?? const {},
      ),
      createdAt: _parseDate(map['created_at']),
      updatedAt: _parseDate(map['updated_at']),
      energyLevel: (map['energy_level'] as num?)?.toDouble() ?? 0.5,
      trendHistory: _parseTrendHistory(map['trend_history']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'artwork_url': artworkUrl,
      'bpm': bpm,
      'key': keySignature,
      'genre': genre,
      'vibe': vibe,
      'trend_score': trendScore,
      'region_scores': regionScores,
      'platform_links': platformLinks,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'energy_level': energyLevel,
      'trend_history': trendHistory.map((point) => point.toMap()).toList(),
    };
  }

  static Map<String, double> _parseDoubleMap(dynamic input) {
    if (input is! Map) {
      return const {};
    }

    return input.map(
      (key, value) =>
          MapEntry(key.toString(), (value as num?)?.toDouble() ?? 0),
    );
  }

  static DateTime _parseDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
  }

  static List<TrendPoint> _parseTrendHistory(dynamic input) {
    if (input is! List) {
      return const [];
    }

    return input
        .whereType<Map>()
        .map(
          (item) => TrendPoint.fromMap(Map<String, dynamic>.from(item.cast())),
        )
        .toList();
  }
}
