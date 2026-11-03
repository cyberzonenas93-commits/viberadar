/// One entry in a [Crate]. Either a reference to a real `tracks/{id}` document
/// (when [trackId] is set and title/artist are empty) or a self-contained rich
/// entry carrying its own metadata + playable platform links (e.g. an
/// AI-resolved song that may not exist in the trends library).
class CrateTrack {
  const CrateTrack({
    this.trackId,
    required this.title,
    required this.artist,
    this.bpm = 0,
    this.key = '',
    this.spotifyUrl,
    this.appleUrl,
    this.youtubeUrl,
    this.artworkUrl,
  });

  /// An id-only reference entry (resolved against the live tracks stream).
  factory CrateTrack.reference(String trackId) =>
      CrateTrack(trackId: trackId, title: '', artist: '');

  final String? trackId;
  final String title;
  final String artist;
  final int bpm;
  final String key;
  final String? spotifyUrl;
  final String? appleUrl;
  final String? youtubeUrl;
  final String? artworkUrl;

  String get bestUrl => spotifyUrl ?? appleUrl ?? youtubeUrl ?? '';
  bool get hasUrl => bestUrl.isNotEmpty;

  /// True for an id-only entry that must be resolved from the tracks stream.
  bool get isReference => title.isEmpty && artist.isEmpty && trackId != null;

  /// Stable identity for de-duplication and the legacy `track_ids` mirror.
  String get stableKey =>
      trackId ?? '${artist.toLowerCase()}|${title.toLowerCase()}';

  Map<String, dynamic> toMap() => {
    if (trackId != null) 'track_id': trackId,
    'title': title,
    'artist': artist,
    'bpm': bpm,
    'key': key,
    if (spotifyUrl != null) 'spotify_url': spotifyUrl,
    if (appleUrl != null) 'apple_url': appleUrl,
    if (youtubeUrl != null) 'youtube_url': youtubeUrl,
    if (artworkUrl != null) 'artwork_url': artworkUrl,
  };

  factory CrateTrack.fromMap(Map<String, dynamic> map) => CrateTrack(
    trackId: map['track_id'] as String?,
    title: map['title'] as String? ?? '',
    artist: map['artist'] as String? ?? '',
    bpm: (map['bpm'] as num?)?.toInt() ?? 0,
    key: map['key'] as String? ?? '',
    spotifyUrl: map['spotify_url'] as String?,
    appleUrl: map['apple_url'] as String?,
    youtubeUrl: map['youtube_url'] as String?,
    artworkUrl: map['artwork_url'] as String?,
  );
}
