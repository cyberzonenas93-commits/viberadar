import '../models/crate_track.dart';
import '../models/track.dart';
import 'apple_music_artist_service.dart';
import 'spotify_artist_service.dart';
import 'youtube_search_service.dart';

typedef Draft = ({String title, String artist, int bpm, String key});
typedef SetSearchResult = ({String url, String art})?;
typedef SetSearch = Future<SetSearchResult> Function(String query);

String _canon(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// Resolves AI/draft songs into [CrateTrack]s with playable links.
/// Order per song: local library → Spotify → Apple → YouTube (fallback only,
/// to protect the low YouTube search quota).
class SetResolutionService {
  SetResolutionService({
    SpotifyArtistService? spotify,
    AppleMusicArtistService? apple,
    YoutubeSearchService? youtube,
  }) : _searchSpotify = _spotifyAdapter(spotify ?? SpotifyArtistService()),
       _searchApple = _appleAdapter(apple ?? AppleMusicArtistService()),
       _searchYoutube = _youtubeAdapter(youtube ?? YoutubeSearchService());

  /// Test seam: inject pure search functions.
  SetResolutionService.test({
    required SetSearch searchSpotify,
    required SetSearch searchApple,
    required SetSearch searchYoutube,
  }) : _searchSpotify = searchSpotify,
       _searchApple = searchApple,
       _searchYoutube = searchYoutube;

  final SetSearch _searchSpotify;
  final SetSearch _searchApple;
  final SetSearch _searchYoutube;

  Future<List<CrateTrack>> resolve(
    List<Draft> drafts, {
    List<Track> library = const [],
    void Function(int found, int total)? onProgress,
  }) async {
    final index = <String, Track>{
      for (final t in library) '${_canon(t.artist)}|${_canon(t.title)}': t,
    };
    final out = <CrateTrack>[];
    var found = 0;
    for (final d in drafts) {
      final local = index['${_canon(d.artist)}|${_canon(d.title)}'];
      CrateTrack entry;
      if (local != null) {
        entry = CrateTrack(
          trackId: local.id,
          title: d.title,
          artist: d.artist,
          bpm: d.bpm == 0 ? local.bpm : d.bpm,
          key: d.key.isEmpty ? local.keySignature : d.key,
          spotifyUrl: local.platformLinks['spotify'],
          appleUrl: local.platformLinks['apple'],
          youtubeUrl: local.platformLinks['youtube'],
          artworkUrl: local.artworkUrl.isEmpty ? null : local.artworkUrl,
        );
      } else {
        final q = '${d.artist} ${d.title}';
        final sp = await _searchSpotify(q);
        final ap = sp == null ? await _searchApple(q) : null;
        final yt = (sp == null && ap == null) ? await _searchYoutube(q) : null;
        entry = CrateTrack(
          title: d.title,
          artist: d.artist,
          bpm: d.bpm,
          key: d.key,
          spotifyUrl: sp?.url,
          appleUrl: ap?.url,
          youtubeUrl: yt?.url,
          artworkUrl: sp?.art ?? ap?.art ?? yt?.art,
        );
      }
      if (entry.hasUrl || entry.trackId != null) found++;
      out.add(entry);
      onProgress?.call(found, drafts.length);
    }
    return out;
  }

  static SetSearch _spotifyAdapter(SpotifyArtistService s) => (q) async {
    final r = await s
        .searchTracks(q, limit: 1)
        .catchError((_) => <SpotifyTrackInfo>[]);
    if (r.isEmpty || r.first.spotifyUrl.isEmpty) return null;
    return (url: r.first.spotifyUrl, art: r.first.albumArt ?? '');
  };

  static SetSearch _appleAdapter(AppleMusicArtistService s) => (q) async {
    final r = await s
        .searchSongs(q, limit: 1)
        .catchError((_) => <AppleMusicTrack>[]);
    if (r.isEmpty || (r.first.appleUrl ?? '').isEmpty) return null;
    return (url: r.first.appleUrl!, art: r.first.artworkUrl ?? '');
  };

  static SetSearch _youtubeAdapter(YoutubeSearchService s) => (q) async {
    final r = await s
        .searchMusic(q, limit: 1)
        .catchError((_) => <YoutubeVideoResult>[]);
    if (r.isEmpty || r.first.youtubeUrl.isEmpty) return null;
    return (url: r.first.youtubeUrl, art: r.first.thumbnailUrl ?? '');
  };
}
