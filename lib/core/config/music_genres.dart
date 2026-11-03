const kCanonicalMusicGenres = <String>[
  'Afrobeats',
  'Afrobeat',
  'Afro-Pop',
  'Afro-Fusion',
  'Afro-House',
  'Amapiano',
  'Highlife',
  'Hiplife',
  'Kwaito',
  'Gqom',
  'Soca',
  'Calypso',
  'Dancehall',
  'Reggae',
  'Baile Funk',
  'Latin',
  'Reggaeton',
  'Salsa',
  'Bachata',
  'Hip-Hop',
  'Hip-Hop/Rap',
  'Trap',
  'Drill',
  'Grime',
  'R&B',
  'Soul',
  'Pop',
  'K-Pop',
  'Dance',
  'EDM',
  'House',
  'Deep House',
  'Tech House',
  'Progressive House',
  'Techno',
  'Trance',
  'Drum & Bass',
  'Dubstep',
  'UK Garage',
  'Garage',
  'Electronic',
  'Disco',
  'Funk',
  'Jazz',
  'Blues',
  'Rock',
  'Alternative',
  'Indie',
  'Country',
  'Gospel',
  'Christian',
  'Classical',
  'World',
  'Other',
];

final kGenreFilterOptions = <String>[
  'All',
  ...kCanonicalMusicGenres.where((genre) => genre != 'Other'),
];

List<String> mergedGenreOptions(
  Iterable<String?> discoveredGenres, {
  bool includeAll = true,
  bool includeOther = false,
}) {
  final options = <String>[
    if (includeAll) 'All',
    ...kCanonicalMusicGenres.where((genre) => includeOther || genre != 'Other'),
  ];
  final seen = options.map(_genreKey).toSet();
  final extras = <String>[];

  for (final rawGenre in discoveredGenres) {
    final genre = rawGenre?.trim();
    if (genre == null || genre.isEmpty) continue;
    if (!includeOther && !isSpecificGenre(genre)) continue;
    final key = _genreKey(genre);
    if (seen.add(key)) {
      extras.add(genre);
    }
  }

  extras.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [...options, ...extras];
}

String _genreKey(String genre) =>
    genre.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), ' ');

/// Genre labels that carry no usable lane information. A track tagged with one
/// of these is "unknown" and must not be treated as matching a specific
/// selected genre — otherwise a selection like "House" would surface every
/// untagged row.
const _unknownGenreKeys = <String>{
  '',
  'open format',
  'other',
  'unknown',
  'music',
  'na',
};

const _genreStopTokens = <String>{'and', 'the', 'of', 'music', 'songs'};

