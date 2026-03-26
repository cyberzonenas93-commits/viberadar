import '../models/track.dart';

/// Computes a [greatestScore] (0.0–1.0) for each [Track] that weighs
/// long-term cultural impact rather than just the current trend momentum.
///
/// Weights (8 dimensions)
/// ─────────────────────────────────────────────
///  long_term_popularity   0.20  (trend_score proxy)
///  chart_legacy           0.15  (platform breadth)
///  replay_longevity       0.15  (energy + history depth)
///  dj_usefulness          0.12  (BPM sweetspot + key)
///  timelessness           0.10  (age × sustained popularity)
///  familiarity            0.10  (mainstream crossover appeal)
///  artist_influence       0.08  (regional + source breadth)
///  cross_source           0.10  (how many sources carry it)
class GreatestOfService {
  // ─── public API ────────────────────────────────────────────────────────────

  /// Compute a 0.0–1.0 greatest-of score for a single track.
  double computeGreatestScore(Track track) {
    final popularity = _longTermPopularity(track);
    final legacy = _chartLegacy(track);
    final longevity = _replayLongevity(track);
    final djUse = _djUsefulness(track);
    final timeless = _timelessness(track);
    final familiar = _familiarity(track);
    final influence = _artistInfluence(track);
    final crossSource = _crossSourceProminence(track);

    return (popularity * 0.20) +
        (legacy * 0.15) +
        (longevity * 0.15) +
        (djUse * 0.12) +
        (timeless * 0.10) +
        (familiar * 0.10) +
        (influence * 0.08) +
        (crossSource * 0.10);
  }

  /// Filter and rank tracks for a greatest-of set.
  ///
  /// Supports multiple genres and multiple artists via comma-separated strings.
  /// Release-range filtering uses [Track.effectiveReleaseYear].
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

    // ── Genre filter (supports comma-separated multi-genre) ──
    if (genre != null && genre.isNotEmpty && genre != 'All') {
      final genres = genre
          .split(',')
          .map((g) => g.trim().toLowerCase())
          .where((g) => g.isNotEmpty)
          .toSet();
      if (genres.isNotEmpty) {
        filtered = filtered
            .where((t) => genres.contains(t.genre.toLowerCase()))
            .toList();
      }
    }

    // ── Artist filter (supports comma-separated multi-artist) ──
    if (artist != null && artist.isNotEmpty) {
      final artists = artist
          .split(',')
          .map((a) => a.trim().toLowerCase())
          .where((a) => a.isNotEmpty)
          .toList();
      if (artists.isNotEmpty) {
        filtered = filtered.where((t) {
          final tArtist = t.artist.toLowerCase();
          return artists.any((a) => tArtist.contains(a));
        }).toList();
      }
    }

    // ── Region filter ──
    if (region != null && region.isNotEmpty && region != 'All') {
      filtered = filtered.where((t) => t.leadRegion == region).toList();
    }

    // ── Release-year range (uses effectiveReleaseYear) ──
    if (yearFrom != null) {
      filtered =
          filtered.where((t) => t.effectiveReleaseYear >= yearFrom).toList();
    }
    if (yearTo != null) {
      filtered =
          filtered.where((t) => t.effectiveReleaseYear <= yearTo).toList();
    }

    filtered.sort(
        (a, b) => computeGreatestScore(b).compareTo(computeGreatestScore(a)));

    return filtered.take(limit).toList();
  }

  // ─── scoring components ────────────────────────────────────────────────────

  /// Long-term popularity: direct use of trend_score (0–1).
  double _longTermPopularity(Track t) => t.trendScore.clamp(0.0, 1.0);

  /// Chart legacy: rewards tracks present on many platforms.
  /// More platform links → wider cultural footprint.
  double _chartLegacy(Track t) {
    final count = t.platformLinks.length;
    // Normalise: 0 → 0.0, 5+ → 1.0
    return (count / 5).clamp(0.0, 1.0);
  }

  /// Replay longevity: energy level + trend-history depth.
  double _replayLongevity(Track t) {
    final energyScore = t.energyLevel.clamp(0.0, 1.0);
    // Bonus for tracks that have a rich history (shows sustained interest).
    final historyBonus = (t.trendHistory.length / 10).clamp(0.0, 0.4);
    return ((energyScore * 0.6) + historyBonus).clamp(0.0, 1.0);
  }

  /// DJ usefulness: optimal BPM range and key compatibility.
  /// Broadened to reward more genres (R&B at 70-90, Afrobeats at 95-115, etc.)
  double _djUsefulness(Track t) {
    double bpmScore;
    final bpm = t.bpm;
    if (bpm == 0) {
      bpmScore = 0.3; // unknown BPM — neutral
    } else if (bpm >= 85 && bpm <= 140) {
      // Broad DJ-friendly range (R&B through House)
      bpmScore = 1.0;
    } else if (bpm >= 70 && bpm <= 160) {
      bpmScore = 0.6;
    } else {
      bpmScore = 0.2;
    }

    // Bonus for tracks with a known key (better harmonic mixing).
    final keyBonus =
        (t.keySignature.isNotEmpty && t.keySignature != '--') ? 0.15 : 0.0;

    return (bpmScore + keyBonus).clamp(0.0, 1.0);
  }

  /// Timelessness: older tracks with sustained popularity get a bonus.
  /// Uses effectiveReleaseYear for age calculation.
  double _timelessness(Track t) {
    final currentYear = DateTime.now().year;
    final ageYears = currentYear - t.effectiveReleaseYear;
    if (ageYears < 2) return 0.0; // too new to be "timeless"
    // Scale: 2 yrs = base, 10+ yrs = full bonus, weighted by trend.
    final ageFactor = ((ageYears - 2) / 8).clamp(0.0, 1.0);
    return (ageFactor * t.trendScore).clamp(0.0, 1.0);
  }

  /// Familiarity: mainstream crossover appeal.
  /// Tracks with high trend scores and multiple regions are more familiar.
  double _familiarity(Track t) {
    final trendFactor = t.trendScore.clamp(0.0, 1.0);
    final regionBreadth = (t.regionScores.length / 4).clamp(0.0, 1.0);
    return (trendFactor * 0.6 + regionBreadth * 0.4).clamp(0.0, 1.0);
  }

  /// Artist influence: regional + source breadth.
  double _artistInfluence(Track t) {
    final regionCount = t.regionScores.length;
    return (regionCount / 6.0).clamp(0.0, 1.0);
  }

  /// Cross-source prominence: how many distinct ingestion sources carry this track.
  double _crossSourceProminence(Track t) {
    final sourceCount = t.effectiveSources.length;
    // 1 source → 0.2, 3+ sources → 1.0
    return ((sourceCount - 1) / 2).clamp(0.0, 1.0);
  }

  // ─── era helpers ──────────────────────────────────────────────────────────

  static String eraLabel(Track t) {
    final y = t.effectiveReleaseYear;
    if (y < 2000) return 'Pre-2000';
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

  /// Era presets for quick UI selection.
  static const eraPresets = {
    '90s': (1990, 1999),
    '2000s': (2000, 2009),
    '2010s': (2010, 2019),
    '2020s': (2020, 2029),
    'All Time': (null, null),
  };
}
