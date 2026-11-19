import 'dart:convert';
import 'dart:developer' as developer;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;

import '../core/config/music_genres.dart';
import '../core/utils/concurrency_limiter.dart';
import '../services/spotify_artist_service.dart';
import '../services/apple_music_artist_service.dart';
import '../services/youtube_search_service.dart';

/// Max concurrent external API calls per `search()` invocation. Capped below
/// the provider count so a multi-query [searchByGenre] loop does not fan out
/// every upstream request simultaneously.
const int _platformSearchConcurrency = 3;
const int _playbackEnrichmentLimit = 12;
const int _playbackEnrichmentProviderLimit = 3;

/// A lightweight track result from platform search (not a full Firestore Track).
class PlatformTrackResult {
  final String title;
  final String artist;
  final String? artworkUrl;
  final String? spotifyUrl;
  final String? appleUrl;
  final String? youtubeUrl;
  final String? deezerUrl;
  final String? soundchartsUrl;
  final String? soundchartsSource;
  final String? soundchartsRegion;
  final List<String> soundchartsRegions;
  final String? billboardUrl;
  final int? billboardRank;
  final String? spotifyChartRegion;
  final int? spotifyChartRank;
  final int? appleChartRank;
  final int? youtubeChartRank;
  final String? genre;
  final int durationMs;
  final int popularity;
  final double trendScore;

  const PlatformTrackResult({
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.spotifyUrl,
    this.appleUrl,
    this.youtubeUrl,
    this.deezerUrl,
    this.soundchartsUrl,
    this.soundchartsSource,
    this.soundchartsRegion,
    this.soundchartsRegions = const <String>[],
    this.billboardUrl,
    this.billboardRank,
    this.spotifyChartRegion,
    this.spotifyChartRank,
    this.appleChartRank,
    this.youtubeChartRank,
    this.genre,
    this.durationMs = 0,
    this.popularity = 0,
    this.trendScore = 0,
  });

  String get bestUrl =>
      appleUrl ??
      spotifyUrl ??
      youtubeUrl ??
      deezerUrl ??
      soundchartsUrl ??
      billboardUrl ??
      '';
  bool get hasUrl => bestUrl.isNotEmpty;

  bool get hasStreamingPlatformEvidence =>
      (spotifyUrl != null && spotifyUrl!.isNotEmpty) ||
      (appleUrl != null && appleUrl!.isNotEmpty) ||
      (youtubeUrl != null && youtubeUrl!.isNotEmpty) ||
      (deezerUrl != null && deezerUrl!.isNotEmpty);

  bool get hasRegionalChartEvidence =>
      (soundchartsUrl != null && soundchartsUrl!.isNotEmpty) ||
      (soundchartsSource != null && soundchartsSource!.isNotEmpty) ||
      (soundchartsRegion != null && soundchartsRegion!.isNotEmpty) ||
      soundchartsRegions.isNotEmpty ||
      appleChartRank != null ||
      spotifyChartRank != null ||
      billboardRank != null ||
      youtubeChartRank != null;

  bool get hasTrustedTrendEvidence =>
      hasRegionalChartEvidence ||
      billboardRank != null ||
      spotifyChartRank != null ||
      youtubeChartRank != null ||
      appleChartRank != null;

  bool hasChartEvidenceForRegion(String? region) {
    final requested = _normalizedRegionCode(region);
    if (requested == null) return hasRegionalChartEvidence;
    if (appleChartRank != null || youtubeChartRank != null) return true;
    if (billboardRank != null && requested == 'US') return true;
    if (spotifyChartRank != null &&
        _normalizedRegionCode(spotifyChartRegion) == requested) {
      return true;
    }
    final primaryRegion = _normalizedRegionCode(soundchartsRegion);
    if (primaryRegion == requested) return true;
    return soundchartsRegions.any(
      (candidate) => _normalizedRegionCode(candidate) == requested,
    );
  }

  /// Return a copy with [genre] replaced. Used to stamp the selected lane onto
  /// genre-discovered streaming rows that carry no genre of their own.
  PlatformTrackResult withGenre(String? genre) => PlatformTrackResult(
    title: title,
    artist: artist,
    artworkUrl: artworkUrl,
    spotifyUrl: spotifyUrl,
    appleUrl: appleUrl,
    youtubeUrl: youtubeUrl,
    deezerUrl: deezerUrl,
    soundchartsUrl: soundchartsUrl,
    soundchartsSource: soundchartsSource,
    soundchartsRegion: soundchartsRegion,
    soundchartsRegions: soundchartsRegions,
    billboardUrl: billboardUrl,
    billboardRank: billboardRank,
    spotifyChartRegion: spotifyChartRegion,
    spotifyChartRank: spotifyChartRank,
    appleChartRank: appleChartRank,
    youtubeChartRank: youtubeChartRank,
    genre: genre,
    durationMs: durationMs,
    popularity: popularity,
    trendScore: trendScore,
  );
}

/// Searches Soundcharts, Spotify, Apple Music, YouTube, and Deezer for tracks
/// by genre, artist, or freeform query. Returns merged, deduplicated results
/// with URLs from all live platforms.
///
/// Accepts an optional [functions] parameter so tests can supply a fake
/// [FirebaseFunctions] without initialising a live Firebase app.
class PlatformSearchService {
  PlatformSearchService({
    FirebaseFunctions? functions,
    SpotifyArtistService? spotify,
    AppleMusicArtistService? apple,
    YoutubeSearchService? youtube,
    http.Client? httpClient,
  }) : _injectedFunctions = functions,
       _spotify = spotify ?? SpotifyArtistService(functions: functions),
       _apple = apple ?? AppleMusicArtistService(functions: functions),
       _youtube = youtube ?? YoutubeSearchService(functions: functions),
       _httpClient = httpClient ?? http.Client();

  final FirebaseFunctions? _injectedFunctions;
  final SpotifyArtistService _spotify;
  final AppleMusicArtistService _apple;
  final YoutubeSearchService _youtube;
  final http.Client _httpClient;
  final Map<String, Future<List<PlatformTrackResult>>> _soundchartsCache = {};

  FirebaseFunctions get _functions =>
      _injectedFunctions ??
      FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Search all live platforms for tracks matching [query].
  /// Returns up to [limit] merged results.
  Future<List<PlatformTrackResult>> search(
    String query, {
    int limit = 50,
    String? region,
  }) {
    return _searchInternal(query, limit: limit, region: region);
  }