String _genreNorm(String genre) => genre
    .toLowerCase()
    .trim()
    .replaceAll(RegExp(r'\(.*?\)'), ' ')
    .replaceAll(RegExp(r'[\/&]'), ' ')
    .replaceAll(RegExp(r'[-_]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Tokenize a genre label into comparable tokens. Drops connective stopwords
/// and lightly de-pluralizes (`afrobeats` → `afrobeat`) so plural/singular and
/// punctuation variants of the same lane compare equal.
Set<String> _genreTokens(String genre) {
  return _genreNorm(genre)
      .split(' ')
      .where((token) => token.isNotEmpty && !_genreStopTokens.contains(token))
      .map(
        (token) => token.length > 4 && token.endsWith('s')
            ? token.substring(0, token.length - 1)
            : token,
      )
      .toSet();
}

/// Whether [genre] names a real, specific lane (not `All`/null/unknown). Used to
/// decide when genre should drive live retrieval and ranking.
bool isSpecificGenre(String? genre) {
  final value = (genre ?? '').trim();
  if (value.isEmpty || value.toLowerCase() == 'all') return false;
  // A comma-joined list ("House, Afrobeats") is a multi-lane hint, not a single
  // specific lane, so it must not drive single-genre gating/stamping.
  if (value.contains(',')) return false;
  return !_unknownGenreKeys.contains(_genreNorm(value));
}

/// Tolerant genre matcher used by every catalog/chart filter.
///
/// Live genres arrive from heterogeneous sources — Apple's compound labels
/// ("Hip-Hop/Rap"), Soundcharts regional defaults ("Afrobeats"), or nothing at
/// all (`Other` when a streaming row carries no genre). Exact string
/// equality discarded almost everything, so this matches on canonical token
/// sets instead: a selection matches when it equals the track lane, or when one
/// is a family/superset of the other (e.g. "House" matches "Deep House").
bool genreMatches(String? trackGenre, String selected) {
  final sel = selected.trim();
  if (sel.isEmpty || sel.toLowerCase() == 'all') return true;

  final track = (trackGenre ?? '').trim();
  if (_unknownGenreKeys.contains(_genreNorm(track))) return false;

  final trackTokens = _genreTokens(track);
  final selTokens = _genreTokens(sel);
  if (trackTokens.isEmpty || selTokens.isEmpty) return false;

  return trackTokens.containsAll(selTokens) ||
      selTokens.containsAll(trackTokens);
}

/// Resolve a raw/platform genre label to a canonical catalog bucket when
/// recognizable, returning `Other` for unknown labels and preserving
/// genuine but non-catalog genres unchanged.
String canonicalGenre(String? raw) {
  final value = (raw ?? '').trim();
  if (_unknownGenreKeys.contains(_genreNorm(value))) return 'Other';

  final tokens = _genreTokens(value);
  if (tokens.isEmpty) return 'Other';

  for (final canonical in kCanonicalMusicGenres) {
    if (_genreTokens(canonical).difference(tokens).isEmpty &&
        tokens.difference(_genreTokens(canonical)).isEmpty) {
      return canonical;
    }
  }
  for (final canonical in kCanonicalMusicGenres) {
    final canonicalTokens = _genreTokens(canonical);
    if (canonicalTokens.isNotEmpty && tokens.containsAll(canonicalTokens)) {
      return canonical;
    }
  }
  return value;
}

/// Apple Music genre mapping for a selected lane. [id] is the Apple Music genre
/// id; [preferredStorefronts] are storefronts known to carry the genre — set
/// only for regional genres (e.g. Afrobeats/Amapiano) that aren't in the US
/// storefront. Empty means the genre exists in every storefront, so the
/// selected region's storefront is used directly.
class AppleGenreMapping {
  const AppleGenreMapping(
    this.id, [
    this.preferredStorefronts = const <String>[],
  ]);

  final int id;
  final List<String> preferredStorefronts;
}

const _afroStorefronts = <String>['ng', 'gh', 'za'];
const _amapianoStorefronts = <String>['za', 'ng', 'gh'];

/// Canonical lane → Apple Music genre. Genre ids verified live against the Apple
/// Music API. Parent-genre mapping is intentional (House→Dance, Dancehall→
/// Reggae). Lanes with no clean Apple genre (Open Format, Disco, Funk, …) are
/// omitted so callers fall back to keyword search.
const _appleGenreByCanonical = <String, AppleGenreMapping>{
  // African genres (carried in African storefronts, not US)
  'Afrobeats': AppleGenreMapping(100051, _afroStorefronts),
  'Afrobeat': AppleGenreMapping(100051, _afroStorefronts),
  'Afro-Pop': AppleGenreMapping(100051, _afroStorefronts),
  'Afro-Fusion': AppleGenreMapping(100051, _afroStorefronts),
  'Highlife': AppleGenreMapping(100051, _afroStorefronts),
  'Hiplife': AppleGenreMapping(100051, _afroStorefronts),
  'Amapiano': AppleGenreMapping(42, _amapianoStorefronts),
  'Afro-House': AppleGenreMapping(42, _amapianoStorefronts),
  'Kwaito': AppleGenreMapping(42, _amapianoStorefronts),
  'Gqom': AppleGenreMapping(42, _amapianoStorefronts),
  // Reggae family
  'Reggae': AppleGenreMapping(24),
  'Dancehall': AppleGenreMapping(24),
  'Soca': AppleGenreMapping(24),
  'Calypso': AppleGenreMapping(24),
  // Latin family
  'Latin': AppleGenreMapping(12),
  'Reggaeton': AppleGenreMapping(12),
  'Salsa': AppleGenreMapping(12),
  'Bachata': AppleGenreMapping(12),
  'Baile Funk': AppleGenreMapping(12),
  // Hip-Hop family
  'Hip-Hop': AppleGenreMapping(18),
  'Hip-Hop/Rap': AppleGenreMapping(18),
  'Trap': AppleGenreMapping(18),
  'Drill': AppleGenreMapping(18),
  'Grime': AppleGenreMapping(18),
  // R&B / Soul
  'R&B': AppleGenreMapping(15),
  'Soul': AppleGenreMapping(15),
  // Pop
  'Pop': AppleGenreMapping(14),
  'K-Pop': AppleGenreMapping(51),
  // Dance / House family
  'Dance': AppleGenreMapping(17),
  'EDM': AppleGenreMapping(17),
  'House': AppleGenreMapping(17),
  'Deep House': AppleGenreMapping(17),
  'Tech House': AppleGenreMapping(17),
  'Progressive House': AppleGenreMapping(17),
  'Techno': AppleGenreMapping(17),
  'Trance': AppleGenreMapping(17),
  // Electronic family
  'Electronic': AppleGenreMapping(7),
  'Drum & Bass': AppleGenreMapping(7),
  'Dubstep': AppleGenreMapping(7),
  'UK Garage': AppleGenreMapping(7),
  'Garage': AppleGenreMapping(7),
  // Rock / Alternative
  'Rock': AppleGenreMapping(21),
  'Alternative': AppleGenreMapping(20),
  'Indie': AppleGenreMapping(20),
  // Other major genres
  'Country': AppleGenreMapping(6),
  'Gospel': AppleGenreMapping(22),
  'Christian': AppleGenreMapping(22),
  'Classical': AppleGenreMapping(5),
  'Jazz': AppleGenreMapping(11),
  'Blues': AppleGenreMapping(2),
  'World': AppleGenreMapping(19),
};

/// Resolve a selected lane to its Apple Music genre chart mapping, or null when
/// the lane is not specific (All/unknown) or has no clean Apple genre — in which
/// case callers fall back to keyword search.
AppleGenreMapping? appleGenreFor(String? lane) {
  if (!isSpecificGenre(lane)) return null;
  return _appleGenreByCanonical[canonicalGenre(lane)];
}
