import 'package:flutter/material.dart';

import 'track.dart';

class TrackFilters {
  const TrackFilters({
    this.bpmRange = const RangeValues(80, 160),
    this.energyRange = const RangeValues(0.0, 1.0),
    this.genre = 'All',
    this.vibe = 'All',
    this.region = 'Global',
  });

  final RangeValues bpmRange;
  final RangeValues energyRange;
  final String genre;
  final String vibe;
  final String region;

  TrackFilters copyWith({
    RangeValues? bpmRange,
    RangeValues? energyRange,
    String? genre,
    String? vibe,
    String? region,
  }) {
    return TrackFilters(
      bpmRange: bpmRange ?? this.bpmRange,
      energyRange: energyRange ?? this.energyRange,
      genre: genre ?? this.genre,
      vibe: vibe ?? this.vibe,
      region: region ?? this.region,
    );
  }

  bool matches(Track track) {
    final bpm = track.bpm.toDouble();
    final regionScore = region == 'Global'
        ? track.trendScore
        : track.regionScores[region.toUpperCase()] ?? 0;

    return (bpm == 0 || (bpm >= bpmRange.start && bpm <= bpmRange.end)) &&
        track.energyLevel >= energyRange.start &&
        track.energyLevel <= energyRange.end &&
        (genre == 'All' || track.genre == genre) &&
        (vibe == 'All' || track.vibe == vibe) &&
        (region == 'Global' || regionScore > 0);
  }
}
