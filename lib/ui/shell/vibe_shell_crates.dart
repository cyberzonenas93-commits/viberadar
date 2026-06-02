part of 'vibe_shell.dart';

class _SavedCratesView extends ConsumerWidget {
  const _SavedCratesView({required this.allTracks, required this.crates});

  final List<Track> allTracks;
  final List<Crate> crates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aiCrates = ref.watch(aiCrateProvider).crates;
    // Combine: AI crates + regular crates
    final allCrateNames = <String>{
      ...aiCrates.keys,
      ...crates.map((c) => c.name),
    };
    final hasCrates = allCrateNames.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TitleBlock(
          title: 'Saved Crates',
          subtitle:
              'Your curated sets from AI Copilot and Set Builder — ready to play and export.',
        ),
        const SizedBox(height: 18),
        Expanded(
          child: !hasCrates
              ? Center(
                  child: Text(
                    'No crates yet. Use AI Copilot or Set Builder to create one.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: Colors.white70),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 40),
                  children: [
                    // AI Crates (with playable links)
                    for (final entry in aiCrates.entries) ...[
                      _AiCrateCard(name: entry.key, tracks: entry.value),
                      const SizedBox(height: 12),
                    ],
                    // Regular crates (Firestore ID-based)
                    for (final crate in crates) ...[
                      _RegularCrateCard(crate: crate, allTracks: allTracks),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _AiCrateCard extends StatelessWidget {
  const _AiCrateCard({required this.name, required this.tracks});
  final String name;
  final List<AiCrateTrack> tracks;

  Future<void> _export(BuildContext context, String format) async {
    final svc = ExportService();
    String path;
    switch (format) {
      case 'm3u':
        path = await svc.exportAiCrateM3u(name, tracks);
      case 'csv':
        path = await svc.exportAiCrateCsv(name, tracks);
      case 'manifest':
        path = await svc.exportAiCrateManifest(name, tracks);
      default:
        return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported to $path'),
          backgroundColor: AppTheme.lime,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Show in Finder',
            textColor: Colors.white,
            onPressed: () => ExportService.revealInFinder(path),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolved = tracks.where((t) => t.resolved).length;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.violet.withValues(alpha: 0.3)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.violet.withValues(alpha: 0.06), AppTheme.panel],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.violet, AppTheme.pink],
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 10,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'AI',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$resolved/${tracks.length} playable',
                style: TextStyle(
                  color: resolved == tracks.length
                      ? AppTheme.lime
                      : AppTheme.amber,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Export buttons
          Row(
            children: [
              _ExportBtn(
                label: 'Export M3U',
                icon: Icons.queue_music_rounded,
                onTap: () => _export(context, 'm3u'),
              ),
              const SizedBox(width: 8),
              _ExportBtn(
                label: 'Export CSV',
                icon: Icons.table_chart_rounded,
                onTap: () => _export(context, 'csv'),
              ),
              const SizedBox(width: 8),
              _ExportBtn(
                label: 'Manifest',
                icon: Icons.description_rounded,
                onTap: () => _export(context, 'manifest'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < tracks.length; i++) ...[
            _AiTrackRow(track: tracks[i], index: i),
            if (i < tracks.length - 1)
              Divider(color: AppTheme.edge.withValues(alpha: 0.3), height: 1),
          ],
        ],
      ),
    );
  }
}

class _AiTrackRow extends StatelessWidget {
  const _AiTrackRow({required this.track, required this.index});
  final AiCrateTrack track;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // Index
          SizedBox(
            width: 24,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Artwork
          if (track.artworkUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: track.artworkUrl!,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.panelRaised,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.music_note_rounded,
                color: AppTheme.textTertiary,
                size: 16,
              ),
            ),
          const SizedBox(width: 10),
          // Title + artist
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  track.artist,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // BPM + Key
          if (track.bpm > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: AppTheme.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${track.bpm}',
                style: const TextStyle(
                  color: AppTheme.amber,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (track.key.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: AppTheme.edge.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                track.key,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          // Play buttons
          if (track.spotifyUrl != null)
            _PlatformPlayBtn(
              icon: Icons.graphic_eq_rounded,
              color: const Color(0xFF1ED760),
              url: track.spotifyUrl!,
              tooltip: 'Play on Spotify',
            ),
          if (track.appleUrl != null)
            _PlatformPlayBtn(
              icon: Icons.music_note_rounded,
              color: const Color(0xFFFF7AB5),
              url: track.appleUrl!,
              tooltip: 'Play on Apple Music',
            ),
          if (!track.resolved)
            const Tooltip(
              message: 'Not found on platforms',
              child: Icon(
                Icons.cloud_off_rounded,
                color: AppTheme.textTertiary,
                size: 16,
              ),
            ),
        ],
      ),
    );
  }
}

class _PlatformPlayBtn extends StatelessWidget {
  const _PlatformPlayBtn({
    required this.icon,
    required this.color,
    required this.url,
    required this.tooltip,
  });
  final IconData icon;
  final Color color;
  final String url;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            final uri = Uri.tryParse(url);
            if (uri != null) {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, color: color, size: 18),
          ),
        ),
      ),
    );
  }
}

