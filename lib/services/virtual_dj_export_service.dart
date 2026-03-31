import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../models/dj_export_result.dart';
import '../models/library_track.dart';

/// VirtualDJ streaming service prefixes used in netsearch:// paths.
///
/// VirtualDJ path format: netsearch://<prefix><numeric_track_id>
/// Example: netsearch://td71717731 (TIDAL track 71717731)
enum VdjStreamingService {
  tidal('TIDAL', 'td'),
  deezer('Deezer', 'dz'),
  soundcloud('SoundCloud', 'sc'),
  beatport('Beatport', 'bp'),
  beatsource('Beatsource', 'bs'),
  idjpool('iDJPool', 'ip');

  const VdjStreamingService(this.label, this.prefix);
  final String label;
  final String prefix;
}

/// Writes VirtualDJ-compatible playlist files into the VirtualDJ library.
///
/// Track resolution priority:
///   1. Local file path (if exists on disk)
///   2. Match against local library by title+artist
///   3. Resolve via streaming API to get real track ID
///   4. Skip (track cannot be resolved)
class VirtualDjExportService {
  static const _localMusicSubdir = 'Folders/LocalMusic';
  static const _playlistsSubdir = 'Playlists';

  /// Export [tracks] as a VirtualDJ playlist folder.
  Future<DjExportResult> exportCrate({
    required String vdjRoot,
    required String playlistName,
    required List<LibraryTrack> tracks,
    VdjStreamingService? streamingService,
    List<LibraryTrack>? localLibrary,
    void Function(int done, int total)? onProgress,
  }) async {
    final resolved = <DjTrackResolution>[];
    final warnings = <String>[];

    // Build local library index for fast matching.
    final Map<String, LibraryTrack> localIndex = {};
    if (localLibrary != null) {
      for (final lt in localLibrary) {
        if (lt.filePath.isNotEmpty) {
          localIndex[_matchKey(lt.title, lt.artist)] = lt;
        }
      }
    }

    for (var i = 0; i < tracks.length; i++) {
      final t = tracks[i];
      onProgress?.call(i + 1, tracks.length);

      // Priority 1: Track already has a valid local file path.
      if (t.filePath.isNotEmpty && File(t.filePath).existsSync()) {
        resolved.add(DjTrackResolution(
          title: t.title, artist: t.artist,
          status: DjTrackStatus.local,
          localFilePath: t.filePath,
          fileSizeBytes: t.fileSizeBytes,
          durationSeconds: t.durationSeconds,
          bpm: t.bpm, key: t.key,
        ));
        continue;
      }

      // Priority 2: Match against local library by title+artist.
      final localMatch = localIndex[_matchKey(t.title, t.artist)];
      if (localMatch != null && File(localMatch.filePath).existsSync()) {
        resolved.add(DjTrackResolution(
          title: t.title, artist: t.artist,
          status: DjTrackStatus.local,
          localFilePath: localMatch.filePath,
          fileSizeBytes: localMatch.fileSizeBytes,
          durationSeconds: localMatch.durationSeconds > 0
              ? localMatch.durationSeconds : t.durationSeconds,
          bpm: t.bpm > 0 ? t.bpm : localMatch.bpm,
          key: t.key.isNotEmpty ? t.key : localMatch.key,
        ));
        continue;
      }

      // Priority 3: Resolve via streaming service API.
      if (streamingService != null) {
        final trackId = await _resolveStreamingTrackId(
          streamingService, t.artist, t.title,
        );
        if (trackId != null) {
          resolved.add(DjTrackResolution(
            title: t.title, artist: t.artist,
            status: DjTrackStatus.tidal,
            tidalTrackId: trackId,
            durationSeconds: t.durationSeconds,
            bpm: t.bpm, key: t.key,
          ));
          continue;
        }
        warnings.add('"${t.artist} – ${t.title}": not found on ${streamingService.label}');
      }

      // Priority 4: Skip.
      resolved.add(DjTrackResolution(
        title: t.title, artist: t.artist,
        status: DjTrackStatus.skipped,
        skipReason: streamingService != null
            ? 'Not found on ${streamingService.label}'
            : 'No local file and no streaming service configured',
        durationSeconds: t.durationSeconds,
        bpm: t.bpm, key: t.key,
      ));
    }

    // Ensure all destination directories exist.
    final localMusicDir = Directory(p.join(vdjRoot, _localMusicSubdir));
    await localMusicDir.create(recursive: true);
    final playlistsDir = Directory(p.join(vdjRoot, _playlistsSubdir));
    await playlistsDir.create(recursive: true);
    final myListsDir = Directory(p.join(vdjRoot, 'MyLists'));
    await myListsDir.create(recursive: true);

    // Build the .vdjfolder XML content.
    final safeName = _safeName(playlistName);
    final xml = buildVdjFolder(playlistName, resolved, streamingService);

    // Write to ALL VDJ playlist locations for maximum cross-computer compatibility:

    // 1. Folders/LocalMusic/ — local sidebar on THIS machine
    final localFile = File(p.join(localMusicDir.path, '$safeName.vdjfolder'));
    await localFile.writeAsString(xml, flush: true);
    await _updateOrderFile(localMusicDir.path, safeName);

    // 2. Playlists/ — shows in VDJ Playlists panel (cross-computer)
    final playlistVdjFile = File(p.join(playlistsDir.path, '$safeName.vdjfolder'));
    await playlistVdjFile.writeAsString(xml, flush: true);
    // Also write M3U version for broader compatibility
    final playlistM3uFile = File(p.join(playlistsDir.path, '$safeName.m3u'));
    await _writePlaylistM3u(playlistM3uFile, resolved, streamingService);

    // 3. MyLists/ — shows in VDJ Sideview Lists (cross-computer)
    final myListFile = File(p.join(myListsDir.path, '$safeName.m3u'));
    await _writePlaylistM3u(myListFile, resolved, streamingService);

    return DjExportResult(
      target: DjExportTarget.virtualDj,
      crateName: playlistName,
      rootPath: vdjRoot,
      outputPath: localFile.path,
      tracks: resolved,
      exportedAt: DateTime.now(),
      warnings: [...warnings,
        'Written to: LocalMusic, Playlists, and MyLists for cross-computer access'],
    );
  }