  /// Search only direct playback/catalog providers. This intentionally excludes
  /// Soundcharts and chart evidence for surfaces that should show music-service
  /// results only.
  Future<List<PlatformTrackResult>> searchMusicPlatforms(
    String query, {
    int limit = 50,
    String? region,
  }) async {
    final cleanRegion = _normalizeRegion(region);
    final results = await runLimited<List<PlatformTrackResult>>([
      () => _searchSpotify(query, limit: limit, region: cleanRegion),
      () => _searchApple(query, limit: limit, region: cleanRegion),
      () => _searchYouTube(query, limit: (limit * 0.6).round().clamp(5, 30)),
      () => _searchDeezer(query, limit: (limit * 0.6).round().clamp(5, 30)),
    ], maxConcurrent: _platformSearchConcurrency);

    final merged = _merge(
      const <PlatformTrackResult>[],
      const <PlatformTrackResult>[],
      results[0],
      results[1],
      results[2],
      results[3],
      limit: limit,
      region: cleanRegion,
      allowUnanchoredPlatformResults: true,
    );
    return enrichPlaybackLinksForResults(
      merged,
      region: cleanRegion,
      maxTracks: _playbackEnrichmentLimit,
    );
  }

  Future<List<PlatformTrackResult>> _searchInternal(
    String query, {
    int limit = 50,
    String? region,
    String? genreLane,
    bool enrichPlaybackLinks = true,
  }) async {
    final cleanRegion = _normalizeRegion(region);
    final lane = isSpecificGenre(genreLane) ? genreLane : null;
    final results = await runLimited<List<PlatformTrackResult>>([
      () => _searchSoundcharts(query, limit: limit, region: cleanRegion),
      () => _searchAppleCharts(query, limit: limit, region: cleanRegion),
      () => _searchSpotify(query, limit: limit, region: cleanRegion),
      () => _searchApple(query, limit: limit, region: cleanRegion),
      () => _searchYouTube(query, limit: (limit * 0.6).round().clamp(5, 30)),
      () => _searchDeezer(query, limit: (limit * 0.6).round().clamp(5, 30)),
    ], maxConcurrent: _platformSearchConcurrency);

    final soundchartsResults = results[0];
    final appleChartResults = results[1];
    final spotifyResults = results[2];
    final appleResults = results[3];
    final youtubeResults = results[4];
    final deezerResults = results[5];

    final merged = _merge(
      soundchartsResults,
      appleChartResults,
      spotifyResults,
      appleResults,
      youtubeResults,
      deezerResults,
      limit: limit,
      region: cleanRegion,
      genre: lane,
      allowUnanchoredPlatformResults: true,
    );
    final stamped = _stampLaneGenre(merged, lane);
    if (!enrichPlaybackLinks) return stamped;
    return enrichPlaybackLinksForResults(
      stamped,
      region: cleanRegion,
      maxTracks: _playbackEnrichmentLimit,
    );
  }

  /// Stamp [lane] onto genre-discovered streaming rows that have no genre of
  /// their own. A pure chart row (chart evidence, no streaming URL) keeps its
  /// unknown genre so it is never mislabeled; a row with a real genre is left
  /// untouched. Without this, the downstream genre filter discards every
  /// streaming result returned by a genre-scoped query.
  List<PlatformTrackResult> _stampLaneGenre(
    List<PlatformTrackResult> rows,
    String? lane,
  ) {
    if (lane == null) return rows;
    return rows.map((row) {
      if (isSpecificGenre(row.genre)) return row;
      if (row.hasRegionalChartEvidence && !row.hasStreamingPlatformEvidence) {
        return row;
      }
      return row.withGenre(lane);
    }).toList();
  }

  /// Fetch live trending rows from chart evidence first, then use playback
  /// platforms only to enrich those chart anchors. Standalone platform search
  /// rows are too noisy for a "Top Trending" feed.
  Future<List<PlatformTrackResult>> fetchTrendingChartTracks({
    String? region,
    String? genre,
    int limit = 100,
  }) async {
    final cleanRegion = _normalizeRegion(region);
    final lane = isSpecificGenre(genre) ? genre : null;
    // When a specific genre is selected it drives retrieval: chart feeds are
    // filtered to genre-relevant rows and platform searches query the lane.
    // Otherwise this stays the broad regional trending fetch.
    final platformQuery = lane != null
        ? _genreTrendingQuery(lane, cleanRegion)
        : _trendingPlatformQuery(cleanRegion);
    final chartQuery = lane ?? '';
    final results = await runLimited<List<PlatformTrackResult>>([
      () => _searchSoundcharts(chartQuery, limit: limit, region: cleanRegion),
      // A specific genre with an Apple genre id is sourced from Apple's genre
      // chart (the same list Apple shows when you select a genre); otherwise the
      // global storefront chart filtered by genre tokens.
      () => lane != null && appleGenreFor(lane) != null
          ? _searchAppleGenreChart(lane, limit: limit, region: cleanRegion)
          : _searchAppleCharts(chartQuery, limit: limit, region: cleanRegion),
      () => _searchBillboardCharts(chartQuery, limit: limit),
      () => _searchSpotifyCharts(chartQuery, limit: limit, region: cleanRegion),
      () => _searchYouTubeCharts(
        limit: (limit * 0.5).round().clamp(5, 30),
        region: cleanRegion,
      ),
      () => _searchSpotify(platformQuery, limit: limit, region: cleanRegion),
      () => _searchApple(platformQuery, limit: limit, region: cleanRegion),
      () => _searchDeezer(
        platformQuery,
        limit: (limit * 0.5).round().clamp(5, 30),
      ),
    ], maxConcurrent: _platformSearchConcurrency);
    final merged = _merge(
      results[0],
      results[1],
      results[5],
      results[6],
      const <PlatformTrackResult>[],
      results[7],
      limit: limit,
      region: cleanRegion,
      genre: lane,
      allowUnanchoredPlatformResults: lane != null,
      billboard: results[2],
      spotifyCharts: results[3],
      youtubeCharts: results[4],
    );
    return enrichPlaybackLinksForResults(
      _stampLaneGenre(merged, lane),
      region: cleanRegion,
      maxTracks: _playbackEnrichmentLimit,
    );
  }

