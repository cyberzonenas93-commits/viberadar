import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'spotify_artist_service.dart';
import 'apple_music_artist_service.dart';
import 'youtube_search_service.dart';
import 'platform_search_service.dart';

/// A playlist fetched from a streaming platform.
class AggregatedPlaylist {
  final String name;
  final List<String> sources;
  final String? artworkUrl;
  final String? description;
  final List<PlatformTrackResult> tracks;

  const AggregatedPlaylist({
    required this.name,
    required this.sources,
    this.artworkUrl,
    this.description,
    this.tracks = const [],
  });

  String get sourceLabel => sources.map((s) => '${s[0].toUpperCase()}${s.substring(1)}').join(' + ');
}

/// Fetches real curated/editorial playlists from Spotify and Apple Music.
class PlaylistAggregationService {
  final _spotify = SpotifyArtistService();
  final _apple = AppleMusicArtistService();
  final _youtube = YoutubeSearchService();

  /// Fetch playlists/charts from all 5 sources.
  Future<List<AggregatedPlaylist>> fetchPlaylists({
    String genre = 'All',
    String region = 'All',
    int limit = 100,
  }) async {
    final results = await Future.wait([
      _fetchSpotifyPlaylists(genre: genre, limit: limit),
      _fetchAppleMusicCharts(genre: genre, limit: limit),
      _fetchYouTubeTrending(genre: genre, limit: limit),
      _fetchDeezerCharts(genre: genre, limit: limit),
      _fetchBillboardCharts(genre: genre, limit: limit),
    ]);

    return [
      ...results[0],
      ...results[1],
      ...results[2],
      ...results[3],
      ...results[4],
    ];
  }

