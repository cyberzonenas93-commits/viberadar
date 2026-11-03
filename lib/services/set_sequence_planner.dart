import '../models/library_track.dart';
import 'platform_search_service.dart';
import 'set_builder_behavior_service.dart';

enum SetJourneyPhase { opener, warmUp, lift, peak, reset, closer }

extension SetJourneyPhaseLabel on SetJourneyPhase {
  String get label => switch (this) {
    SetJourneyPhase.opener => 'Opener',
    SetJourneyPhase.warmUp => 'Warm-up',
    SetJourneyPhase.lift => 'Lift',
    SetJourneyPhase.peak => 'Peak',
    SetJourneyPhase.reset => 'Reset',
    SetJourneyPhase.closer => 'Closer',
  };
}

enum SetEnergyCurve { smoothRise, wave, peakEarly, peakLate, steady }

extension SetEnergyCurveLabel on SetEnergyCurve {
  String get label => switch (this) {
    SetEnergyCurve.smoothRise => 'Smooth rise',
    SetEnergyCurve.wave => 'Wave',
    SetEnergyCurve.peakEarly => 'Peak early',
    SetEnergyCurve.peakLate => 'Peak late',
    SetEnergyCurve.steady => 'Steady',
  };
}

enum SetContentPreference { cleanPreferred, flexible, explicitAllowed }

extension SetContentPreferenceLabel on SetContentPreference {
  String get label => switch (this) {
    SetContentPreference.cleanPreferred => 'Clean preferred',
    SetContentPreference.flexible => 'Flexible',
    SetContentPreference.explicitAllowed => 'Explicit ok',
  };
}

class DjSetContext {
  const DjSetContext({
    required this.eventType,
    required this.cityMarket,
    required this.crowdAge,
    required this.genreLane,
    required this.energyCurve,
    required this.contentPreference,
    required this.setLengthMinutes,
    required this.allowHardSwitches,
    this.mustPlay = const [],
    this.avoid = const [],
  });

  final String eventType;
  final String cityMarket;
  final String crowdAge;
  final String genreLane;
  final SetEnergyCurve energyCurve;
  final SetContentPreference contentPreference;
  final int setLengthMinutes;
  final bool allowHardSwitches;
  final List<String> mustPlay;
  final List<String> avoid;

  String get summary =>
      '$eventType in $cityMarket, crowd $crowdAge, $genreLane, '
      '${energyCurve.label}, ${contentPreference.label}, '
      '${allowHardSwitches ? 'hard switches allowed' : 'smooth transitions'}';
}

class SequencePlannedTrack {
  const SequencePlannedTrack({
    required this.track,
    required this.phase,
    required this.confidence,
    required this.reasons,
    required this.selectionScore,
    this.localMatch,
  });

  final PlatformTrackResult track;
  final SetJourneyPhase phase;
  final double confidence;
  final List<String> reasons;
  final double selectionScore;
  final LibraryTrack? localMatch;

  int get bpm => localMatch?.bpm.round() ?? 0;
  String get key => localMatch?.key ?? '';
  bool get foundLocally => localMatch != null;
}

class SetSequencePlan {
  const SetSequencePlan({
    required this.tracks,
    required this.targetCount,
    required this.removedDuplicates,
  });

  final List<SequencePlannedTrack> tracks;
  final int targetCount;
  final int removedDuplicates;
}

class SetSequencePlanner {
  const SetSequencePlanner();