  /// Search for tracks by genre. Searches multiple representative queries
  /// for broader coverage.
  Future<List<PlatformTrackResult>> searchByGenre(
    String genre, {
    int limit = 100,
    String? era,
    String? region,
    String? genreLane,
  }) async {
    final lane = isSpecificGenre(genreLane) ? genreLane : null;
    final queries = <String>[
      genre,
      '$genre music',
      'best $genre songs',
      'top $genre hits',
      '$genre playlist',
      '$genre new releases',
      'popular $genre',
      '$genre classics',
      '$genre party',
      '$genre mix',
    ];

    if (era != null && era != 'All') {
      queries.add('$genre $era hits');
      queries.add('best $genre songs $era');
      queries.add('$genre $era classics');
    }

    final allResults = <PlatformTrackResult>[];
    final seen = <String>{};

    // Apple Music's genre chart leads — its curated genre top-songs are the same
    // list Apple shows when you select a genre. The keyword queries below fill
    // in the rest (and cover lanes with no Apple genre).
    if (lane != null && appleGenreFor(lane) != null) {
      final chart = await _searchAppleGenreChart(
        lane,
        limit: limit,
        region: region,
      );
      for (final r in chart) {
        final key = '${r.title.toLowerCase()}::${r.artist.toLowerCase()}';
        if (seen.add(key)) allResults.add(r);
      }
    }

    for (final query in queries) {
      if (allResults.length >= limit) break;

      final batchSize = (limit - allResults.length).clamp(20, 50);
      final batch = await _searchInternal(
        query,
        limit: batchSize,
        region: region,
        genreLane: lane,
        enrichPlaybackLinks: false,
      );
      for (final r in batch) {
        final key = '${r.title.toLowerCase()}::${r.artist.toLowerCase()}';
        if (!seen.contains(key)) {
          seen.add(key);
          allResults.add(r);
        }
      }
    }

    allResults.sort(
      (a, b) => _selectionScore(
        b,
        region: region,
        genre: lane,
      ).compareTo(_selectionScore(a, region: region, genre: lane)),
    );
    return enrichPlaybackLinksForResults(
      allResults.take(limit).toList(),
      region: region,
      maxTracks: _playbackEnrichmentLimit,
    );
  }

  /// Search for tracks by a specific artist.
  Future<List<PlatformTrackResult>> searchByArtist(
    String artistName, {
    int limit = 50,
    String? region,
  }) async {
    final artists = artistName
        .split(',')
        .map((a) => a.trim())
        .where((a) => a.isNotEmpty)
        .toList();
    final allResults = <PlatformTrackResult>[];
    final seen = <String>{};

    for (final artist in artists) {
      final perArtist = (limit / artists.length).ceil().clamp(10, limit);
      final batch = await _searchInternal(
        artist,
        limit: perArtist,
        region: region,
        enrichPlaybackLinks: false,
      );
      for (final r in batch) {
        final key = '${r.title.toLowerCase()}::${r.artist.toLowerCase()}';
        if (!seen.contains(key)) {
          seen.add(key);
          allResults.add(r);
        }
      }
    }

    final results = allResults.isNotEmpty
        ? allResults
        : await _searchInternal(
            artistName,
            limit: limit,
            region: region,
            enrichPlaybackLinks: false,
          );
    // Filter: keep tracks where ANY of the searched artist names appear
    final normalizedParts = artists.map((a) => a.toLowerCase()).toList();
    final filtered = results.where((r) {
      final rArtist = r.artist.toLowerCase();
      return normalizedParts.any(
        (a) => rArtist.contains(a) || a.contains(rArtist),
      );
    }).toList();
    return enrichPlaybackLinksForResults(
      filtered.isEmpty
          ? results.take(limit).toList()
          : filtered.take(limit).toList(),
      region: region,
      maxTracks: _playbackEnrichmentLimit,
    );
  }

  Future<List<PlatformTrackResult>> enrichPlaybackLinksForResults(
    List<PlatformTrackResult> results, {
    String? region,
    int maxTracks = _playbackEnrichmentLimit,
  }) async {
    if (results.isEmpty || maxTracks <= 0) return results;
    final cleanRegion = _normalizeRegion(region);
    final enriched = [...results];
    var remaining = maxTracks;

    for (var i = 0; i < enriched.length && remaining > 0; i += 1) {
      final result = enriched[i];
      if (!_needsPlaybackLinkEnrichment(result)) continue;
      remaining -= 1;

      final query = '${result.title} ${result.artist}'.trim();
      if (query.isEmpty) continue;
      final batches = await runLimited<List<PlatformTrackResult>>([
        () => result.spotifyUrl == null || result.spotifyUrl!.isEmpty
            ? _searchSpotify(
                query,
                limit: _playbackEnrichmentProviderLimit,
                region: cleanRegion,
              )
            : Future.value(const <PlatformTrackResult>[]),
        () => result.appleUrl == null || result.appleUrl!.isEmpty
            ? _searchApple(
                query,
                limit: _playbackEnrichmentProviderLimit,
                region: cleanRegion,
              )
            : Future.value(const <PlatformTrackResult>[]),
        () => result.youtubeUrl == null || result.youtubeUrl!.isEmpty
            ? _searchYouTube(query, limit: _playbackEnrichmentProviderLimit)
            : Future.value(const <PlatformTrackResult>[]),
        () => result.deezerUrl == null || result.deezerUrl!.isEmpty
            ? _searchDeezer(query, limit: _playbackEnrichmentProviderLimit)
            : Future.value(const <PlatformTrackResult>[]),
      ], maxConcurrent: _platformSearchConcurrency);

      final spotify = _bestPlaybackMatch(batches[0], result);
      final apple = _bestPlaybackMatch(batches[1], result);
      final youtube = _bestPlaybackMatch(
        batches[2],
        result,
        allowTitleOnlyWhenArtistIsInTitle: true,
      );
      final deezer = _bestPlaybackMatch(batches[3], result);
      final patch = PlatformTrackResult(
        title: result.title,
        artist: result.artist,
        artworkUrl:
            spotify?.artworkUrl ??
            apple?.artworkUrl ??
            youtube?.artworkUrl ??
            deezer?.artworkUrl,
        spotifyUrl: spotify?.spotifyUrl,
        appleUrl: apple?.appleUrl,
        youtubeUrl: youtube?.youtubeUrl,
        deezerUrl: deezer?.deezerUrl,
        durationMs:
            spotify?.durationMs ??
            apple?.durationMs ??
            deezer?.durationMs ??
            result.durationMs,
        popularity: [
          result.popularity,
          spotify?.popularity ?? 0,
          apple?.popularity ?? 0,
          deezer?.popularity ?? 0,
        ].reduce((a, b) => a > b ? a : b),
        genre: apple?.genre ?? deezer?.genre,
      );
      enriched[i] = _combine(result, patch);
    }

    return enriched;
  }

  Future<List<PlatformTrackResult>> _searchSoundcharts(
    String query, {
    int limit = 50,
    String? region,
  }) {
    final cleanRegion = _normalizeRegion(region);
    // Canonicalize to meaningful tokens: the server strips the same stopwords,
    // so "best music songs" / "top music hits" / "music playlist" are all the
    // identical request. Deduplicating here turns a multi-query fan-out into
    // one network call instead of N identical 15-second proxy round-trips.
    final canonicalQuery = _selectionTokens(query).join(' ');
    final cacheKey = [
      canonicalQuery,
      cleanRegion ?? 'all',
      limit.clamp(1, 100),
    ].join('|');
    return _soundchartsCache.putIfAbsent(
      cacheKey,
      () =>
          _fetchSoundcharts(canonicalQuery, limit: limit, region: cleanRegion),
    );
  }

