import '../core/config/music_genres.dart';
import '../models/track.dart';
import 'platform_search_service.dart';

class LiveTrackCatalogService {
  LiveTrackCatalogService({PlatformSearchService? platformSearch})
    : _platformSearch = platformSearch ?? PlatformSearchService();

  final PlatformSearchService _platformSearch;

  Future<List<Track>> fetchTrendingTracks({
    required String region,
    String? genre,
    int limit = 100,
  }) async {
    final normalizedRegion = _normalizeRegion(region);
    final results = await _platformSearch.fetchTrendingChartTracks(
      region: normalizedRegion,
      genre: genre,
      limit: limit,
    );
    // Live trending must be chart-anchored. Playback platforms enrich chart
    // rows, but generic search-only results are too noisy for a top feed.
    final chartBacked = results
        .where(
          (result) =>
              result.hasUrl &&
              result.hasTrustedTrendEvidence &&
              (normalizedRegion == null ||
                  result.hasChartEvidenceForRegion(normalizedRegion)),
        )
        .toList();
    final eligible = _withGenreFallbacks(
      chartBacked,
      results,
      genre: genre,
      requestedRegion: normalizedRegion,
      limit: limit,
    );
    return eligible
        .map((result) => _trackFromResult(result, normalizedRegion))
        .toList();
  }

  List<PlatformTrackResult> _withGenreFallbacks(
    List<PlatformTrackResult> chartBacked,
    List<PlatformTrackResult> allResults, {
    required String? genre,
    required String? requestedRegion,
    required int limit,
  }) {
    if (!isSpecificGenre(genre)) return chartBacked;

    final targetFloor = (limit * 0.35).round().clamp(18, 36).toInt();
    if (chartBacked.length >= targetFloor) return chartBacked;

    final seen = {
      for (final result in chartBacked) _stableId(result.title, result.artist),
    };
    final filled = [...chartBacked];
    for (final result in allResults) {
      if (filled.length >= targetFloor || filled.length >= limit) break;
      if (!result.hasUrl || !result.hasStreamingPlatformEvidence) continue;
      if (!genreMatches(result.genre, genre!)) continue;
      if (requestedRegion != null &&
          result.hasRegionalChartEvidence &&
          !result.hasChartEvidenceForRegion(requestedRegion)) {
        continue;
      }
      final key = _stableId(result.title, result.artist);
      if (seen.add(key)) filled.add(result);
    }
    return filled;
  }

  Track _trackFromResult(PlatformTrackResult result, String? requestedRegion) {
    final now = DateTime.now();
    final trendScore = _trendScore(result);
    final regionScores = _regionScoresFor(result, requestedRegion, trendScore);
    final primaryRegion = requestedRegion ?? regionScores.keys.first;
    return Track(
      id: 'live:${_stableId(result.title, result.artist)}',
      title: result.title,
      artist: result.artist,
      artworkUrl: result.artworkUrl ?? '',
      bpm: 0,
      keySignature: '--',
      genre: result.genre ?? _defaultGenreForRegion(primaryRegion),
      vibe: _vibeFor(result),
      trendScore: trendScore,
      regionScores: regionScores,
      platformLinks: {
        if (result.spotifyUrl != null) 'spotify': result.spotifyUrl!,
        if (result.appleUrl != null) 'apple': result.appleUrl!,
        if (result.youtubeUrl != null) 'youtube': result.youtubeUrl!,
        if (result.soundchartsUrl != null)
          'soundcharts': result.soundchartsUrl!,
        if (result.billboardUrl != null) 'billboard': result.billboardUrl!,
        if (result.deezerUrl != null) 'deezer': result.deezerUrl!,
      },
      createdAt: now,
      updatedAt: now,
      energyLevel: _energyFor(result),
      trendHistory: const [],
      sources: [
        if (result.soundchartsSource != null) result.soundchartsSource!,
        if (result.appleChartRank != null) 'apple',
        if (result.billboardRank != null) 'billboard',
        if (result.youtubeChartRank != null) 'youtube',
        if (result.spotifyUrl != null) 'spotify',
        if (result.deezerUrl != null) 'deezer',
      ],
    );
  }

  double _trendScore(PlatformTrackResult result) {
    if (result.trendScore > 0) {
      return result.trendScore.clamp(0.05, 1.0).toDouble();
    }
    if (result.popularity > 0) {
      return (result.popularity / 100).clamp(0.05, 1.0).toDouble();
    }
    if (result.appleChartRank != null) {
      return ((101 - result.appleChartRank!.clamp(1, 100)) / 100)
          .clamp(0.05, 1.0)
          .toDouble();
    }
    return 0.5;
  }

  double _energyFor(PlatformTrackResult result) {
    var value = 0.42 + _trendScore(result) * 0.36;
    final source = result.soundchartsSource?.toLowerCase() ?? '';
    if (source.contains('tiktok')) value += 0.08;
    if (source.contains('boomplay')) value += 0.05;
    return value.clamp(0.25, 0.94).toDouble();
  }

  String _vibeFor(PlatformTrackResult result) {
    final source = result.soundchartsSource?.toLowerCase() ?? '';
    if (source.contains('tiktok')) return 'viral';
    if (source.contains('shazam')) return 'discovery';
    return 'club';
  }

  String _defaultGenreForRegion(String region) {
    return switch (region.toUpperCase()) {
      'GH' || 'NG' => 'Afrobeats',
      'ZA' => 'Amapiano',
      _ => 'Other',
    };
  }

  Map<String, double> _regionScoresFor(
    PlatformTrackResult result,
    String? requestedRegion,
    double score,
  ) {
    final requested = _normalizeRegion(requestedRegion ?? '');
    if (requested != null) return {requested: score};

    final regions = <String>{};
    final primaryRegion = _normalizeRegion(result.soundchartsRegion ?? '');
    if (primaryRegion != null) regions.add(primaryRegion);
    for (final region in result.soundchartsRegions) {
      final normalized = _normalizeRegion(region);
      if (normalized != null) regions.add(normalized);
    }
    if (regions.isEmpty) return {'Global': score};
    return {for (final region in regions) region: score};
  }

  String _stableId(String title, String artist) {
    return '$artist::$title'
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  String? _normalizeRegion(String region) {
    final value = region.trim().toUpperCase();
    if (value.isEmpty || value == 'ALL' || value == 'GLOBAL') return null;
    return value;
  }
}
