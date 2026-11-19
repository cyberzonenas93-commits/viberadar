part of 'vibe_shell.dart';

const _collapsedTrackPreviewLimit = 6;
const _expandedTrackRenderLimit = 80;

class _SavedCratesView extends ConsumerWidget {
  const _SavedCratesView({
    required this.allTracks,
    required this.crates,
    required this.localLibrary,
  });

  final List<Track> allTracks;
  final List<Crate> crates;
  final List<LibraryTrack> localLibrary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aiCrates = ref.watch(aiCrateProvider).crates;
    final aiEntries = aiCrates.entries.toList(growable: false);
    final allCrateNames = <String>{
      ...aiCrates.keys,
      ...crates.map((c) => c.name),
    };
    final hasCrates = allCrateNames.isNotEmpty;
    final itemCount = aiEntries.length + crates.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TitleBlock(
          title: 'Saved Setlists',
          subtitle:
              'Your synced setlists from phone, AI Copilot, and Set Builder — ready to match and export.',
        ),
        const SizedBox(height: 18),
        Expanded(
          child: !hasCrates
              ? Center(
                  child: Text(
                    'No setlists yet. Use AI Copilot or Set Builder to create one.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: Colors.white70),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 40),
                  itemCount: itemCount,
                  itemBuilder: (context, index) {
                    final child = index < aiEntries.length
                        ? _AiCrateCard(
                            name: aiEntries[index].key,
                            tracks: aiEntries[index].value,
                          )
                        : _RegularCrateCard(
                            crate: crates[index - aiEntries.length],
                            allTracks: allTracks,
                            localLibrary: localLibrary,
                            onOpenInStudio: () => _openInStudio(
                              ref,
                              context,
                              crates[index - aiEntries.length],
                            ),
                          );
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == itemCount - 1 ? 0 : 12,
                      ),
                      child: child,
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Loads a synced phone setlist into the Export Studio bench (the unified
  /// crate store the desktop's full match/export UI works from) and switches to
  /// it. Rich entries are encoded so the Studio resolves them against the local
  /// library; legacy id-only references are enriched from the live feed first.
  void _openInStudio(WidgetRef ref, BuildContext context, Crate crate) {
    final resolved = resolveCrateTracks(crate.tracks, allTracks);
    final ids = resolved.tracks.map(exportStudioId).toList();
    ref.read(crateProvider.notifier).importCrate(crate.name, ids);
    ref
        .read(workspaceControllerProvider.notifier)
        .setSection(AppSection.exports);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Opened "${crate.name}" in Export Studio — match to your library and '
          'export below.',
        ),
        backgroundColor: AppTheme.violet,
        duration: const Duration(seconds: 4),
      ),
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
    await const SetBuilderBehaviorService().recordTracks(
      event: SetBuilderBehaviorEvent.export,
      tracks: tracks.map(_platformResultFromAiCrateTrack),
    );
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
    final visibleTracks = tracks
        .take(_collapsedTrackPreviewLimit)
        .toList(growable: false);
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
          for (var i = 0; i < visibleTracks.length; i++) ...[
            _AiTrackRow(track: visibleTracks[i], index: i),
            if (i < visibleTracks.length - 1)
              Divider(color: AppTheme.edge.withValues(alpha: 0.3), height: 1),
          ],
          if (tracks.length > visibleTracks.length)
            _TrackPreviewNotice(
              shown: visibleTracks.length,
              total: tracks.length,
            ),
        ],
      ),
    );
  }
}

PlatformTrackResult _platformResultFromAiCrateTrack(AiCrateTrack track) {
  final confidence = track.confidence ?? 0;
  return PlatformTrackResult(
    title: track.title,
    artist: track.artist,
    artworkUrl: track.artworkUrl,
    spotifyUrl: track.spotifyUrl,
    appleUrl: track.appleUrl,
    youtubeUrl: track.youtubeUrl,
    soundchartsUrl: track.soundchartsUrl,
    soundchartsSource: track.soundchartsSource,
    soundchartsRegion: track.soundchartsRegion,
    popularity: (confidence * 100).round().clamp(0, 100),
    trendScore: confidence,
  );
}

class _TrackPreviewNotice extends StatelessWidget {
  const _TrackPreviewNotice({
    required this.shown,
    required this.total,
    this.expanded = false,
  });