class _ExportBtn extends StatelessWidget {
  const _ExportBtn({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.cyan.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppTheme.cyan, size: 14),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.cyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegularCrateCard extends StatelessWidget {
  const _RegularCrateCard({required this.crate, required this.allTracks});
  final Crate crate;
  final List<Track> allTracks;

  Future<void> _export(
    BuildContext context,
    String format,
    List<Track> tracks,
  ) async {
    // Show immediate feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exporting $format...'),
        backgroundColor: AppTheme.cyan,
        duration: const Duration(seconds: 1),
      ),
    );

    final svc = ExportService();
    final name = crate.name;
    final libTracks = tracks
        .map(
          (t) => LibraryTrack(
            id: t.id,
            filePath: '',
            fileName: '${t.artist} - ${t.title}',
            title: t.title,
            artist: t.artist,
            album: '',
            genre: t.genre,
            bpm: t.bpm.toDouble(),
            key: t.keySignature,
            durationSeconds: 0,
            fileSizeBytes: 0,
            fileExtension: '.mp3',
            md5Hash: '',
            bitrate: 320,
            sampleRate: 44100,
          ),
        )
        .toList();
    final exportCrate = ExportCrate(name: name, tracks: libTracks);

    String path;
    switch (format) {
      case 'm3u':
        path = await svc.exportM3u(exportCrate);
      case 'csv':
        path = await svc.exportSeratoCsv(exportCrate);
      case 'rekordbox':
        path = await svc.exportRekordboxXml(exportCrate);
      case 'virtualdj':
        path = await svc.exportVirtualDjXml(exportCrate);
      case 'traktor':
        path = await svc.exportTraktorNml(exportCrate);
      case 'manifest':
        path = await svc.exportAiCrateManifest(
          name,
          tracks.map((t) {
            // Wrap as dynamic with required fields
            return _TrackExportProxy(t);
          }).toList(),
        );
      default:
        return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported to $path'),
          backgroundColor: AppTheme.lime,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Show in Finder',
            textColor: Colors.white,
            onPressed: () => ExportService.revealInFinder(path),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracks = crate.trackIds
        .map((id) => allTracks.firstWhereOrNull((t) => t.id == id))
        .whereType<Track>()
        .toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.edge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_fix_high_rounded,
                      color: AppTheme.amber,
                      size: 10,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'SET',
                      style: TextStyle(
                        color: AppTheme.amber,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  crate.name,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${tracks.length} tracks',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          if (crate.context.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              crate.context,
              style: const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 10),
          // Export buttons
          Row(
            children: [
              _ExportBtn(
                label: 'M3U',
                icon: Icons.queue_music_rounded,
                onTap: () => _export(context, 'm3u', tracks),
              ),
              const SizedBox(width: 6),
              _ExportBtn(
                label: 'Serato',
                icon: Icons.table_chart_rounded,
                onTap: () => _export(context, 'csv', tracks),
              ),
              const SizedBox(width: 6),
              _ExportBtn(
                label: 'Rekordbox',
                icon: Icons.album_rounded,
                onTap: () => _export(context, 'rekordbox', tracks),
              ),
              const SizedBox(width: 6),
              _ExportBtn(
                label: 'VirtualDJ',
                icon: Icons.surround_sound_rounded,
                onTap: () => _export(context, 'virtualdj', tracks),
              ),
              const SizedBox(width: 6),
              _ExportBtn(
                label: 'Traktor',
                icon: Icons.speaker_rounded,
                onTap: () => _export(context, 'traktor', tracks),
              ),
              const SizedBox(width: 6),
              _ExportBtn(
                label: 'Manifest',
                icon: Icons.description_rounded,
                onTap: () => _export(context, 'manifest', tracks),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < tracks.length; i++) ...[
            _CrateTrackRow(track: tracks[i], index: i),
            if (i < tracks.length - 1)
              Divider(color: AppTheme.edge.withValues(alpha: 0.3), height: 1),
          ],
        ],
      ),
    );
  }
}

class _CrateTrackRow extends StatelessWidget {
  const _CrateTrackRow({required this.track, required this.index});
  final Track track;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // Index
          SizedBox(
            width: 24,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Artwork
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: track.artworkUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: track.artworkUrl,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => _trackArtPlaceholder(),
                  )
                : _trackArtPlaceholder(),
          ),
          const SizedBox(width: 10),
          // Title + artist
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  track.artist,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // BPM
          if (track.bpm > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: AppTheme.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${track.bpm}',
                style: const TextStyle(
                  color: AppTheme.amber,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          // Key
          if (track.keySignature.isNotEmpty && track.keySignature != '--')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: AppTheme.edge.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                track.keySignature,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          // Genre
          Text(
            track.genre,
            style: TextStyle(
              color: AppTheme.violet.withValues(alpha: 0.6),
              fontSize: 10,
            ),
          ),
          const SizedBox(width: 8),
          // Play buttons per platform
          for (final entry in track.platformLinks.entries.take(3))
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: _PlatformPlayBtn(
                icon: _platformIcon(entry.key),
                color: _platformColor(entry.key),
                url: entry.value,
                tooltip:
                    'Play on ${entry.key[0].toUpperCase()}${entry.key.substring(1)}',
              ),
            ),
        ],
      ),
    );
  }

  static Widget _trackArtPlaceholder() => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: AppTheme.panelRaised,
      borderRadius: BorderRadius.circular(6),
    ),
    child: const Icon(
      Icons.music_note_rounded,
      color: AppTheme.textTertiary,
      size: 16,
    ),
  );

  static IconData _platformIcon(String p) => switch (p.toLowerCase()) {
    'spotify' => Icons.graphic_eq_rounded,
    'apple' => Icons.music_note_rounded,
    'youtube' => Icons.play_circle_fill_rounded,
    'deezer' => Icons.headphones_rounded,
    'soundcloud' => Icons.cloud_rounded,
    _ => Icons.open_in_new_rounded,
  };

  static Color _platformColor(String p) => switch (p.toLowerCase()) {
    'spotify' => const Color(0xFF1ED760),
    'apple' => const Color(0xFFFF7AB5),
    'youtube' => const Color(0xFFFF4B4B),
    'deezer' => const Color(0xFFA238FF),
    'soundcloud' => const Color(0xFFFFA237),
    _ => AppTheme.cyan,
  };
}