  SetSequencePlan planPlatformSet({
    required List<PlatformTrackResult> candidates,
    required int targetCount,
    required DjSetContext context,
    List<LibraryTrack> localLibrary = const [],
    SetBuilderBehaviorProfile behavior = SetBuilderBehaviorProfile.empty,
  }) {
    if (targetCount <= 0 || candidates.isEmpty) {
      return const SetSequencePlan(
        tracks: [],
        targetCount: 0,
        removedDuplicates: 0,
      );
    }

    final filtered = candidates.where((track) {
      final haystack = '${track.artist} ${track.title}'.toLowerCase();
      return !context.avoid.any(
        (term) =>
            term.trim().isNotEmpty && haystack.contains(term.toLowerCase()),
      );
    }).toList();

    final deduped = _dedupeAndPickVersions(filtered, context, behavior);
    final selected = <SequencePlannedTrack>[];
    final remaining = [...deduped];
    final artistCounts = <String, int>{};
    final cappedTarget = targetCount.clamp(1, 150).toInt();

    while (selected.length < cappedTarget && remaining.isNotEmpty) {
      final phase = _phaseFor(selected.length, cappedTarget);
      final previous = selected.isEmpty ? null : selected.last;
      var bestIndex = 0;
      var bestScore = double.negativeInfinity;
      LibraryTrack? bestLocalMatch;

      for (var i = 0; i < remaining.length; i++) {
        final track = remaining[i];
        final localMatch = _localMatchFor(track, localLibrary);
        final score = _scoreCandidate(
          track: track,
          phase: phase,
          index: selected.length,
          targetCount: cappedTarget,
          previous: previous,
          context: context,
          behavior: behavior,
          localMatch: localMatch,
          artistCount: artistCounts[_artistKey(track.artist)] ?? 0,
        );
        if (score > bestScore) {
          bestScore = score;
          bestIndex = i;
          bestLocalMatch = localMatch;
        }
      }

      final track = remaining.removeAt(bestIndex);
      final planned = SequencePlannedTrack(
        track: track,
        phase: phase,
        confidence: _confidenceFor(
          track: track,
          previous: previous,
          context: context,
          localMatch: bestLocalMatch,
          score: bestScore,
        ),
        reasons: _reasonsFor(
          track: track,
          phase: phase,
          previous: previous,
          context: context,
          localMatch: bestLocalMatch,
        ),
        selectionScore: bestScore,
        localMatch: bestLocalMatch,
      );
      selected.add(planned);
      final artistKey = _artistKey(track.artist);
      artistCounts[artistKey] = (artistCounts[artistKey] ?? 0) + 1;
    }

    return SetSequencePlan(
      tracks: selected,
      targetCount: cappedTarget,
      removedDuplicates: filtered.length - deduped.length,
    );
  }

  List<PlatformTrackResult> _dedupeAndPickVersions(
    List<PlatformTrackResult> tracks,
    DjSetContext context,
    SetBuilderBehaviorProfile behavior,
  ) {
    final bySong = <String, PlatformTrackResult>{};
    final bestScore = <String, double>{};
    for (final track in tracks) {
      final key = _versionlessKey(track.title, track.artist);
      final score =
          _evidenceScore(track, context) +
          _versionScore(track, context) +
          behavior.affinityFor(track);
      if (!bySong.containsKey(key) || score > bestScore[key]!) {
        bySong[key] = track;
        bestScore[key] = score;
      }
    }
    return bySong.values.toList();
  }

  double _scoreCandidate({
    required PlatformTrackResult track,
    required SetJourneyPhase phase,
    required int index,
    required int targetCount,
    required SequencePlannedTrack? previous,
    required DjSetContext context,
    required SetBuilderBehaviorProfile behavior,
    required LibraryTrack? localMatch,
    required int artistCount,
  }) {
    final energyTarget = _energyTarget(
      context.energyCurve,
      phase,
      index,
      targetCount,
    );
    final energyFit = 1 - (_energyEstimate(track) - energyTarget).abs();
    final sourceFit = _evidenceScore(track, context);
    final versionFit = _versionScore(track, context);
    final localFit = localMatch == null ? 0.0 : 24.0;
    final behaviorFit = behavior.affinityFor(track);
    final transitionFit = previous == null
        ? 8.0
        : _transitionScore(previous, track, localMatch, context);
    final mustPlayFit = _matchesAny(track, context.mustPlay) ? 80.0 : 0.0;
    final artistPenalty = artistCount == 0 ? 0.0 : 22.0 + artistCount * 12.0;

    return sourceFit +
        versionFit +
        localFit +
        behaviorFit +
        transitionFit +
        mustPlayFit +
        (energyFit * 36.0) -
        artistPenalty;
  }

