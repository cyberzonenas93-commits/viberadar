import '../models/crate_track.dart';
import '../models/library_track.dart';
import '../models/track.dart';
import 'local_match_service.dart';

/// Pure conversion + planning helpers that bridge a phone-built [Crate]'s rich
/// [CrateTrack] entries into the desktop's local-library matching + export
/// pipeline. Kept free of Firebase/IO so it is unit-testable.

/// Builds a self-contained crate entry from a live trends [Track], capturing its
/// metadata + platform links. Without this an entry is an id-only reference that
/// silently vanishes on the desktop once the track decays out of the live feed.
CrateTrack crateTrackFromTrack(Track t) => CrateTrack(
  trackId: t.id,
  title: t.title,
  artist: t.artist,
  bpm: t.bpm,
  key: t.keySignature,
  spotifyUrl: t.platformLinks['spotify'],
  appleUrl: t.platformLinks['apple'],
  youtubeUrl: t.platformLinks['youtube'],
  artworkUrl: t.artworkUrl.isEmpty ? null : t.artworkUrl,
);

/// Synthesises a [Track] from a rich [CrateTrack] so it can be rendered and run
/// through [LocalMatchService] without needing the live trends document.
Track trackFromCrateTrack(CrateTrack e, DateTime now) {
  final links = <String, String>{
    if (e.spotifyUrl != null && e.spotifyUrl!.isNotEmpty)
      'spotify': e.spotifyUrl!,
    if (e.appleUrl != null && e.appleUrl!.isNotEmpty) 'apple': e.appleUrl!,
    if (e.youtubeUrl != null && e.youtubeUrl!.isNotEmpty)
      'youtube': e.youtubeUrl!,
  };
  return Track(
    id: e.trackId ?? e.stableKey,
    title: e.title,
    artist: e.artist,
    artworkUrl: e.artworkUrl ?? '',
    bpm: e.bpm,
    keySignature: e.key.isEmpty ? '--' : e.key,
    genre: 'Other',
    vibe: 'club',
    trendScore: 0,
    regionScores: const {},
    platformLinks: links,
    createdAt: now,
    updatedAt: now,
    energyLevel: 0.5,
    trendHistory: const [],
  );
}

/// Encodes a [Track] as a crate-store id the desktop Export Studio resolves back
/// to a local file by title/artist — mirroring the `spotify:`/`apple:` encoding
/// the search screen already uses. Lets a synced phone setlist be loaded into
/// the Export Studio bench (with its match panel + physical-crate tools) without
/// a separate storage model. Colons are stripped so the `:`-delimited decode on
/// the desktop stays aligned.
String exportStudioId(Track t) {
  String clean(String s) =>
      s.replaceAll(':', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return 'vibe:${clean(t.title)}:${clean(t.artist)}';
}

/// The outcome of resolving a crate's entries to display/export-ready tracks.
class ResolvedCrate {
  const ResolvedCrate({required this.tracks, required this.droppedReferences});

  /// Render/export-ready tracks (rich entries synthesised, references enriched).
  final List<Track> tracks;

  /// Count of id-only legacy references that no longer exist in the live feed
  /// (no metadata to render or match on). Surfaced so the UI can warn instead of
  /// silently showing a shorter set than the phone did.
  final int droppedReferences;
}

/// Resolves a crate's [entries] to [Track]s for the desktop. Rich entries are
/// used directly (preferring the fresher live doc when still present); id-only
/// references are enriched from [liveTracks]; bare references with no live match
/// are dropped and counted.
ResolvedCrate resolveCrateTracks(
  List<CrateTrack> entries,
  List<Track> liveTracks, {
  DateTime? now,
}) {
  final ts = now ?? DateTime.now();
  final byId = {for (final t in liveTracks) t.id: t};
  final out = <Track>[];
  var dropped = 0;
  for (final e in entries) {
    final live = e.trackId != null ? byId[e.trackId] : null;
    if (e.isReference) {
      if (live != null) {
        out.add(live);
      } else {
        dropped++;
      }
    } else {
      out.add(live ?? trackFromCrateTrack(e, ts));
    }
  }
  return ResolvedCrate(tracks: out, droppedReferences: dropped);
}

/// A crate split into files the DJ owns locally (ready for real-path export) and
/// the labels of tracks not found in their library.
class CrateExportPlan {
  const CrateExportPlan({required this.matched, required this.missing});

  /// Local files with full metadata + real paths — usable by every exporter.
  final List<LibraryTrack> matched;

  /// "Artist - Title" of tracks with no local file (export as streaming/manifest).
  final List<String> missing;

  int get total => matched.length + missing.length;
  bool get hasMissing => missing.isNotEmpty;
}

/// Matches [tracks] against the scanned [library] and returns the real local
/// files (so file-based exports point at audio that actually exists) plus the
/// tracks the DJ doesn't own locally.
Future<CrateExportPlan> planLocalExport({
  required List<Track> tracks,
  required List<LibraryTrack> library,
  LocalMatchService? matcher,
}) async {
  final m = matcher ?? LocalMatchService();
  final matches = await m.matchSet(tracks, library);
  final byPath = {for (final lt in library) lt.filePath: lt};
  final matched = <LibraryTrack>[];
  final missing = <String>[];
  for (final match in matches) {
    final path = match.localFilePath;
    final lt = path == null ? null : byPath[path];
    if (match.isMissing || lt == null) {
      missing.add(
        '${match.vibeTrack.artist} - ${match.vibeTrack.title}'.trim(),
      );
    } else {
      matched.add(lt);
    }
  }
  return CrateExportPlan(matched: matched, missing: missing);
}
