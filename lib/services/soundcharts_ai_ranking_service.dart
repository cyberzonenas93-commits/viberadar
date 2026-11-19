import 'dart:convert';
import 'dart:developer' as developer;

import 'ai_copilot_service.dart';
import 'platform_search_service.dart';

typedef AiJsonRequester =
    Future<String> Function(List<Map<String, String>> messages);

/// Ranks live platform results with chart/platform evidence and a bounded AI
/// rerank pass over supplied candidate IDs only.
class SoundchartsAiRankingService {
  SoundchartsAiRankingService({
    AiCopilotService? ai,
    AiJsonRequester? requestJson,
  }) : _requestJson = requestJson ?? (ai ?? AiCopilotService()).requestJson;

  final AiJsonRequester _requestJson;

  Future<List<PlatformTrackResult>> rankForSetBuilder({
    required List<PlatformTrackResult> results,
    required String mode,
    required String genre,
    String artist = '',
    String? region,
    int? yearFrom,
    int? yearTo,
    int minBpm = 0,
    int maxBpm = 0,
    String djContext = '',
  }) {
    return _rankWithAi(
      results,
      _RankingContext(
        useCase: _RankingUseCase.setBuilder,
        mode: mode,
        genre: genre,
        artist: artist,
        region: region,
        yearFrom: yearFrom,
        yearTo: yearTo,
        minBpm: minBpm,
        maxBpm: maxBpm,
        djContext: djContext,
      ),
    );
  }

  Future<List<PlatformTrackResult>> rankForGreatestOf({
    required List<PlatformTrackResult> results,
    required String genre,
    required String region,
    required String artist,
    int? yearFrom,
    int? yearTo,
  }) {
    return _rankWithAi(
      results,
      _RankingContext(
        useCase: _RankingUseCase.greatestOf,
        mode: 'Greatest Of',
        genre: genre,
        artist: artist,
        region: region,
        yearFrom: yearFrom,
        yearTo: yearTo,
      ),
    );
  }

  Future<List<PlatformTrackResult>> _rankWithAi(
    List<PlatformTrackResult> results,
    _RankingContext context,
  ) async {
    final deterministic = _rankDeterministically(results, context);
    if (deterministic.length < 2) return deterministic;

    final candidates = deterministic.take(40).toList();
    if (!candidates.any(_hasLiveEvidence)) return deterministic;

    try {
      final raw = await _requestJson(_messagesFor(context, candidates));
      final ids = _extractRankedIds(raw);
      if (ids.isEmpty) return deterministic;
      return _reorderByIds(
        deterministic: deterministic,
        candidates: candidates,
        ids: ids,
      );
    } catch (error, stackTrace) {
      developer.log(
        'Live platform AI ranking failed; using deterministic ranking',
        name: 'SoundchartsAiRanking',
        error: error,
        stackTrace: stackTrace,
      );
      return deterministic;
    }
  }

  List<PlatformTrackResult> _rankDeterministically(
    List<PlatformTrackResult> results,
    _RankingContext context,
  ) {
    final ranked = [...results];
    ranked.sort((a, b) {
      final scoreCompare = _score(b, context).compareTo(_score(a, context));
      if (scoreCompare != 0) return scoreCompare;
      final titleCompare = a.title.compareTo(b.title);
      if (titleCompare != 0) return titleCompare;
      return a.artist.compareTo(b.artist);
    });
    return ranked;
  }

  double _score(PlatformTrackResult track, _RankingContext context) {
    final source = track.soundchartsSource?.toLowerCase() ?? '';
    final trend = track.trendScore.clamp(0.0, 1.0);
    final popularity = track.popularity.clamp(0, 100).toDouble();
    var score = popularity + (trend * 100);

    if (_hasChartEvidence(track)) {
      score += context.useCase == _RankingUseCase.greatestOf ? 42 : 34;
    }
    if (track.appleChartRank != null) {
      score += 42 + ((101 - track.appleChartRank!.clamp(1, 100)) * 0.25);
    }

    if (source.contains('shazam')) score += 20;
    if (source.contains('tiktok')) score += 16;
    if (source.contains('boomplay')) score += 14;

    final mode = context.mode.toLowerCase();
    if (mode.contains('rising')) {
      score += trend * 45;
      if (source.contains('tiktok')) score += 18;
      if (source.contains('shazam')) score += 10;
    } else if (mode.contains('hot')) {
      score += popularity * 0.25;
      if (source.contains('boomplay')) score += 12;
    } else if (mode.contains('greatest')) {
      score += popularity * 0.20;
      if (source.contains('shazam')) score += 14;
    } else if (mode.contains('trending')) {
      score += trend * 30;
    }

    final requestedRegion = _normalizeRegion(context.region);
    final resultRegion = _normalizeRegion(track.soundchartsRegion);
    if (requestedRegion != null && resultRegion == requestedRegion) {
      score += 28;
    } else if (resultRegion != null) {
      score += 6;
    }

    final requestedGenre = context.genre.trim().toLowerCase();
    final resultGenre = track.genre?.trim().toLowerCase();
    if (requestedGenre.isNotEmpty &&
        requestedGenre != 'all' &&
        resultGenre != null &&
        (resultGenre.contains(requestedGenre) ||
            requestedGenre.contains(resultGenre))) {
      score += 16;
    }

    final platformCount = [
      track.spotifyUrl,
      track.appleUrl,
      track.youtubeUrl,
      track.deezerUrl,
      track.soundchartsUrl,
    ].where((url) => url != null && url.isNotEmpty).length;
    score += platformCount * 5;

    if (context.artist.trim().isNotEmpty) {
      final requestedArtists = context.artist
          .split(',')
          .map((value) => value.trim().toLowerCase())
          .where((value) => value.isNotEmpty);
      final resultArtist = track.artist.toLowerCase();
      if (requestedArtists.any(
        (artist) =>
            resultArtist.contains(artist) || artist.contains(resultArtist),
      )) {
        score += 18;
      }
    }

    return score;
  }