  final int shown;
  final int total;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final message = expanded
        ? 'Showing $shown of $total tracks. Export Studio and exports use the full setlist.'
        : 'Showing first $shown of $total tracks. Export Studio and exports use the full setlist.';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        message,
        style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11),
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
                if (track.phaseLabel != null || track.reasons.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (track.phaseLabel != null) track.phaseLabel!,
                      if (track.confidence != null)
                        '${(track.confidence! * 100).round()}%',
                      if (track.reasons.isNotEmpty) track.reasons.first,
                    ].join(' · '),
                    style: const TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
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
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 112),
            child: PlatformPlayActions.fromUrls(
              spotifyUrl: track.spotifyUrl,
              appleUrl: track.appleUrl,
              youtubeUrl: track.youtubeUrl,
              compact: true,
              maxLinks: 3,
              alignment: WrapAlignment.end,
            ),
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

class _ExportBtn extends StatelessWidget {
  const _ExportBtn({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isBusy = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: isBusy ? null : onTap,
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
              if (isBusy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.cyan,
                  ),
                )
              else
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

class _RegularCrateCard extends ConsumerStatefulWidget {
  const _RegularCrateCard({
    required this.crate,
    required this.allTracks,
    required this.localLibrary,
    required this.onOpenInStudio,
  });
  final Crate crate;
  final List<Track> allTracks;
  final List<LibraryTrack> localLibrary;

  /// Loads this crate into the desktop Export Studio bench (match panel,
  /// candidate disambiguation, physical crates) — the unified export surface.
  final VoidCallback onOpenInStudio;

  @override
  ConsumerState<_RegularCrateCard> createState() => _RegularCrateCardState();
}

class _RegularCrateCardState extends ConsumerState<_RegularCrateCard> {
  bool _expanded = false;
  bool _preparingFolder = false;

  Future<void> _export(
    BuildContext context,
    String format,
    List<Track> tracks,
  ) async {
    final svc = ExportService();
    final name = widget.crate.name;
    final messenger = ScaffoldMessenger.of(context);

    // ── Streaming manifest: platform URLs, works without any local files ──────
    if (format == 'manifest') {
      final path = await svc.exportAiCrateManifest(
        name,
        tracks.map(_TrackExportProxy.new).toList(),
      );
      _showExported(messenger, path);
      return;
    }

    // ── DJ-software formats need real local file paths ────────────────────────
    // Match the crate against the scanned library so exports point at audio that
    // actually exists. (Writing empty paths produced playlists DJ software
    // couldn't load — the whole point of "ready to export" was being defeated.)
    if (widget.localLibrary.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Scan your music in the Library tab first so "$name" can be matched '
            'to your audio files. (Use Manifest for a streaming list meanwhile.)',
          ),
          backgroundColor: AppTheme.amber,
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text('Matching ${tracks.length} tracks to your library…'),
        backgroundColor: AppTheme.cyan,
        duration: const Duration(seconds: 1),
      ),
    );

    final plan = await planLocalExport(
      tracks: tracks,
      library: widget.localLibrary,
    );

    if (plan.matched.isEmpty) {
      final missingPath = await svc.exportMissingManifest(name, plan.missing);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'None of ${tracks.length} tracks were found locally — wrote a '
            'missing-tracks list instead.',
          ),
          backgroundColor: AppTheme.amber,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Show in Finder',
            textColor: Colors.white,
            onPressed: () => ExportService.revealInFinder(missingPath),
          ),
        ),
      );
      return;
    }

    final exportCrate = ExportCrate(name: name, tracks: plan.matched);
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
      default:
        return;
    }

    // Always leave a record of what the DJ still needs to source.
    if (plan.hasMissing) {
      await svc.exportMissingManifest(name, plan.missing);
    }
    _showExported(
      messenger,
      path,
      matched: plan.matched.length,
      missing: plan.missing.length,
    );
  }

  Future<void> _prepareSetFolder(
    BuildContext context,
    List<Track> tracks,
  ) async {
    if (_preparingFolder) return;

    final messenger = ScaffoldMessenger.of(context);
    final name = widget.crate.name;

    if (tracks.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('This setlist has no tracks to prepare.'),
          backgroundColor: AppTheme.amber,
        ),
      );
      return;
    }

    setState(() => _preparingFolder = true);

    try {
      var library = widget.localLibrary;
      if (library.isEmpty) {
        final musicFolder = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Choose your music folder to search',
        );
        if (!mounted || musicFolder == null) return;

        messenger.showSnackBar(
          SnackBar(
            content: Text('Scanning "$musicFolder" for local tracks…'),
            backgroundColor: AppTheme.cyan,
            duration: const Duration(seconds: 3),
          ),
        );

        await ref.read(libraryProvider.notifier).scanDirectory(musicFolder);
        if (!mounted) return;

        final libraryState = ref.read(libraryProvider);
        if (libraryState.error != null) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Could not scan music folder: ${libraryState.error}',
              ),
              backgroundColor: AppTheme.amber,
              duration: const Duration(seconds: 5),
            ),
          );
          return;
        }

        library = libraryState.tracks;
        if (library.isEmpty) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'No supported audio files were found in that folder.',
              ),
              backgroundColor: AppTheme.amber,
              duration: Duration(seconds: 5),
            ),
          );
          return;
        }
      }

      final destination = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose where to create the set folder',
      );
      if (!mounted || destination == null) return;

      messenger.showSnackBar(
        SnackBar(
          content: Text('Preparing "$name" for Serato / VirtualDJ…'),
          backgroundColor: AppTheme.cyan,
          duration: const Duration(seconds: 2),
        ),
      );

      final result = await SetFolderPreparationService().prepare(
        crateName: name,
        tracks: tracks,
        library: library,
        destinationParentDir: destination,
        aiAssist: ref.read(liveCatalogAccessProvider).hasLiveAccess
            ? _buildSetFolderAiNotes
            : null,
      );

      if (!mounted) return;

      final detail = StringBuffer()
        ..write('Prepared ${result.copiedCount} track')
        ..write(result.copiedCount == 1 ? '' : 's');
      if (result.missingCount > 0) {
        detail.write(' · ${result.missingCount} missing');
      }
      if (result.reviewCount > 0) {
        detail.write(' · ${result.reviewCount} to review');
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text('$detail → ${result.folderPath}'),
          backgroundColor: AppTheme.lime,
          duration: const Duration(seconds: 7),
          action: SnackBarAction(
            label: 'Show in Finder',
            textColor: Colors.white,
            onPressed: () => ExportService.revealInFinder(result.folderPath),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not prepare "$name": $e'),
          backgroundColor: AppTheme.amber,
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _preparingFolder = false);
    }
  }

  Future<String?> _buildSetFolderAiNotes(SetFolderAiAssistContext input) async {
    try {
      final payload = {
        'setlist': input.crateName,
        'copied': input.copied
            .take(40)
            .map(
              (item) => {
                'track': _trackLabel(item.track),
                'file': _basename(item.destinationPath),
                'matchMethod': item.matchMethod,
                'confidence': item.confidence,
              },
            )
            .toList(),
        'missing': input.missing
            .take(30)
            .map(
              (item) => {
                'track': _trackLabel(item.track),
                'tidalSearchUrl': item.tidalSearchUrl,
                'platforms': item.platformUrls.keys.toList(),
              },
            )
            .toList(),
        'review': input.review
            .take(20)
            .map(
              (item) => {
                'track': _trackLabel(item.track),
                'matchMethod': item.matchMethod,
                'confidence': item.confidence,
                'candidateFiles': item.candidates.map(_basename).toList(),
              },
            )
            .toList(),
      };

      final raw = await AiCopilotService()
          .requestJson([
            {
              'role': 'system',
              'content':
                  'You help DJs prepare local set folders for Serato and '
                  'VirtualDJ. Return strict JSON with "summary" as one short '
                  'string and "actions" as up to five short strings. Do not '
                  'invent file paths or claim a missing song exists locally.',
            },
            {'role': 'user', 'content': jsonEncode(payload)},
          ])
          .timeout(const Duration(seconds: 12));
      final decoded = jsonDecode(_stripJsonFence(raw));
      if (decoded is! Map) return null;

      final lines = <String>[];
      final summary = decoded['summary'];
      if (summary is String && summary.trim().isNotEmpty) {
        lines.add(summary.trim());
      }
      final actions = decoded['actions'];
      if (actions is List) {
        for (final action in actions.take(5)) {
          final text = action.toString().trim();
          if (text.isNotEmpty) lines.add('- $text');
        }
      }
      return lines.isEmpty ? null : lines.join('\n');
    } catch (e, stack) {
      developer.log(
        'Set folder AI assist unavailable',
        name: 'SetFolder',
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  String _stripJsonFence(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('```')) return trimmed;
    return trimmed
        .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();
  }

  String _trackLabel(Track track) => '${track.artist} - ${track.title}'.trim();

  String _basename(String path) => path.split(RegExp(r'[\\/]+')).last;

  void _showExported(
    ScaffoldMessengerState messenger,
    String path, {
    int? matched,
    int? missing,
  }) {
    final prefix = matched == null
        ? ''
        : '$matched track${matched == 1 ? '' : 's'}'
              '${(missing ?? 0) > 0 ? ' · $missing not in library' : ''} → ';
    messenger.showSnackBar(
      SnackBar(
        content: Text('Exported $prefix$path'),
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

  @override
  Widget build(BuildContext context) {
    // Render from the crate's own rich entries (title/artist/bpm/links), only
    // enriching id-only legacy references from the live feed. The old id-lookup
    // silently dropped AI tracks and any track that had decayed out of the feed.
    final resolved = resolveCrateTracks(widget.crate.tracks, widget.allTracks);
    final tracks = resolved.tracks;
    final visibleLimit = _expanded
        ? _expandedTrackRenderLimit
        : _collapsedTrackPreviewLimit;
    final visibleTracks = tracks.take(visibleLimit).toList(growable: false);
    final canExpand = tracks.length > _collapsedTrackPreviewLimit;

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
                      'SETLIST',
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
                  widget.crate.name,
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
          if (widget.crate.context.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              widget.crate.context,
              style: const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 11,
              ),
            ),
          ],
          if (resolved.droppedReferences > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: AppTheme.amber,
                  size: 12,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${resolved.droppedReferences} older track'
                    '${resolved.droppedReferences == 1 ? '' : 's'} '
                    'dropped off the charts and can\'t be shown — re-add '
                    'on your phone to refresh.',
                    style: const TextStyle(color: AppTheme.amber, fontSize: 10),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          // Export actions — wrap so they never overflow the card width.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Primary: hand off to the full Export Studio (match panel,
              // candidate disambiguation, physical crates).
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: widget.onOpenInStudio,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.violet, AppTheme.pink],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tune_rounded, color: Colors.white, size: 14),
                        SizedBox(width: 6),
                        Text(
                          'Open in Export Studio',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _ExportBtn(
                label: _preparingFolder ? 'Preparing' : 'Prepare Folder',
                icon: Icons.folder_copy_rounded,
                isBusy: _preparingFolder,
                onTap: () => _prepareSetFolder(context, tracks),
              ),
              _ExportBtn(
                label: 'M3U',
                icon: Icons.queue_music_rounded,
                onTap: () => _export(context, 'm3u', tracks),
              ),
              _ExportBtn(
                label: 'Serato',
                icon: Icons.table_chart_rounded,
                onTap: () => _export(context, 'csv', tracks),
              ),
              _ExportBtn(
                label: 'Rekordbox',
                icon: Icons.album_rounded,
                onTap: () => _export(context, 'rekordbox', tracks),
              ),
              _ExportBtn(
                label: 'VirtualDJ',
                icon: Icons.surround_sound_rounded,
                onTap: () => _export(context, 'virtualdj', tracks),
              ),
              _ExportBtn(
                label: 'Traktor',
                icon: Icons.speaker_rounded,
                onTap: () => _export(context, 'traktor', tracks),
              ),
              _ExportBtn(
                label: 'Manifest',
                icon: Icons.description_rounded,
                onTap: () => _export(context, 'manifest', tracks),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < visibleTracks.length; i++) ...[
            _CrateTrackRow(track: visibleTracks[i], index: i),
            if (i < visibleTracks.length - 1)
              Divider(color: AppTheme.edge.withValues(alpha: 0.3), height: 1),
          ],
          if (tracks.length > visibleTracks.length)
            _TrackPreviewNotice(
              shown: visibleTracks.length,
              total: tracks.length,
              expanded: _expanded,
            ),
          if (canExpand)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded
                      ? Icons.unfold_less_rounded
                      : Icons.unfold_more_rounded,
                  size: 18,
                ),
                label: Text(_expanded ? 'Show fewer tracks' : 'Preview more'),
              ),
            ),
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
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 112),
            child: PlatformPlayActions(
              links: track.platformLinks,
              compact: true,
              maxLinks: 3,
              alignment: WrapAlignment.end,
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
}