  double _evidenceScore(PlatformTrackResult track, DjSetContext context) {
    var score =
        (track.popularity.clamp(0, 100) * 0.45) +
        (track.trendScore.clamp(0.0, 1.0) * 52);
    if (_hasSoundchartsEvidence(track)) score += 34;
    if (track.appleChartRank != null) {
      score += 28 + ((101 - track.appleChartRank!.clamp(1, 100)) * 0.18);
    }

    final source = track.soundchartsSource?.toLowerCase() ?? '';
    if (source.contains('shazam')) score += 20;
    if (source.contains('tiktok')) score += 18;
    if (source.contains('boomplay')) score += 14;

    final region = _normalizeRegion(context.cityMarket);
    final resultRegion = _normalizeRegion(track.soundchartsRegion ?? '');
    if (region.isNotEmpty && resultRegion == region) {
      score += 22;
    } else if (resultRegion.isNotEmpty) {
      score += 5;
    }

    final genre = track.genre?.toLowerCase();
    final lane = context.genreLane.toLowerCase();
    if (genre != null && lane.contains(genre)) score += 10;

    final platformCount = [
      track.soundchartsUrl,
      track.spotifyUrl,
      track.appleUrl,
      track.youtubeUrl,
      track.deezerUrl,
    ].where((url) => url != null && url.isNotEmpty).length;
    score += platformCount * 4.0;
    return score;
  }

  double _versionScore(PlatformTrackResult track, DjSetContext context) {
    final text = '${track.title} ${track.artist}'.toLowerCase();
    var score = 0.0;
    final clean = text.contains('clean') || text.contains('radio edit');
    final explicit =
        text.contains('explicit') ||
        text.contains('dirty') ||
        text.contains('uncensored');
    final remix = text.contains('remix') || text.contains('edit');
    final instrumental =
        text.contains('instrumental') ||
        text.contains('karaoke') ||
        text.contains('acapella');
    final live = text.contains(' live ') || text.endsWith(' live');

    switch (context.contentPreference) {
      case SetContentPreference.cleanPreferred:
        if (clean) score += 22;
        if (explicit) score -= 34;
      case SetContentPreference.flexible:
        if (clean) score += 6;
        if (explicit) score -= 5;
      case SetContentPreference.explicitAllowed:
        if (explicit) score += 2;
    }

    if (remix && context.eventType.toLowerCase().contains('club')) {
      score += 8;
    }
    if (instrumental) score -= 18;
    if (live) score -= 14;
    return score;
  }

  double _transitionScore(
    SequencePlannedTrack previous,
    PlatformTrackResult candidate,
    LibraryTrack? localMatch,
    DjSetContext context,
  ) {
    if (context.allowHardSwitches) return 7;
    var score = 10.0;
    final previousBpm = previous.bpm;
    final nextBpm = localMatch?.bpm.round() ?? 0;
    if (previousBpm > 0 && nextBpm > 0) {
      final diff = (previousBpm - nextBpm).abs();
      if (diff <= 4) {
        score += 24;
      } else if (diff <= 8) {
        score += 15;
      } else if (diff <= 14) {
        score += 5;
      } else {
        score -= 24;
      }
    }

    final previousKey = previous.key;
    final nextKey = localMatch?.key ?? '';
    if (previousKey.isNotEmpty && nextKey.isNotEmpty) {
      score += _harmonicCompatibility(previousKey, nextKey) * 18;
    }
    return score;
  }

  double _confidenceFor({
    required PlatformTrackResult track,
    required SequencePlannedTrack? previous,
    required DjSetContext context,
    required LibraryTrack? localMatch,
    required double score,
  }) {
    var confidence = 0.48;
    if (_hasSoundchartsEvidence(track)) confidence += 0.16;
    if (track.trendScore > 0.55) confidence += 0.10;
    if (track.popularity >= 65) confidence += 0.08;
    if (localMatch != null) confidence += 0.12;
    if (_matchesAny(track, context.mustPlay)) confidence += 0.08;
    if (score > 130) confidence += 0.06;
    if (previous != null && previous.bpm > 0 && localMatch?.bpm != null) {
      confidence += 0.04;
    }
    return confidence.clamp(0.35, 0.98);
  }