  // ── Streaming track resolution ──────────────────────────────────────────

  /// Resolves a track to a real streaming service track ID.
  /// Returns the numeric ID string, or null if not found.
  Future<String?> _resolveStreamingTrackId(
    VdjStreamingService service,
    String artist,
    String title,
  ) async {
    switch (service) {
      case VdjStreamingService.tidal:
        return _resolveTidalTrackId(artist, title);
      case VdjStreamingService.deezer:
        return _resolveDeezerTrackId(artist, title);
      default:
        // Other services don't have a free search API
        return null;
    }
  }

  /// Search TIDAL for a track and return its numeric ID.
  /// Uses TIDAL's public API (no auth needed for search).
  Future<String?> _resolveTidalTrackId(String artist, String title) async {
    try {
      final query = Uri.encodeComponent(_cleanForSearch('$artist $title'));
      final url = Uri.parse(
        'https://api.tidal.com/v1/search/tracks?query=$query&limit=5&countryCode=US',
      );
      final resp = await http.get(url, headers: {
        'x-tidal-token': 'CzET4vdadNUFQ5JU', // VDJ's public client token
      }).timeout(const Duration(seconds: 8));

      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body);
      final items = data['items'] as List?;
      if (items == null || items.isEmpty) return null;

      // Find best match by comparing artist+title
      final cleanArtist = _cleanForSearch(artist).toLowerCase();
      final cleanTitle = _cleanForSearch(title).toLowerCase();

      for (final item in items) {
        final rTitle = (item['title'] as String? ?? '').toLowerCase();
        final rArtist = (item['artist']?['name'] as String? ?? '').toLowerCase();

        // Check for reasonable match
        if (_fuzzyMatch(cleanTitle, rTitle) && _fuzzyMatch(cleanArtist, rArtist)) {
          return item['id'].toString();
        }
      }

      // Fallback: return first result if query was specific enough
      return items.first['id'].toString();
    } catch (_) {
      return null;
    }
  }

  /// Search Deezer for a track and return its numeric ID.
  /// Deezer's search API is fully public.
  Future<String?> _resolveDeezerTrackId(String artist, String title) async {
    try {
      final query = Uri.encodeComponent(_cleanForSearch('$artist $title'));
      final url = Uri.parse('https://api.deezer.com/search/track?q=$query&limit=5');
      final resp = await http.get(url).timeout(const Duration(seconds: 8));

      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body);
      final items = data['data'] as List?;
      if (items == null || items.isEmpty) return null;

      final cleanArtist = _cleanForSearch(artist).toLowerCase();
      final cleanTitle = _cleanForSearch(title).toLowerCase();

      for (final item in items) {
        final rTitle = (item['title'] as String? ?? '').toLowerCase();
        final rArtist = (item['artist']?['name'] as String? ?? '').toLowerCase();

        if (_fuzzyMatch(cleanTitle, rTitle) && _fuzzyMatch(cleanArtist, rArtist)) {
          return item['id'].toString();
        }
      }

      return items.first['id'].toString();
    } catch (_) {
      return null;
    }
  }

  // ── XML builder ──────────────────────────────────────────────────────────

  /// Builds the .vdjfolder XML.
  ///
  /// Correct VDJ format (lowercase `song`, `path` attribute):
  /// ```xml
  /// <?xml version="1.0" encoding="UTF-8"?>
  /// <VirtualFolder noDuplicates="yes">
  ///   <song path="netsearch://td71717731" songlength="299.0" bpm="112.000"
  ///         key="B" artist="Drake" title="Passionfruit" idx="0" />
  /// </VirtualFolder>
  /// ```
  String buildVdjFolder(
    String playlistName,
    List<DjTrackResolution> resolved,
    VdjStreamingService? streamingService,
  ) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<VirtualFolder noDuplicates="yes">');
    var idx = 0;
    for (final t in resolved) {
      if (t.isSkipped) continue;
      final attrs = StringBuffer();

      // Build path attribute.
      if (t.isLocal && t.localFilePath != null && t.localFilePath!.isNotEmpty) {
        attrs.write('path="${_esc(t.localFilePath!)}"');
      } else if (t.isTidal && t.tidalTrackId != null && streamingService != null) {
        // Real track ID: netsearch://td71717731
        attrs.write('path="netsearch://${streamingService.prefix}${t.tidalTrackId}"');
      } else {
        continue;
      }

      if (t.durationSeconds > 0) {
        attrs.write(' songlength="${t.durationSeconds.toStringAsFixed(1)}"');
      }
      if (t.bpm > 0) attrs.write(' bpm="${t.bpm.toStringAsFixed(3)}"');
      if (t.key.isNotEmpty) attrs.write(' key="${_esc(t.key)}"');
      if (t.artist.isNotEmpty) attrs.write(' artist="${_esc(t.artist)}"');
      if (t.title.isNotEmpty) attrs.write(' title="${_esc(t.title)}"');
      attrs.write(' idx="$idx"');
      buf.writeln('\t<song $attrs />');
      idx++;
    }
    buf.writeln('</VirtualFolder>');
    return buf.toString();
  }

  // ── Order file management ────────────────────────────────────────────────

  /// Adds [sanitizedName] to the `order` file in [destDirPath].
  /// [sanitizedName] must match the .vdjfolder filename (without extension).
  Future<void> _updateOrderFile(String destDirPath, String sanitizedName) async {
    final orderFile = File(p.join(destDirPath, 'order'));
    List<String> lines = [];
    if (orderFile.existsSync()) {
      final content = await orderFile.readAsString();
      lines = content
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    }
    if (!lines.contains(sanitizedName)) {
      lines.add(sanitizedName);
      await orderFile.writeAsString(lines.join('\n') + '\n', flush: true);
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll("'", '&apos;');

  String _safeName(String s) =>
      s.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();

  /// Write a VDJ-compatible M3U playlist to the Playlists folder.
  /// This format is recognized by VDJ across all computers.
  Future<void> _writePlaylistM3u(
    File file,
    List<DjTrackResolution> tracks,
    VdjStreamingService? streaming,
  ) async {
    final buf = StringBuffer('#EXTM3U\n');
    for (final t in tracks) {
      if (t.isSkipped) continue;

      // Determine the path for this track.
      String? path;
      if (t.isLocal && t.localFilePath != null) {
        path = t.localFilePath;
      } else if (t.isTidal && t.tidalTrackId != null && streaming != null) {
        // iDJPool has no VDJ netsearch prefix — skip the track entirely.
        if (streaming == VdjStreamingService.idjpool) continue;
        path = 'netsearch://${streaming.prefix}${t.tidalTrackId}';
      }
      if (path == null) continue;

      final dur = t.durationSeconds.round();
      buf.writeln('#EXTINF:$dur,${t.artist} - ${t.title}');
      buf.writeln(path);
    }
    await file.writeAsString(buf.toString(), flush: true);
  }

  String _matchKey(String title, String artist) =>
      '${title.toLowerCase().trim()}::${artist.toLowerCase().trim()}';

  /// Clean text for search queries.
  String _cleanForSearch(String s) {
    var clean = s;
    clean = clean.replaceAll(RegExp(r'\s*\([^)]*\)'), '');
    clean = clean.replaceAll(RegExp(r'\s*\[[^\]]*\]'), '');
    clean = clean.replaceAll(RegExp(r'\s*(?:feat\.?|ft\.?)\s+.*', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'\s*-\s*(?:Radio Edit|Remix|Edit|Remaster(?:ed)?|Live|Acoustic|Version|Mix|Deluxe|Original|Extended|Sped Up|Slowed).*', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean;
  }

  /// Simple fuzzy match — checks if one string contains most of the other.
  bool _fuzzyMatch(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    if (a.contains(b) || b.contains(a)) return true;
    // Check word overlap
    final wordsA = a.split(RegExp(r'\s+')).toSet();
    final wordsB = b.split(RegExp(r'\s+')).toSet();
    final overlap = wordsA.intersection(wordsB).length;
    final minWords = wordsA.length < wordsB.length ? wordsA.length : wordsB.length;
    return minWords > 0 && overlap / minWords >= 0.5;
  }
}