  /// Fetch Spotify featured playlists and category playlists.
  Future<List<AggregatedPlaylist>> _fetchSpotifyPlaylists({
    String genre = 'All',
    int limit = 100,
  }) async {
    final playlists = <AggregatedPlaylist>[];

    try {
      final token = await _spotify.getAccessToken();
      if (token == null) return [];

      // 1. Featured playlists
      dev.log('Fetching Spotify featured playlists with token: ${token.substring(0, 10)}...', name: 'PlaylistAggregation');
      final featuredRes = await http.get(
        Uri.parse('https://api.spotify.com/v1/browse/featured-playlists?limit=10&country=US'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 15));

      if (featuredRes.statusCode == 200) {
        final data = jsonDecode(featuredRes.body);
        final items = data['playlists']?['items'] as List? ?? [];
        for (final item in items.take(5)) {
          final playlistId = item['id'] as String?;
          final name = item['name'] as String? ?? 'Playlist';
          final desc = item['description'] as String? ?? '';
          final images = item['images'] as List? ?? [];
          final artwork = images.isNotEmpty ? images.first['url'] as String? : null;

          if (playlistId != null) {
            final tracks = await _fetchSpotifyPlaylistTracks(token, playlistId, limit: limit);
            if (tracks.isNotEmpty) {
              playlists.add(AggregatedPlaylist(
                name: name,
                sources: const ['spotify'],
                artworkUrl: artwork,
                description: desc,
                tracks: tracks,
              ));
            }
          }
        }
      }

      // 2. Genre-specific category playlists (if genre selected)
      if (genre != 'All') {
        final catRes = await http.get(
          Uri.parse('https://api.spotify.com/v1/search?q=$genre&type=playlist&limit=5&market=US'),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(const Duration(seconds: 10));

        if (catRes.statusCode == 200) {
          final data = jsonDecode(catRes.body);
          final items = data['playlists']?['items'] as List? ?? [];
          for (final item in items.take(3)) {
            final playlistId = item['id'] as String?;
            final name = item['name'] as String? ?? 'Playlist';
            final desc = item['description'] as String? ?? '';
            final images = item['images'] as List? ?? [];
            final artwork = images.isNotEmpty ? images.first['url'] as String? : null;

            if (playlistId != null) {
              final tracks = await _fetchSpotifyPlaylistTracks(token, playlistId, limit: limit);
              if (tracks.isNotEmpty) {
                playlists.add(AggregatedPlaylist(
                  name: name,
                  sources: const ['spotify'],
                  artworkUrl: artwork,
                  description: desc,
                  tracks: tracks,
                ));
              }
            }
          }
        }
      }
      // 3. Fallback: if no playlists found yet, search for popular tracks directly
      if (playlists.isEmpty) {
        dev.log('No Spotify playlists found, falling back to track search', name: 'PlaylistAggregation');
        final searchQuery = genre == 'All' ? 'top hits 2026' : '$genre top hits';
        final searchRes = await http.get(
          Uri.parse('https://api.spotify.com/v1/search?q=${Uri.encodeComponent(searchQuery)}&type=track&limit=${limit.clamp(1, 50)}&market=US'),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(const Duration(seconds: 10));

        if (searchRes.statusCode == 200) {
          final searchData = jsonDecode(searchRes.body);
          final searchItems = searchData['tracks']?['items'] as List? ?? [];
          final searchTracks = <PlatformTrackResult>[];

          for (final item in searchItems) {
            final name = item['name'] as String? ?? '';
            final artists = (item['artists'] as List?)
                ?.map((a) => a['name'] as String)
                .join(', ') ?? '';
            final album = item['album'] as Map<String, dynamic>?;
            final images = album?['images'] as List? ?? [];
            final artwork = images.isNotEmpty ? images.first['url'] as String? : null;
            final url = item['external_urls']?['spotify'] as String?;
            final duration = item['duration_ms'] as int? ?? 0;
            final popularity = item['popularity'] as int? ?? 0;

            if (name.isNotEmpty) {
              searchTracks.add(PlatformTrackResult(
                title: name,
                artist: artists,
                artworkUrl: artwork,
                spotifyUrl: url,
                durationMs: duration,
                popularity: popularity,
              ));
            }
          }

          if (searchTracks.isNotEmpty) {
            playlists.add(AggregatedPlaylist(
              name: genre == 'All' ? 'Top Hits (Spotify)' : '$genre Hits (Spotify)',
              sources: const ['spotify'],
              artworkUrl: searchTracks.first.artworkUrl,
              description: 'Popular tracks from Spotify',
              tracks: searchTracks,
            ));
          }
        }
      }
    } catch (e) {
      dev.log('Spotify playlist fetch error: $e', name: 'PlaylistAggregation');
    }

    return playlists;
  }

  /// Fetch tracks from a specific Spotify playlist.
  Future<List<PlatformTrackResult>> _fetchSpotifyPlaylistTracks(
    String token, String playlistId, {int limit = 100}
  ) async {
    try {
      final res = await http.get(
        Uri.parse('https://api.spotify.com/v1/playlists/$playlistId/tracks?limit=$limit&market=US'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return [];

      final data = jsonDecode(res.body);
      final items = data['items'] as List? ?? [];
      final tracks = <PlatformTrackResult>[];

      for (final item in items) {
        final track = item['track'] as Map<String, dynamic>?;
        if (track == null) continue;

        final name = track['name'] as String? ?? '';
        final artists = (track['artists'] as List?)
            ?.map((a) => a['name'] as String)
            .join(', ') ?? '';
        final album = track['album'] as Map<String, dynamic>?;
        final images = album?['images'] as List? ?? [];
        final artwork = images.isNotEmpty ? images.first['url'] as String? : null;
        final url = track['external_urls']?['spotify'] as String?;
        final duration = track['duration_ms'] as int? ?? 0;
        final popularity = track['popularity'] as int? ?? 0;

        if (name.isNotEmpty) {
          tracks.add(PlatformTrackResult(
            title: name,
            artist: artists,
            artworkUrl: artwork,
            spotifyUrl: url,
            durationMs: duration,
            popularity: popularity,
          ));
        }
      }

      return tracks;
    } catch (_) {
      return [];
    }
  }

  /// Fetch Apple Music charts (top songs).
  Future<List<AggregatedPlaylist>> _fetchAppleMusicCharts({
    String genre = 'All',
    int limit = 100,
  }) async {
    final playlists = <AggregatedPlaylist>[];

    try {
      final token = dotenv.env['APPLE_MUSIC_TOKEN'];
      if (token == null || token.isEmpty) return [];

      // Fetch top songs chart
      final chartRes = await http.get(
        Uri.parse('https://api.music.apple.com/v1/catalog/us/charts?types=songs&limit=$limit'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      if (chartRes.statusCode == 200) {
        final data = jsonDecode(chartRes.body);
        final charts = data['results']?['songs'] as List? ?? [];

        for (final chart in charts) {
          final chartName = chart['name'] as String? ?? 'Top Songs';
          final chartData = chart['data'] as List? ?? [];
          final tracks = <PlatformTrackResult>[];

          for (final item in chartData) {
            final attrs = item['attributes'] as Map<String, dynamic>?;
            if (attrs == null) continue;

            final name = attrs['name'] as String? ?? '';
            final artist = attrs['artistName'] as String? ?? '';
            var artwork = attrs['artwork']?['url'] as String? ?? '';
            artwork = artwork.replaceAll('{w}', '300').replaceAll('{h}', '300');
            final url = attrs['url'] as String?;
            final duration = attrs['durationInMillis'] as int? ?? 0;

            if (name.isNotEmpty) {
              tracks.add(PlatformTrackResult(
                title: name,
                artist: artist,
                artworkUrl: artwork.isNotEmpty ? artwork : null,
                appleUrl: url,
                durationMs: duration,
              ));
            }
          }

          if (tracks.isNotEmpty) {
            playlists.add(AggregatedPlaylist(
              name: '$chartName (Apple Music)',
              sources: const ['apple'],
              artworkUrl: tracks.first.artworkUrl,
              tracks: tracks,
            ));
          }
        }
      }

      // Genre-specific search as fallback
      if (genre != 'All') {
        final results = await _apple.searchSongs(genre, limit: limit);
        if (results.isNotEmpty) {
          playlists.add(AggregatedPlaylist(
            name: '$genre on Apple Music',
            sources: const ['apple'],
            artworkUrl: results.first.artworkUrl,
            tracks: results.map((t) => PlatformTrackResult(
              title: t.name,
              artist: t.artistName,
              artworkUrl: t.artworkUrl,
              appleUrl: t.appleUrl,
              durationMs: t.durationMs,
            )).toList(),
          ));
        }
      }
    } catch (e) {
      dev.log('Apple Music playlist fetch error: $e', name: 'PlaylistAggregation');
    }

    return playlists;
  }

  /// Fetch YouTube trending music as a playlist-like source.
  /// Uses YouTube Data API if key is available, otherwise falls back to
  /// Spotify search for YouTube-labeled playlists.
  Future<List<AggregatedPlaylist>> _fetchYouTubeTrending({
    String genre = 'All',
    int limit = 100,
  }) async {
    try {
      // Try YouTube Data API first
      final query = genre == 'All' ? 'trending music 2026' : '$genre music trending';
      final videos = await _youtube.searchMusic(query, limit: limit.clamp(1, 50));
      if (videos.isNotEmpty) {
        return [
          AggregatedPlaylist(
            name: genre == 'All' ? 'Trending on YouTube' : '$genre on YouTube',
            sources: const ['youtube'],
            artworkUrl: videos.first.thumbnailUrl,
            description: 'Top trending music videos from YouTube',
            tracks: videos.map((v) => PlatformTrackResult(
              title: v.title,
              artist: v.channelName,
              artworkUrl: v.thumbnailUrl,
              youtubeUrl: v.youtubeUrl,
            )).toList(),
          ),
        ];
      }

      // Fallback: use Spotify to discover tracks, generate YouTube search URLs
      final token = await _spotify.getAccessToken();
      if (token == null) return [];

      // Fetch multiple queries for variety
      final queries = genre == 'All'
          ? ['trending music 2026', 'viral hits 2026', 'popular songs new']
          : ['$genre trending 2026', '$genre hits new', '$genre popular'];

      final allTracks = <PlatformTrackResult>[];
      final seen = <String>{};

      for (final searchQuery in queries) {
        final res = await http.get(
          Uri.parse('https://api.spotify.com/v1/search?q=${Uri.encodeComponent(searchQuery)}&type=track&limit=50&market=US'),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(const Duration(seconds: 10));

        if (res.statusCode != 200) continue;

        final data = jsonDecode(res.body);
        final items = data['tracks']?['items'] as List? ?? [];

        for (final item in items) {
          final name = item['name'] as String? ?? '';
          final artists = (item['artists'] as List?)
              ?.map((a) => a['name'] as String)
              .join(', ') ?? '';
          final dedup = '${name.toLowerCase()}::${artists.toLowerCase()}';
          if (seen.contains(dedup)) continue;
          seen.add(dedup);

          final album = item['album'] as Map<String, dynamic>?;
          final images = album?['images'] as List? ?? [];
          final artwork = images.isNotEmpty ? images.first['url'] as String? : null;
          final spotUrl = item['external_urls']?['spotify'] as String?;
          // Generate YouTube search URL so users can find it on YouTube
          final ytSearch = 'https://www.youtube.com/results?search_query=${Uri.encodeComponent('$artists $name official')}';

          if (name.isNotEmpty) {
            allTracks.add(PlatformTrackResult(
              title: name,
              artist: artists,
              artworkUrl: artwork,
              spotifyUrl: spotUrl,
              youtubeUrl: ytSearch,
            ));
          }

          if (allTracks.length >= limit) break;
        }
        if (allTracks.length >= limit) break;
      }

      if (allTracks.isNotEmpty) {
        return [
          AggregatedPlaylist(
            name: genre == 'All' ? 'Trending on YouTube' : '$genre on YouTube',
            sources: const ['youtube', 'spotify'],
            artworkUrl: allTracks.first.artworkUrl,
            description: 'Trending tracks available on YouTube',
            tracks: allTracks.take(limit).toList(),
          ),
        ];
      }
    } catch (e) {
      dev.log('YouTube/trending fetch error: $e', name: 'PlaylistAggregation');
    }
    return [];
  }

  /// Fetch Deezer chart tracks as a playlist-like source.
  Future<List<AggregatedPlaylist>> _fetchDeezerCharts({
    String genre = 'All',
    int limit = 100,
  }) async {
    try {
      // Deezer public chart API (no auth required)
      final url = genre == 'All'
          ? 'https://api.deezer.com/chart/0/tracks?limit=$limit'
          : 'https://api.deezer.com/search?q=$genre&limit=$limit&order=RANKING';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return [];

      final data = jsonDecode(res.body);
      final items = (data['data'] as List?) ?? (data['tracks']?['data'] as List?) ?? [];
      if (items.isEmpty) return [];

      final tracks = items.map<PlatformTrackResult>((item) {
        final title = item['title'] as String? ?? '';
        final artist = item['artist']?['name'] as String? ?? '';
        final artwork = item['album']?['cover_medium'] as String? ?? '';
        final link = item['link'] as String?;
        return PlatformTrackResult(
          title: title,
          artist: artist,
          artworkUrl: artwork.isNotEmpty ? artwork : null,
          deezerUrl: link,
          durationMs: ((item['duration'] as int?) ?? 0) * 1000,
          popularity: item['rank'] as int? ?? 0,
        );
      }).where((t) => t.title.isNotEmpty).toList();

      if (tracks.isEmpty) return [];

      return [
        AggregatedPlaylist(
          name: genre == 'All' ? 'Deezer Chart' : '$genre on Deezer',
          sources: const ['deezer'],
          artworkUrl: tracks.first.artworkUrl,
          description: 'Top tracks from Deezer charts',
          tracks: tracks,
        ),
      ];
    } catch (_) {
      return [];
    }
  }

  /// Billboard-style chart using Spotify's viral/top charts as proxy.
  /// Billboard doesn't have a public API, so we simulate via Spotify's
  /// curated Billboard-equivalent playlists.
  Future<List<AggregatedPlaylist>> _fetchBillboardCharts({
    String genre = 'All',
    int limit = 100,
  }) async {
    try {
      final token = await _spotify.getAccessToken();
      if (token == null) return [];

      // Search for Billboard-style playlists on Spotify
      final query = genre == 'All' ? 'Billboard Hot 100' : 'Billboard $genre';
      final res = await http.get(
        Uri.parse('https://api.spotify.com/v1/search?q=${Uri.encodeComponent(query)}&type=playlist&limit=2&market=US'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return [];

      final data = jsonDecode(res.body);
      final items = data['playlists']?['items'] as List? ?? [];
      final playlists = <AggregatedPlaylist>[];

      for (final item in items.take(1)) {
        final playlistId = item['id'] as String?;
        final name = item['name'] as String? ?? 'Billboard Chart';
        final images = item['images'] as List? ?? [];
        final artwork = images.isNotEmpty ? images.first['url'] as String? : null;

        if (playlistId != null) {
          final tracks = await _fetchSpotifyPlaylistTracks(token, playlistId, limit: limit);
          if (tracks.isNotEmpty) {
            playlists.add(AggregatedPlaylist(
              name: '$name (Billboard)',
              sources: const ['billboard'],
              artworkUrl: artwork,
              description: 'Billboard chart tracks',
              tracks: tracks,
            ));
          }
        }
      }

      return playlists;
    } catch (_) {
      return [];
    }
  }
}