  List<String> _reasonsFor({
    required PlatformTrackResult track,
    required SetJourneyPhase phase,
    required SequencePlannedTrack? previous,
    required DjSetContext context,
    required LibraryTrack? localMatch,
  }) {
    final reasons = <String>[
      'Placed as ${phase.label.toLowerCase()} for ${context.energyCurve.label.toLowerCase()} flow',
    ];
    final source = track.soundchartsSource?.trim();
    final region = track.soundchartsRegion?.trim();
    if (source != null && source.isNotEmpty) {
      final label = source.toLowerCase().contains('tiktok')
          ? 'Rising on TikTok'
          : source.toLowerCase().contains('shazam')
          ? 'Strong Shazam discovery'
          : source.toLowerCase().contains('boomplay')
          ? 'Strong Boomplay signal'
          : 'Soundcharts evidence';
      reasons.add(
        region == null || region.isEmpty ? label : '$label in $region',
      );
    } else if (track.popularity >= 70) {
      reasons.add('High platform popularity');
    }

    if (track.appleChartRank != null) {
      reasons.add('Top ${track.appleChartRank} on Apple Music');
    }

    if (track.trendScore >= 0.65) {
      reasons.add('High trend velocity');
    }
    if (localMatch != null) {
      reasons.add('Found locally on this computer');
      if (previous != null && previous.bpm > 0 && localMatch.bpm > 0) {
        final diff = (previous.bpm - localMatch.bpm.round()).abs();
        if (diff <= 8) reasons.add('Good BPM bridge');
      }
      if (previous != null &&
          previous.key.isNotEmpty &&
          localMatch.key.isNotEmpty &&
          _harmonicCompatibility(previous.key, localMatch.key) >= 0.85) {
        reasons.add('Compatible Camelot key');
      }
    }
    if (_matchesAny(track, context.mustPlay)) {
      reasons.add('Matches must-play request');
    }
    final version = _versionReason(track, context);
    if (version != null) reasons.add(version);

    return reasons.take(5).toList();
  }

  String? _versionReason(PlatformTrackResult track, DjSetContext context) {
    final text = '${track.title} ${track.artist}'.toLowerCase();
    if (context.contentPreference == SetContentPreference.cleanPreferred &&
        (text.contains('clean') || text.contains('radio edit'))) {
      return 'Clean/DJ-safe version preferred';
    }
    if (text.contains('remix') || text.contains('edit')) {
      return 'DJ-ready edit/version';
    }
    return null;
  }

  SetJourneyPhase _phaseFor(int index, int targetCount) {
    final progress = targetCount <= 1 ? 1.0 : index / (targetCount - 1);
    if (progress < 0.12) return SetJourneyPhase.opener;
    if (progress < 0.32) return SetJourneyPhase.warmUp;
    if (progress < 0.55) return SetJourneyPhase.lift;
    if (progress < 0.78) return SetJourneyPhase.peak;
    if (progress < 0.9) return SetJourneyPhase.reset;
    return SetJourneyPhase.closer;
  }

  double _energyTarget(
    SetEnergyCurve curve,
    SetJourneyPhase phase,
    int index,
    int targetCount,
  ) {
    final progress = targetCount <= 1 ? 1.0 : index / (targetCount - 1);
    return (switch (curve) {
      SetEnergyCurve.smoothRise => switch (phase) {
        SetJourneyPhase.opener => 0.34,
        SetJourneyPhase.warmUp => 0.48,
        SetJourneyPhase.lift => 0.66,
        SetJourneyPhase.peak => 0.88,
        SetJourneyPhase.reset => 0.58,
        SetJourneyPhase.closer => 0.76,
      },
      SetEnergyCurve.wave =>
        0.55 + (progress < 0.5 ? progress : 1 - progress) * 0.55,
      SetEnergyCurve.peakEarly =>
        progress < 0.35 ? 0.82 : 0.72 - progress * 0.18,
      SetEnergyCurve.peakLate => 0.35 + progress * 0.58,
      SetEnergyCurve.steady => 0.62,
    }).clamp(0.2, 0.95).toDouble();
  }