  Future<List<PlatformTrackResult>> _fetchSoundcharts(
    String query, {
    int limit = 50,
    String? region,
  }) async {
    try {
      final callable = _functions.httpsCallable('soundchartsProxy');
      final payload = <String, dynamic>{
        'query': query,
        'limit': limit.clamp(1, 100),
        'region': region ?? 'Global',
      };
      final result = await callable.call(payload);
      final data = Map<String, dynamic>.from(result.data as Map);
      final tracks = data['tracks'] as List? ?? const [];
      return tracks
          .whereType<Map<Object?, Object?>>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .map(
            (track) => PlatformTrackResult(
              title: _asString(track['title'], fallback: 'Untitled'),
              artist: _asString(track['artist'], fallback: 'Unknown Artist'),
              artworkUrl: _optionalString(track['artworkUrl']),
              soundchartsUrl: _optionalString(track['soundchartsUrl']),
              soundchartsSource: _optionalString(track['source']),
              soundchartsRegion: _optionalString(track['region']),
              soundchartsRegions: _stringList(track['regions']),
              genre: _optionalString(track['genre']),
              popularity: _asInt(track['popularity']),
              trendScore: _asDouble(track['trendScore']),
            ),
          )
          .where((track) => track.soundchartsUrl != null)
          .toList();
    } catch (error) {
      developer.log(
        'Soundcharts search failed for "$query"',
        name: 'PlatformSearch',
        error: error,
      );
      return [];
    }
  }

  Future<List<PlatformTrackResult>> _searchBillboardCharts(
    String query, {
    int limit = 50,
  }) async {
    try {
      final uri = Uri.parse(
        'https://raw.githubusercontent.com/mhollingshead/billboard-hot-100/main/recent.json',
      );
      final response = await _httpClient.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'Billboard chart fetch failed: ${response.statusCode}',
        );
      }
      final decoded = jsonDecode(response.body);
      final chart = decoded is List && decoded.isNotEmpty
          ? decoded.last
          : decoded is Map
          ? decoded
          : null;
      if (chart is! Map) return const [];