  List<Map<String, String>> _messagesFor(
    _RankingContext context,
    List<PlatformTrackResult> candidates,
  ) {
    final payload = {
      'task': context.useCase == _RankingUseCase.greatestOf
          ? 'rank_greatest_of'
          : 'rank_set_builder_slot',
      'rules': [
        'Only return candidate ids from the supplied list.',
        'Use Apple Music, Spotify, YouTube, Deezer, and Soundcharts evidence.',
        'Treat Apple Music country chart rank as strong regional demand.',
        'Prefer region and genre fit, platform agreement, and DJ usability.',
        'Do not invent tracks or metadata.',
      ],
      'context': {
        'mode': context.mode,
        'genre': context.genre,
        'artist': context.artist,
        'region': context.region,
        'yearFrom': context.yearFrom,
        'yearTo': context.yearTo,
        'minBpm': context.minBpm,
        'maxBpm': context.maxBpm,
        if (context.djContext.isNotEmpty) 'djContext': context.djContext,
      },
      'candidates': [
        for (var i = 0; i < candidates.length; i++)
          _candidateJson('c$i', candidates[i]),
      ],
    };

    return [
      {
        'role': 'system',
        'content':
            'You are VibeRadar ranking intelligence for professional DJs. '
            'Use Apple Music, Spotify, YouTube, Deezer, Soundcharts evidence, '
            'and DJ context to order candidates. '
            'Return strict JSON only, shaped as {"ids":["c0","c1"]}.',
      },
      {'role': 'user', 'content': jsonEncode(payload)},
    ];
  }

  Map<String, Object?> _candidateJson(String id, PlatformTrackResult track) {
    return {
      'id': id,
      'title': track.title,
      'artist': track.artist,
      'genre': track.genre,
      'soundchartsSource': track.soundchartsSource,
      'soundchartsRegion': track.soundchartsRegion,
      'soundchartsUrl': track.soundchartsUrl,
      'appleChartRank': track.appleChartRank,
      'popularity': track.popularity,
      'trendScore': track.trendScore,
      'platforms': [
        if (track.soundchartsUrl != null) 'soundcharts',
        if (track.spotifyUrl != null) 'spotify',
        if (track.appleUrl != null) 'apple_music',
        if (track.youtubeUrl != null) 'youtube',
        if (track.deezerUrl != null) 'deezer',
      ],
    };
  }

  List<String> _extractRankedIds(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const [];

      final ids = decoded['ids'];
      if (ids is List) {
        return ids.whereType<String>().where((id) => id.isNotEmpty).toList();
      }

      final tracks = decoded['tracks'];
      if (tracks is List) {
        return tracks
            .whereType<Map<Object?, Object?>>()
            .map((track) => track['id'])
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toList();
      }
    } catch (_) {
      return const [];
    }
    return const [];
  }

  List<PlatformTrackResult> _reorderByIds({
    required List<PlatformTrackResult> deterministic,
    required List<PlatformTrackResult> candidates,
    required List<String> ids,
  }) {
    final byId = {
      for (var i = 0; i < candidates.length; i++) 'c$i': candidates[i],
    };
    final selected = <PlatformTrackResult>[];
    final selectedSet = <PlatformTrackResult>{};

    for (final id in ids) {
      final track = byId[id];
      if (track != null && selectedSet.add(track)) selected.add(track);
    }

    for (final track in candidates) {
      if (selectedSet.add(track)) selected.add(track);
    }

    final candidateSet = candidates.toSet();
    for (final track in deterministic) {
      if (!candidateSet.contains(track)) selected.add(track);
    }

    return selected;
  }

  bool _hasLiveEvidence(PlatformTrackResult track) {
    return _hasChartEvidence(track) || track.hasStreamingPlatformEvidence;
  }

  bool _hasChartEvidence(PlatformTrackResult track) {
    return (track.soundchartsUrl != null && track.soundchartsUrl!.isNotEmpty) ||
        (track.soundchartsSource != null &&
            track.soundchartsSource!.isNotEmpty) ||
        (track.soundchartsRegion != null &&
            track.soundchartsRegion!.isNotEmpty) ||
        track.appleChartRank != null;
  }

  String? _normalizeRegion(String? region) {
    final value = region?.trim().toUpperCase();
    if (value == null || value.isEmpty || value == 'ALL' || value == 'GLOBAL') {
      return null;
    }
    return value;
  }
}

enum _RankingUseCase { setBuilder, greatestOf }

class _RankingContext {
  const _RankingContext({
    required this.useCase,
    required this.mode,
    required this.genre,
    required this.artist,
    required this.region,
    required this.yearFrom,
    required this.yearTo,
    this.minBpm = 0,
    this.maxBpm = 0,
    this.djContext = '',
  });

  final _RankingUseCase useCase;
  final String mode;
  final String genre;
  final String artist;
  final String? region;
  final int? yearFrom;
  final int? yearTo;
  final int minBpm;
  final int maxBpm;
  final String djContext;
}