  double _energyEstimate(PlatformTrackResult track) {
    final source = track.soundchartsSource?.toLowerCase() ?? '';
    var value = 0.34 + track.trendScore.clamp(0.0, 1.0) * 0.34;
    value += track.popularity.clamp(0, 100) / 100 * 0.22;
    if (source.contains('tiktok')) value += 0.08;
    if (source.contains('boomplay')) value += 0.05;
    return value.clamp(0.2, 0.95).toDouble();
  }

  LibraryTrack? _localMatchFor(
    PlatformTrackResult track,
    List<LibraryTrack> localLibrary,
  ) {
    final wanted = _versionlessKey(track.title, track.artist);
    LibraryTrack? best;
    var bestScore = 0;
    for (final local in localLibrary) {
      final key = _versionlessKey(local.title, local.artist);
      var score = 0;
      if (key == wanted) {
        score += 100;
      } else {
        final wantedTitle = wanted.split('::').first;
        final localTitle = key.split('::').first;
        if (wantedTitle.contains(localTitle) ||
            localTitle.contains(wantedTitle)) {
          score += 45;
        }
      }
      if (local.bitrate > 0) score += (local.bitrate / 64).round();
      if (local.bpm > 0) score += 5;
      if (local.key.isNotEmpty) score += 5;
      if (score > bestScore) {
        bestScore = score;
        best = local;
      }
    }
    return bestScore >= 55 ? best : null;
  }

  bool _matchesAny(PlatformTrackResult track, List<String> terms) {
    final text = '${track.artist} ${track.title}'.toLowerCase();
    return terms.any((term) {
      final value = term.trim().toLowerCase();
      return value.isNotEmpty && text.contains(value);
    });
  }

  bool _hasSoundchartsEvidence(PlatformTrackResult track) {
    return (track.soundchartsUrl != null && track.soundchartsUrl!.isNotEmpty) ||
        (track.soundchartsSource != null &&
            track.soundchartsSource!.isNotEmpty) ||
        (track.soundchartsRegion != null &&
            track.soundchartsRegion!.isNotEmpty) ||
        track.appleChartRank != null;
  }

  String _versionlessKey(String title, String artist) {
    final cleanTitle = _normalize(title)
        .replaceAll(
          RegExp(
            r'\b(clean|dirty|explicit|radio|edit|remix|original|version|official|video|audio|lyric|lyrics|extended|club|mix|feat|ft)\b',
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return '$cleanTitle::${_artistKey(artist)}';
  }

  String _artistKey(String artist) => _normalize(
    artist,
  ).replaceAll(RegExp(r'\b(feat|ft|with)\b.*$'), '').trim();

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _normalizeRegion(String value) {
    final match = RegExp(r'\b[A-Z]{2}\b').firstMatch(value.toUpperCase());
    return match?.group(0) ?? value.trim().toUpperCase();
  }

  double _harmonicCompatibility(String first, String second) {
    if (first == second) return 1;
    final firstCamelot = _toCamelot(first);
    final secondCamelot = _toCamelot(second);
    if (firstCamelot == null || secondCamelot == null) return 0.55;

    final sameLetter = firstCamelot.$2 == secondCamelot.$2;
    final sameNumber = firstCamelot.$1 == secondCamelot.$1;
    final distance = (firstCamelot.$1 - secondCamelot.$1).abs();
    final wrappedDistance = distance > 6 ? 12 - distance : distance;
    if (sameNumber && sameLetter) return 1;
    if (sameNumber && !sameLetter) return 0.92;
    if (sameLetter && wrappedDistance == 1) return 0.88;
    if (!sameLetter && wrappedDistance == 1) return 0.72;
    if (sameLetter && wrappedDistance == 2) return 0.6;
    return 0.4;
  }

  (int, String)? _toCamelot(String key) {
    final match = RegExp(
      r'^(\d{1,2})([AB])$',
    ).firstMatch(key.trim().toUpperCase());
    if (match != null) return (int.parse(match.group(1)!), match.group(2)!);
    return null;
  }
}