      final tokens = _selectionTokens(query);
      final rows = chart['data'] is List ? chart['data'] as List : const [];
      return rows
          .whereType<Map<Object?, Object?>>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .map((song) {
            final position = _asInt(song['this_week']).clamp(1, 100);
            final title = _asString(
              song['song'] ?? song['name'],
              fallback: 'Untitled',
            );
            final artist = _asString(
              song['artist'],
              fallback: 'Unknown Artist',
            );
            return PlatformTrackResult(
              title: title,
              artist: artist,
              billboardUrl: 'https://www.billboard.com/charts/hot-100/',
              billboardRank: position,
              popularity: (101 - position).clamp(1, 100).toInt(),
              trendScore: ((101 - position) / 100).clamp(0.05, 1.0).toDouble(),
            );
          })
          .where((track) => _isTrustedChartCandidate(track))
          .where(
            (track) =>
                tokens.isEmpty ||
                tokens.any(
                  (token) =>
                      track.title.toLowerCase().contains(token) ||
                      track.artist.toLowerCase().contains(token),
                ),
          )
          .take(limit)
          .toList();
    } catch (error) {
      developer.log(
        'Billboard chart search failed for "$query"',
        name: 'PlatformSearch',
        error: error,
      );
      return [];
    }
  }

  Future<List<PlatformTrackResult>> _searchSpotifyCharts(
    String query, {
    int limit = 50,
    String? region,
  }) async {
    final country = _kworbSpotifyCountryForRegion(region);
    final chartRegion = country == 'global' ? 'GLOBAL' : country.toUpperCase();
    try {
      final uri = Uri.https(
        'kworb.net',
        '/spotify/country/${country}_daily.html',
      );
      final response = await _httpClient.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Spotify chart fetch failed: ${response.statusCode}');
      }
      final tokens = _selectionTokens(query);
      return _parseKworbSpotifyChart(
            response.body,
            chartRegion: chartRegion,
            limit: limit,
          )
          .where(_isTrustedChartCandidate)
          .where(
            (track) =>
                tokens.isEmpty ||
                tokens.any(
                  (token) =>
                      track.title.toLowerCase().contains(token) ||
                      track.artist.toLowerCase().contains(token),
                ),
          )
          .toList();
    } catch (error) {
      developer.log(
        'Spotify chart search failed for "$query" in "$region"',
        name: 'PlatformSearch',
        error: error,
      );
      return [];
    }
  }

  List<PlatformTrackResult> _parseKworbSpotifyChart(
    String html, {
    required String chartRegion,
    required int limit,
  }) {
    final rows = RegExp(
      r'<tr[^>]*>(.*?)</tr>',
      dotAll: true,
      caseSensitive: false,
    ).allMatches(html);
    final results = <PlatformTrackResult>[];
    for (final rowMatch in rows) {
      if (results.length >= limit) break;
      final row = rowMatch.group(1) ?? '';
      final rank = _asInt(
        RegExp(
          r'<td class="np">(\d+)</td>',
          caseSensitive: false,
        ).firstMatch(row)?.group(1),
      );
      if (rank <= 0) continue;

      final titleCell = RegExp(
        r'<td class="text mp"><div>(.*?)</div></td>',
        dotAll: true,
        caseSensitive: false,
      ).firstMatch(row)?.group(1);
      if (titleCell == null) continue;

      final trackMatch = RegExp(
        r'^(.*?)\s+-\s+<a href="\.\./track/([^"]+)">(.*?)</a>',
        dotAll: true,
        caseSensitive: false,
      ).firstMatch(titleCell);
      if (trackMatch == null) continue;

      final artist = _decodeHtml(_stripHtml(trackMatch.group(1) ?? ''));
      final title = _decodeHtml(_stripHtml(trackMatch.group(3) ?? ''));
      final trackPath = trackMatch.group(2) ?? '';
      final trackId = trackPath.split('/').last.replaceAll('.html', '').trim();
      if (artist.isEmpty || title.isEmpty || trackId.isEmpty) continue;

      results.add(
        PlatformTrackResult(
          title: title,
          artist: artist,
          spotifyUrl: 'https://open.spotify.com/track/$trackId',
          spotifyChartRegion: chartRegion,
          spotifyChartRank: rank,
          popularity: (101 - rank.clamp(1, 100)).clamp(1, 100).toInt(),
          trendScore: ((101 - rank.clamp(1, 100)) / 100)
              .clamp(0.05, 1.0)
              .toDouble(),
        ),
      );
    }
    return results;
  }

  Future<List<PlatformTrackResult>> _searchSpotify(
    String query, {
    int limit = 50,
    String? region,
  }) async {
    try {
      final results = await _spotify.searchTracks(
        query,
        limit: limit,
        market: _marketForRegion(region),
      );
      return results
          .map(
            (t) => PlatformTrackResult(
              title: t.name,
              artist: t.artists,
              artworkUrl: t.albumArt,
              spotifyUrl: t.spotifyUrl,
              durationMs: t.durationMs,
              popularity: t.popularity,
            ),
          )
          .toList();
    } catch (error) {
      developer.log(
        'Spotify search failed for "$query"',
        name: 'PlatformSearch',
        error: error,
      );
      return [];
    }
  }

  Future<List<PlatformTrackResult>> _searchApple(
    String query, {
    int limit = 50,
    String? region,
  }) async {
    try {
      final results = await _apple.searchSongs(
        query,
        limit: limit,
        region: region,
      );
      return results
          .map(
            (t) => PlatformTrackResult(
              title: t.name,
              artist: t.artistName,
              artworkUrl: t.artworkUrl,
              appleUrl: t.appleUrl,
              durationMs: t.durationMs,
              genre: t.genreNames.isEmpty ? null : t.genreNames.first,
            ),
          )
          .toList();
    } catch (error) {
      developer.log(
        'Apple Music search failed for "$query"',
        name: 'PlatformSearch',
        error: error,
      );
      return [];
    }
  }

  Future<List<PlatformTrackResult>> _searchAppleCharts(
    String query, {
    int limit = 50,
    String? region,
  }) async {
    if (region == null) return [];
    try {
      final results = await _apple.getChartSongs(
        limit: limit.clamp(1, 100),
        region: region,
      );
      final tokens = _selectionTokens(query);
      final filtered = tokens.isEmpty
          ? results
          : results.where((track) => _appleChartMatches(track, tokens));
      var rank = 0;
      return filtered.map((t) {
        rank += 1;
        return PlatformTrackResult(
          title: t.name,
          artist: t.artistName,
          artworkUrl: t.artworkUrl,
          appleUrl: t.appleUrl,
          durationMs: t.durationMs,
          appleChartRank: rank,
          genre: t.genreNames.isEmpty ? null : t.genreNames.first,
          popularity: (101 - rank).clamp(1, 100).toInt(),
          trendScore: ((101 - rank).clamp(1, 100) / 100).toDouble(),
        );
      }).toList();
    } catch (error) {
      developer.log(
        'Apple Music chart search failed for "$query" in "$region"',
        name: 'PlatformSearch',
        error: error,
      );
      return [];
    }
  }

  /// Source a selected genre from Apple Music's genre chart — the curated top
  /// songs for that genre, the same list Apple Music shows when you tap a genre.
  /// Rows carry [appleChartRank] (so they count as chart evidence for any region)
  /// and are stamped with the selected [lane]. Returns [] when the lane has no
  /// Apple genre id, so callers fall back to keyword search.
  Future<List<PlatformTrackResult>> _searchAppleGenreChart(
    String lane, {
    int limit = 50,
    String? region,
  }) async {
    final mapping = appleGenreFor(lane);
    if (mapping == null) return [];
    try {
      final results = await _apple.getGenreChartSongs(
        genreId: mapping.id,
        limit: limit.clamp(1, 100),
        region: region,
        preferredStorefronts: mapping.preferredStorefronts,
      );
      var rank = 0;
      return results.map((t) {
        rank += 1;
        return PlatformTrackResult(
          title: t.name,
          artist: t.artistName,
          artworkUrl: t.artworkUrl,
          appleUrl: t.appleUrl,
          durationMs: t.durationMs,
          appleChartRank: rank,
          genre: lane,
          popularity: (101 - rank).clamp(1, 100).toInt(),
          trendScore: ((101 - rank).clamp(1, 100) / 100).toDouble(),
        );
      }).toList();
    } catch (error) {
      developer.log(
        'Apple Music genre chart failed for "$lane" in "$region"',
        name: 'PlatformSearch',
        error: error,
      );
      return [];
    }
  }

  Future<List<PlatformTrackResult>> _searchYouTube(
    String query, {
    int limit = 15,
  }) async {
    try {
      final results = await _youtube.searchMusic(query, limit: limit);
      return results
          .map(
            (v) => PlatformTrackResult(
              title: v.title,
              artist: v.channelName,
              artworkUrl: v.thumbnailUrl,
              youtubeUrl: v.youtubeUrl,
            ),
          )
          .toList();
    } catch (error) {
      developer.log(
        'YouTube search failed for "$query"',
        name: 'PlatformSearch',
        error: error,
      );
      return [];
    }
  }

  Future<List<PlatformTrackResult>> _searchYouTubeCharts({
    int limit = 20,
    String? region,
  }) async {
    try {
      final results = await _youtube.fetchTrendingMusic(
        limit: limit,
        region: _marketForRegion(region),
      );
      var rank = 0;
      return results
          .map((v) {
            rank += 1;
            return PlatformTrackResult(
              title: v.title,
              artist: v.channelName,
              artworkUrl: v.thumbnailUrl,
              youtubeUrl: v.youtubeUrl,
              youtubeChartRank: rank,
              popularity: (101 - rank.clamp(1, 100)).clamp(1, 100).toInt(),
              trendScore: ((101 - rank.clamp(1, 100)) / 100)
                  .clamp(0.05, 1.0)
                  .toDouble(),
            );
          })
          .where(_isTrustedChartCandidate)
          .toList();
    } catch (error) {
      developer.log(
        'YouTube chart search failed for "$region"',
        name: 'PlatformSearch',
        error: error,
      );
      return [];
    }
  }

  Future<List<PlatformTrackResult>> _searchDeezer(
    String query, {
    int limit = 15,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    try {
      final uri = Uri.https('api.deezer.com', '/search/track', {
        'q': trimmed,
        'limit': '${limit.clamp(1, 50)}',
      });
      final response = await _httpClient.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Deezer search failed: ${response.statusCode}');
      }
      final decoded = jsonDecode(response.body);
      final items = decoded is Map ? decoded['data'] as List? : null;
      return (items ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .map((track) {
            final artist = track['artist'] is Map
                ? Map<String, dynamic>.from(track['artist'] as Map)
                : const <String, dynamic>{};
            final album = track['album'] is Map
                ? Map<String, dynamic>.from(track['album'] as Map)
                : const <String, dynamic>{};
            final deezerUrl = _optionalString(track['link']);
            return PlatformTrackResult(
              title: _asString(
                track['title_short'] ?? track['title'],
                fallback: 'Untitled',
              ),
              artist: _asString(artist['name'], fallback: 'Unknown Artist'),
              artworkUrl: _optionalString(
                album['cover_medium'] ?? album['cover_big'] ?? album['cover'],
              ),
              deezerUrl: deezerUrl,
              durationMs: _asInt(track['duration']) * 1000,
              popularity: _asInt(track['rank']).clamp(0, 1000000) ~/ 10000,
            );
          })
          .where((track) => track.deezerUrl != null)
          .toList();
    } catch (error) {
      developer.log(
        'Deezer search failed for "$query"',
        name: 'PlatformSearch',
        error: error,
      );
      return [];
    }
  }

  /// Merge Soundcharts, Spotify, Apple Music, YouTube, and Deezer results,
  /// deduplicating by title+artist.
  List<PlatformTrackResult> _merge(
    List<PlatformTrackResult> soundcharts,
    List<PlatformTrackResult> appleCharts,
    List<PlatformTrackResult> spotify,
    List<PlatformTrackResult> apple,
    List<PlatformTrackResult> youtube,
    List<PlatformTrackResult> deezer, {
    int limit = 50,
    String? region,
    String? genre,
    bool allowUnanchoredPlatformResults = true,
    List<PlatformTrackResult> billboard = const <PlatformTrackResult>[],
    List<PlatformTrackResult> spotifyCharts = const <PlatformTrackResult>[],
    List<PlatformTrackResult> youtubeCharts = const <PlatformTrackResult>[],
  }) {
    final map = <String, PlatformTrackResult>{};

    // Chart evidence first so later streaming-platform rows enrich it instead
    // of replacing stronger regional metadata.
    for (final t in soundcharts) {
      final key = _normalizeKey(t.title, t.artist);
      map[key] = t;
    }

    for (final t in appleCharts) {
      final key = _normalizeKey(t.title, t.artist);
      map[key] = map.containsKey(key) ? _combine(map[key]!, t) : t;
    }

    for (final t in billboard) {
      final key = _normalizeKey(t.title, t.artist);
      map[key] = map.containsKey(key) ? _combine(map[key]!, t) : t;
    }

    for (final t in spotifyCharts) {
      final key = _normalizeKey(t.title, t.artist);
      map[key] = map.containsKey(key) ? _combine(map[key]!, t) : t;
    }

    for (final t in youtubeCharts) {
      final key = _normalizeKey(t.title, t.artist);
      if (map.containsKey(key)) {
        map[key] = _combine(map[key]!, t);
      } else {
        final fuzzyKey = _fuzzyMatchKey(t.title, t.artist, map.keys);
        if (fuzzyKey != null) {
          map[fuzzyKey] = _combine(map[fuzzyKey]!, t);
        } else {
          map[key] = t;
        }
      }
    }

    final allowNewPlatformRows = allowUnanchoredPlatformResults;

    for (final t in spotify) {
      final key = _normalizeKey(t.title, t.artist);
      if (map.containsKey(key)) {
        map[key] = _combine(map[key]!, t);
      } else if (allowNewPlatformRows) {
        map[key] = t;
      }
    }

    for (final t in apple) {
      final key = _normalizeKey(t.title, t.artist);
      if (map.containsKey(key)) {
        map[key] = _combine(map[key]!, t);
      } else if (allowNewPlatformRows) {
        map[key] = t;
      }
    }

    for (final t in youtube) {
      final key = _normalizeKey(t.title, t.artist);
      if (map.containsKey(key)) {
        map[key] = _combine(map[key]!, t);
      } else {
        final fuzzyKey = _fuzzyMatchKey(t.title, t.artist, map.keys);
        if (fuzzyKey != null) {
          map[fuzzyKey] = _combine(map[fuzzyKey]!, t);
        } else if (allowNewPlatformRows) {
          map[key] = t;
        }
      }
    }

    for (final t in deezer) {
      final key = _normalizeKey(t.title, t.artist);
      if (map.containsKey(key)) {
        map[key] = _combine(map[key]!, t);
      } else if (allowNewPlatformRows) {
        map[key] = t;
      }
    }

    // When a specific genre is the active criterion, drop rows with a known,
    // non-matching genre (e.g. a #1 Country chart hit during a House selection).
    // Chart rank should only rank tracks *within* the chosen lane; unknown-genre
    // rows stay because a genre-scoped query already vouches for them.
    final lane = isSpecificGenre(genre) ? genre : null;
    final entries = lane == null
        ? map.values
        : map.values.where(
            (t) => !isSpecificGenre(t.genre) || genreMatches(t.genre, lane),
          );

    final merged = entries.toList()
      ..sort(
        (a, b) => _selectionScore(
          b,
          region: region,
          genre: lane,
        ).compareTo(_selectionScore(a, region: region, genre: lane)),
      );
    return merged.take(limit).toList();
  }

  PlatformTrackResult _combine(
    PlatformTrackResult existing,
    PlatformTrackResult incoming,
  ) {
    return PlatformTrackResult(
      title: existing.title,
      artist: existing.artist,
      artworkUrl: existing.artworkUrl ?? incoming.artworkUrl,
      spotifyUrl: existing.spotifyUrl ?? incoming.spotifyUrl,
      appleUrl: existing.appleUrl ?? incoming.appleUrl,
      youtubeUrl: existing.youtubeUrl ?? incoming.youtubeUrl,
      deezerUrl: existing.deezerUrl ?? incoming.deezerUrl,
      soundchartsUrl: existing.soundchartsUrl ?? incoming.soundchartsUrl,
      soundchartsSource:
          existing.soundchartsSource ?? incoming.soundchartsSource,
      soundchartsRegion:
          existing.soundchartsRegion ?? incoming.soundchartsRegion,
      soundchartsRegions: _mergeRegions(
        existing.soundchartsRegions,
        incoming.soundchartsRegions,
      ),
      billboardUrl: existing.billboardUrl ?? incoming.billboardUrl,
      billboardRank: _bestChartRank(
        existing.billboardRank,
        incoming.billboardRank,
      ),
      spotifyChartRegion:
          existing.spotifyChartRegion ?? incoming.spotifyChartRegion,
      spotifyChartRank: _bestChartRank(
        existing.spotifyChartRank,
        incoming.spotifyChartRank,
      ),
      appleChartRank: _bestAppleChartRank(
        existing.appleChartRank,
        incoming.appleChartRank,
      ),
      youtubeChartRank: _bestChartRank(
        existing.youtubeChartRank,
        incoming.youtubeChartRank,
      ),
      genre: existing.genre ?? incoming.genre,
      durationMs: existing.durationMs > 0
          ? existing.durationMs
          : incoming.durationMs,
      popularity: existing.popularity > incoming.popularity
          ? existing.popularity
          : incoming.popularity,
      trendScore: existing.trendScore > incoming.trendScore
          ? existing.trendScore
          : incoming.trendScore,
    );
  }

  int? _bestAppleChartRank(int? first, int? second) {
    return _bestChartRank(first, second);
  }

  int? _bestChartRank(int? first, int? second) {
    if (first == null) return second;
    if (second == null) return first;
    return first < second ? first : second;
  }

  String? _normalizeRegion(String? region) {
    return _normalizedRegionCode(region);
  }

  String? _optionalString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _asString(Object? value, {required String fallback}) {
    final result = _optionalString(value);
    return result ?? fallback;
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  List<String> _stringList(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .whereType<String>()
        .map((item) => item.trim().toUpperCase())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  List<String> _mergeRegions(List<String> first, List<String> second) {
    return {
      ...first
          .map((item) => item.trim().toUpperCase())
          .where((item) => item.isNotEmpty),
      ...second
          .map((item) => item.trim().toUpperCase())
          .where((item) => item.isNotEmpty),
    }.toList()..sort();
  }

  double _asDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _marketForRegion(String? region) {
    final value = _normalizeRegion(region);
    if (value == null) return 'US';
    return value.length == 2 ? value : 'US';
  }

  String _kworbSpotifyCountryForRegion(String? region) {
    final code = _normalizeRegion(region)?.toLowerCase();
    if (code != null && _kworbSpotifyCountryCodes.contains(code)) {
      return code;
    }
    return 'global';
  }

  String _trendingPlatformQuery(String? region) {
    final normalized = _normalizeRegion(region);
    return switch (normalized) {
      'GH' => 'Ghana hits',
      'NG' => 'Nigeria hits',
      'ZA' => 'South Africa hits',
      'GB' => 'UK hits',
      'US' => 'US hits',
      'CA' => 'Canada hits',
      'AU' => 'Australia hits',
      'FR' => 'France hits',
      'DE' => 'Germany hits',
      null => 'global hits',
      _ => '$normalized hits',
    };
  }

  /// Genre-scoped trending query. The region market is already passed to the
  /// Spotify/Apple searches, so the query itself stays lane-focused (and is
  /// canonicalized server-side for Soundcharts), e.g. "House hits".
  String _genreTrendingQuery(String genre, String? region) {
    final lane = genre.trim();
    return lane.isEmpty ? _trendingPlatformQuery(region) : '$lane hits';
  }

  bool _appleChartMatches(AppleMusicTrack track, List<String> tokens) {
    final text = [
      track.name,
      track.artistName,
      track.albumName,
      ...track.genreNames,
    ].join(' ').toLowerCase();
    return tokens.any(text.contains);
  }

  List<String> _selectionTokens(String query) {
    final seen = <String>{};
    return query
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .map((token) => token.trim())
        .where((token) {
          if (token.length < 3) return false;
          if (_selectionStopwords.contains(token)) return false;
          if (int.tryParse(token) != null) return false;
          return seen.add(token);
        })
        .toList();
  }

  double _selectionScore(
    PlatformTrackResult track, {
    String? region,
    String? genre,
  }) {
    var score =
        track.popularity.clamp(0, 100).toDouble() +
        track.trendScore.clamp(0, 1) * 80;
    if (track.soundchartsUrl != null && track.soundchartsUrl!.isNotEmpty) {
      score += 130;
    }
    if (track.soundchartsSource != null &&
        track.soundchartsSource!.isNotEmpty) {
      score += 40;
    }
    if (track.appleChartRank != null) {
      score += 125 + (101 - track.appleChartRank!.clamp(1, 100));
    }
    if (track.billboardRank != null) {
      score += 145 + (101 - track.billboardRank!.clamp(1, 100));
    }
    if (track.spotifyChartRank != null) {
      score += 135 + (101 - track.spotifyChartRank!.clamp(1, 100));
    }
    if (track.youtubeChartRank != null) {
      score += 95 + (101 - track.youtubeChartRank!.clamp(1, 100));
    }

    final trendSourceCount = _trendSourceCount(track);
    if (trendSourceCount > 1) {
      score += (trendSourceCount - 1) * 85;
    } else if (track.youtubeChartRank != null) {
      score -= 90;
    }

    final genreActive = isSpecificGenre(genre);
    final requestedRegion = _normalizeRegion(region);
    if (requestedRegion != null) {
      // A selected genre already narrows relevance, so region becomes a gentle
      // re-ranker rather than a near-veto on otherwise-perfect genre matches.
      if (track.hasChartEvidenceForRegion(requestedRegion)) {
        score += 85;
      } else if (track.hasRegionalChartEvidence) {
        score -= genreActive ? 15 : 45;
      } else if (track.hasStreamingPlatformEvidence) {
        score -= genreActive ? 5 : 15;
      } else {
        score -= genreActive ? 40 : 120;
      }
    }

    // Genre fit is a first-class signal when a lane is chosen: reward matches,
    // and lightly favor unknown-genre rows (which a genre-scoped query implies)
    // over nothing.
    if (genreActive) {
      if (genreMatches(track.genre, genre!)) {
        score += 70;
      } else if (!isSpecificGenre(track.genre)) {
        score += 8;
      }
    }

    final platformCount = [
      track.spotifyUrl,
      track.appleUrl,
      track.youtubeUrl,
      track.deezerUrl,
      track.soundchartsUrl,
      track.billboardUrl,
    ].where((url) => url != null && url.isNotEmpty).length;
    score += platformCount * 3;
    return score;
  }

  int _trendSourceCount(PlatformTrackResult track) {
    var count = 0;
    if (track.soundchartsUrl != null ||
        track.soundchartsSource != null ||
        track.soundchartsRegion != null ||
        track.soundchartsRegions.isNotEmpty) {
      count += 1;
    }
    if (track.appleChartRank != null) count += 1;
    if (track.billboardRank != null) count += 1;
    if (track.spotifyChartRank != null) count += 1;
    if (track.youtubeChartRank != null) count += 1;
    return count;
  }

  bool _isTrustedChartCandidate(PlatformTrackResult track) {
    final title = track.title.trim();
    final artist = track.artist.trim();
    if (title.isEmpty || artist.isEmpty) return false;
    final text = '$title $artist'.toLowerCase();
    final blocked = <RegExp>[
      RegExp(r'\binstrumental\b'),
      RegExp(r'\bkaraoke\b'),
      RegExp(r'\bcover\b'),
      RegExp(r'\btype\s+beat\b'),
      RegExp(r'\bfree\s+beat\b'),
      RegExp(r'\breaction\b'),
      RegExp(r'\btutorial\b'),
      RegExp(r'\bsped\s+up\b'),
      RegExp(r'\bslowed\b'),
      RegExp(r'\bnightcore\b'),
      RegExp(r'\b8d\b'),
      RegExp(r'\bhour\s+loop\b'),
      RegExp(r'\blofi\b'),
      RegExp(r'\bno\s+copyright\b'),
      RegExp(r'\broyalty\s+free\b'),
      RegExp(r'\bmeditation\b'),
      RegExp(r'\bsleep\s+music\b'),
      RegExp(r'\bwhite\s+noise\b'),
      RegExp(r'\brain\s+sounds\b'),
    ];
    return !blocked.any((pattern) => pattern.hasMatch(text));
  }

  bool _needsPlaybackLinkEnrichment(PlatformTrackResult track) {
    return track.spotifyUrl == null ||
        track.spotifyUrl!.isEmpty ||
        track.appleUrl == null ||
        track.appleUrl!.isEmpty ||
        track.youtubeUrl == null ||
        track.youtubeUrl!.isEmpty ||
        track.deezerUrl == null ||
        track.deezerUrl!.isEmpty;
  }

  PlatformTrackResult? _bestPlaybackMatch(
    List<PlatformTrackResult> candidates,
    PlatformTrackResult target, {
    bool allowTitleOnlyWhenArtistIsInTitle = false,
  }) {
    PlatformTrackResult? best;
    var bestScore = 0.0;
    for (final candidate in candidates) {
      final score = _playbackMatchScore(
        candidate,
        target,
        allowTitleOnlyWhenArtistIsInTitle: allowTitleOnlyWhenArtistIsInTitle,
      );
      if (score > bestScore) {
        best = candidate;
        bestScore = score;
      }
    }
    return bestScore >= 70 ? best : null;
  }

  double _playbackMatchScore(
    PlatformTrackResult candidate,
    PlatformTrackResult target, {
    required bool allowTitleOnlyWhenArtistIsInTitle,
  }) {
    final candidateTitle = _normalizeSearchText(candidate.title);
    final targetTitle = _normalizeSearchText(target.title);
    final candidateArtist = _normalizeSearchText(candidate.artist);
    final targetArtist = _normalizeSearchText(target.artist);
    final combinedCandidate = '$candidateTitle $candidateArtist';

    var titleScore = 0.0;
    if (candidateTitle == targetTitle) {
      titleScore = 60;
    } else if (candidateTitle.contains(targetTitle) ||
        targetTitle.contains(candidateTitle)) {
      titleScore = 46;
    } else {
      titleScore = _tokenOverlap(candidateTitle, targetTitle) * 44;
    }

    var artistScore = 0.0;
    if (candidateArtist == targetArtist) {
      artistScore = 34;
    } else if (candidateArtist.contains(targetArtist) ||
        targetArtist.contains(candidateArtist)) {
      artistScore = 26;
    } else if (combinedCandidate.contains(targetArtist)) {
      artistScore = 22;
    }

    if (artistScore == 0 &&
        allowTitleOnlyWhenArtistIsInTitle &&
        candidateTitle.contains(targetArtist)) {
      artistScore = 18;
    }

    if (titleScore < 30 || artistScore == 0) return 0;
    return titleScore + artistScore + candidate.popularity.clamp(0, 100) * 0.04;
  }

  double _tokenOverlap(String first, String second) {
    final firstTokens = first
        .split(' ')
        .where((token) => token.length > 2)
        .toSet();
    final secondTokens = second
        .split(' ')
        .where((token) => token.length > 2)
        .toSet();
    if (firstTokens.isEmpty || secondTokens.isEmpty) return 0;
    final overlap = firstTokens.intersection(secondTokens).length;
    return overlap /
        (firstTokens.length > secondTokens.length
            ? firstTokens.length
            : secondTokens.length);
  }

  String _normalizeSearchText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\(.*?\)'), ' ')
        .replaceAll(RegExp(r'\[.*?\]'), ' ')
        .replaceAll(RegExp(r'official|video|audio|lyrics|visualizer'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _stripHtml(String value) {
    return value
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _decodeHtml(String value) {
    var result = value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#039;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    result = result.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
      final codePoint = int.tryParse(match.group(1) ?? '', radix: 16);
      return codePoint == null
          ? match.group(0)!
          : String.fromCharCode(codePoint);
    });
    result = result.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
      final codePoint = int.tryParse(match.group(1) ?? '');
      return codePoint == null
          ? match.group(0)!
          : String.fromCharCode(codePoint);
    });
    return result.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _normalizeKey(String title, String artist) {
    final t = title
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\(.*?\)'), '')
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final a = artist
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return '$t::$a';
  }

  /// Try to find a fuzzy match for a YouTube title among existing keys.
  String? _fuzzyMatchKey(
    String ytTitle,
    String ytArtist,
    Iterable<String> keys,
  ) {
    final normalized = _normalizeKey(ytTitle, ytArtist);
    final titlePart = normalized.split('::').first;
    if (titlePart.length < 4) return null;

    for (final key in keys) {
      final existingTitle = key.split('::').first;
      // Check if one title contains the other
      if (existingTitle.contains(titlePart) ||
          titlePart.contains(existingTitle)) {
        return key;
      }
    }
    return null;
  }
}

const _selectionStopwords = {
  'all',
  'best',
  'bpm',
  'classic',
  'classics',
  'club',
  'dj',
  'essential',
  'greatest',
  'hit',
  'hits',
  'hot',
  'mix',
  'music',
  'new',
  'party',
  'playlist',
  'popular',
  'rising',
  'song',
  'songs',
  'top',
  'track',
  'tracks',
  'trend',
  'trending',
};

const _kworbSpotifyCountryCodes = {
  'ad',
  'ae',
  'ar',
  'at',
  'au',
  'be',
  'bg',
  'bo',
  'br',
  'by',
  'ca',
  'ch',
  'cl',
  'co',
  'cr',
  'cy',
  'cz',
  'de',
  'dk',
  'do',
  'ec',
  'ee',
  'eg',
  'es',
  'fi',
  'fr',
  'gb',
  'gr',
  'gt',
  'hk',
  'hn',
  'hu',
  'id',
  'ie',
  'il',
  'in',
  'is',
  'it',
  'jp',
  'kr',
  'kz',
  'lt',
  'lu',
  'lv',
  'ma',
  'mt',
  'mx',
  'my',
  'ng',
  'ni',
  'nl',
  'no',
  'nz',
  'pa',
  'pe',
  'ph',
  'pk',
  'pl',
  'pt',
  'py',
  'ro',
  'ru',
  'sa',
  'se',
  'sg',
  'sk',
  'sv',
  'th',
  'tr',
  'tw',
  'ua',
  'us',
  'uy',
  've',
  'vn',
  'za',
};

String? _normalizedRegionCode(String? region) {
  final value = region?.trim().toUpperCase();
  if (value == null || value.isEmpty || value == 'ALL' || value == 'GLOBAL') {
    return null;
  }
  return value;
}
