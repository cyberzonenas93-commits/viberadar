import '../models/track.dart';

/// Computes a [greatestScore] (0.0–1.0) for each [Track] that weighs
/// long-term cultural impact rather than just the current trend momentum.
///
/// Weights
/// ─────────────────────────────────────────────
///  long_term_popularity  0.25  (trend_score proxy)
///  chart_legacy          0.20  (platform breadth)
///  replay_longevity      0.20  (energy + history depth)
///  dj_usefulness         0.15  (BPM sweetspot + key)
///  timelessness          0.10  (age × sustained popularity)
///  artist_influence      0.10  (relative to peer avg)
class GreatestOfService {
  // ─── public API ────────────────────────────────────────────────────────────

  /// Compute a 0.0–1.0 greatest-of score for a single track.
  double computeGreatestScore(Track track) {
    final popularity = _longTermPopularity(track);
    final legacy = _chartLegacy(track);
    final longevity = _replayLongevity(track);
    final djUse = _djUsefulness(track);
    final timeless = _timelessness(track);
    final influence = _artistInfluence(track);

    return (popularity * 0.25) +
        (legacy * 0.20) +
        (longevity * 0.20) +
        (djUse * 0.15) +
        (timeless * 0.10) +
        (influence * 0.10);
  }

  /// Filter and rank tracks for a greatest-of set.
  List<Track> buildGreatestOfSet({
    required List<Track> tracks,
    String? genre,
    String? artist,
    String? region,
    int? yearFrom,
    int? yearTo,
    int limit = 50,
  }) {
    var filtered = tracks.toList();

    if (genre != null && genre.isNotEmpty && genre != 'All') {
      filtered =
          filtered.where((t) => t.genre.toLowerCase() == genre.toLowerCase()).toList();
    }
    if (artist != null && artist.isNotEmpty) {
      final q = artist.toLowerCase();
      filtered =
          filtered.where((t) => t.artist.toLowerCase().contains(q)).toList();
    }
    if (region != null && region.isNotEmpty && region != 'All') {
      filtered =
          filtered.where((t) => t.leadRegion == region).toList();
    }
    if (yearFrom != null) {
      filtered =
          filtered.where((t) => t.createdAt.year >= yearFrom).toList();
    }
    if (yearTo != null) {
      filtered =
          filtered.where((t) => t.createdAt.year <= yearTo).toList();
    }

    filtered.sort((a, b) =>
        computeGreatestScore(b).compareTo(computeGreatestScore(a)));

    return filtered.take(limit).toList();
  }

  // ─── scoring components ────────────────────────────────────────────────────

  /// Long-term popularity: direct use of trend_score (0–1).
  double _longTermPopularity(Track t) => t.trendScore.clamp(0.0, 1.0);

  /// Chart legacy: rewards tracks present on many platforms.
  /// More platform links → wider cultural footprint.
  double _chartLegacy(Track t) {
    final count = t.platformLinks.length;
    // Normalise: 0 → 0.0, 4+ → 1.0
    return (count / 4).clamp(0.0, 1.0);
  }

  /// Replay longevity: energy level + trend-history depth.
  double _replayLongevity(Track t) {
    final energyScore = t.energyLevel.clamp(0.0, 1.0);
    // Bonus for tracks that have a rich history (shows sustained interest).
    final historyBonus = (t.trendHistory.length / 10).clamp(0.0, 0.4);
    return ((energyScore * 0.6) + historyBonus).clamp(0.0, 1.0);
  }

  /// DJ usefulness: optimal BPM range and key compatibility.
  double _djUsefulness(Track t) {
    double bpmScore;
    final bpm = t.bpm;
    if (bpm >= 120 && bpm <= 130) {
      // House/tech-house sweet spot
      bpmScore = 1.0;
    } else if (bpm >= 110 && bpm <= 140) {
      bpmScore = 0.7;
    } else if (bpm >= 90 && bpm <= 150) {
      bpmScore = 0.4;
    } else if (bpm == 0) {
      bpmScore = 0.3; // unknown BPM — neutral penalty
    } else {
      bpmScore = 0.2;
    }

    // Bonus for tracks with a known key (better harmonic mixing).
    final keyBonus = (t.keySignature.isNotEmpty && t.keySignature != '--')
        ? 0.15
        : 0.0;

    return (bpmScore + keyBonus).clamp(0.0, 1.0);
  }

  /// Timelessness: old tracks with sustained popularity get a bonus.
  double _timelessness(Track t) {
    final ageYears = DateTime.now().difference(t.createdAt).inDays / 365;
    if (ageYears < 3) return 0.0; // too new to be "timeless"
    // Scale: 3 yrs = base, 10+ yrs = full bonus, weighted by trend.
    final ageFactor = ((ageYears - 3) / 7).clamp(0.0, 1.0);
    return (ageFactor * t.trendScore).clamp(0.0, 1.0);
  }

  /// Artist influence: relative score versus the average across all tracks.
  /// Computed per track with a simple heuristic (trend_score above median).
  double _artistInfluence(Track t) {
    // Without a full catalogue context here we use regionScores breadth.
    final regionCount = t.regionScores.length;
    final maxRegions = 8.0;
    return (regionCount / maxRegions).clamp(0.0, 1.0);
  }

  // ─── era helpers ──────────────────────────────────────────────────────────

  static String eraLabel(Track t) {
    final y = t.createdAt.year;
    if (y < 2010) return '2000s';
    if (y < 2020) return '2010s';
    return '2020s';
  }

  static Map<String, List<Track>> groupByEra(List<Track> tracks) {
    final map = <String, List<Track>>{};
    for (final t in tracks) {
      map.putIfAbsent(eraLabel(t), () => []).add(t);
    }
    return map;
  }
}
