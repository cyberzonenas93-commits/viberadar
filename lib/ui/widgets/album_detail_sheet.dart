import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/library_provider.dart';
import '../../providers/streaming_provider.dart';
import '../../services/platform_search_service.dart';

/// Shows album details as a dialog: artwork, track list, play/add-to-crate.
void showAlbumDetailSheet(
  BuildContext context,
  PlatformAlbumResult album,
) {
  showDialog(
    context: context,
    builder: (_) => _AlbumDetailDialog(album: album),
  );
}

class _AlbumDetailDialog extends ConsumerStatefulWidget {
  const _AlbumDetailDialog({required this.album});
  final PlatformAlbumResult album;

  @override
  ConsumerState<_AlbumDetailDialog> createState() => _AlbumDetailDialogState();
}

class _AlbumDetailDialogState extends ConsumerState<_AlbumDetailDialog> {
  final _search = PlatformSearchService();
  List<PlatformTrackResult> _tracks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    final albumId = widget.album.spotifyId ?? widget.album.appleMusicId ?? widget.album.id;
    final tracks = await _search.getAlbumTracks(albumId, widget.album.platform);
    if (mounted) {
      setState(() {
        _tracks = tracks;
        _loading = false;
      });
    }
  }

  void _playTrack(PlatformTrackResult t) {
    ref.read(appleMusicProvider.notifier).playByQuery(t.title, t.artist);
  }

  void _playAll() {
    if (_tracks.isEmpty) return;
    // Play the first track, queue the rest
    final first = _tracks.first;
    final queue = _tracks.skip(1).map((t) => (t.title, t.artist)).toList();
    ref.read(appleMusicProvider.notifier).playByQuery(first.title, first.artist, queue: queue);
  }

  void _addAllToCrate() {
    if (_tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tracks are still loading. Please wait.'),
          backgroundColor: AppTheme.amber,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final crateState = ref.read(crateProvider);
    final crates = crateState.crates.keys.toList();

    showDialog(
      context: context,
      builder: (ctx) => _CratePickerDialog(
        title: 'Add Album to Crate',
        subtitle: '${widget.album.name} (${_tracks.length} tracks)',
        crates: crates,
        onPick: (name) {
          for (final t in _tracks) {
            final trackId = '${widget.album.platform}:${t.title}:${t.artist}';
            ref.read(crateProvider.notifier).addTrackToCrate(name, trackId);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Added ${_tracks.length} tracks to $name'),
                backgroundColor: AppTheme.violet,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
        onNewCrate: (name) {
          ref.read(crateProvider.notifier).createCrate(name);
          for (final t in _tracks) {
            final trackId = '${widget.album.platform}:${t.title}:${t.artist}';
            ref.read(crateProvider.notifier).addTrackToCrate(name, trackId);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Created "$name" and added ${_tracks.length} tracks'),
                backgroundColor: AppTheme.violet,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
      ),
    );
  }

  void _addTrackToCrate(PlatformTrackResult t) {
    final crateState = ref.read(crateProvider);
    final crates = crateState.crates.keys.toList();
    final trackId = '${widget.album.platform}:${t.title}:${t.artist}';

    showDialog(
      context: context,
      builder: (ctx) => _CratePickerDialog(
        title: 'Add to Crate',
        subtitle: t.title,
        crates: crates,
        onPick: (name) {
          ref.read(crateProvider.notifier).addTrackToCrate(name, trackId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Added "${t.title}" to $name'),
                backgroundColor: AppTheme.violet,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
        onNewCrate: (name) {
          ref.read(crateProvider.notifier).createCrate(name);
          ref.read(crateProvider.notifier).addTrackToCrate(name, trackId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Created "$name" and added "${t.title}"'),
                backgroundColor: AppTheme.violet,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    final am = ref.watch(appleMusicProvider);

    return Dialog(
      backgroundColor: AppTheme.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 480,
        constraints: const BoxConstraints(maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Album header ────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.violet.withValues(alpha: 0.12),
                    AppTheme.panel,
                  ],
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Album artwork
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 120,
                      height: 120,
                      child: album.artworkUrl != null
                          ? CachedNetworkImage(
                              imageUrl: album.artworkUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => _artPlaceholder(),
                            )
                          : _artPlaceholder(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Album info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          album.name,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          album.artist,
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            if (album.year.isNotEmpty)
                              _InfoChip(label: album.year, icon: Icons.calendar_today_rounded),
                            _InfoChip(
                              label: '${album.trackCount} tracks',
                              icon: Icons.music_note_rounded,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Action buttons
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _AlbumActionBtn(
                              icon: Icons.play_arrow_rounded,
                              label: 'Play All',
                              color: AppTheme.cyan,
                              onTap: _playAll,
                            ),
                            _AlbumActionBtn(
                              icon: Icons.playlist_add_rounded,
                              label: 'Add All to Crate',
                              color: AppTheme.violet,
                              onTap: _addAllToCrate,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Close button
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppTheme.textTertiary, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const Divider(color: AppTheme.edge, height: 1),
            // ── Track list ──────────────────────────────────────────────
            Flexible(
              child: _loading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: AppTheme.cyan, strokeWidth: 2),
                            SizedBox(height: 12),
                            Text('Loading tracks...', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                          ],
                        ),
                      ),
                    )
                  : _tracks.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: Text('No tracks found', style: TextStyle(color: AppTheme.textTertiary)),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _tracks.length,
                          itemBuilder: (ctx, i) {
                            final t = _tracks[i];
                            final isPlaying = am.currentTrack?.title == t.title &&
                                am.currentTrack?.artist == t.artist &&
                                am.isPlaying;
                            return _TrackRow(
                              track: t,
                              index: i + 1,
                              isPlaying: isPlaying,
                              onPlay: () => _playTrack(t),
                              onAddToCrate: () => _addTrackToCrate(t),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _artPlaceholder() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [AppTheme.edge, AppTheme.panelRaised]),
        ),
        child: const Center(
          child: Icon(Icons.album_rounded, color: AppTheme.textTertiary, size: 40),
        ),
      );
}

// ── Track row ──────────────────────────────────────────────────────────────

class _TrackRow extends StatefulWidget {
  const _TrackRow({
    required this.track,
    required this.index,
    required this.isPlaying,
    required this.onPlay,
    required this.onAddToCrate,
  });
  final PlatformTrackResult track;
  final int index;
  final bool isPlaying;
  final VoidCallback onPlay;
  final VoidCallback onAddToCrate;

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> {
  bool _hovered = false;

  String _formatDuration(int ms) {
    if (ms == 0) return '';
    final m = ms ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPlay,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          color: _hovered ? AppTheme.panelRaised.withValues(alpha: 0.5) : Colors.transparent,
          child: Row(
            children: [
              // Track number / play icon
              SizedBox(
                width: 28,
                child: _hovered || widget.isPlaying
                    ? Icon(
                        widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: widget.isPlaying ? const Color(0xFFFC3C44) : AppTheme.cyan,
                        size: 18,
                      )
                    : Text(
                        '${widget.index}',
                        style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
              ),
              const SizedBox(width: 12),
              // Track info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.title,
                      style: TextStyle(
                        color: widget.isPlaying ? const Color(0xFFFC3C44) : AppTheme.textPrimary,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      t.artist,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Duration
              if (_formatDuration(t.durationMs).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    _formatDuration(t.durationMs),
                    style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11),
                  ),
                ),
              // Add to crate button (visible on hover)
              if (_hovered)
                GestureDetector(
                  onTap: widget.onAddToCrate,
                  child: Tooltip(
                    message: 'Add to Crate',
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppTheme.violet.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.violet.withValues(alpha: 0.3)),
                      ),
                      child: const Icon(Icons.playlist_add_rounded, color: AppTheme.violet, size: 15),
                    ),
                  ),
                )
              else
                const SizedBox(width: 28),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Info chip ───────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.textTertiary, size: 12),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}

// ── Album action button ────────────────────────────────────────────────────

class _AlbumActionBtn extends StatelessWidget {
  const _AlbumActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 15),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Crate picker dialog (reusable) ─────────────────────────────────────────

class _CratePickerDialog extends StatefulWidget {
  const _CratePickerDialog({
    required this.title,
    required this.subtitle,
    required this.crates,
    required this.onPick,
    required this.onNewCrate,
  });
  final String title;
  final String subtitle;
  final List<String> crates;
  final void Function(String name) onPick;
  final void Function(String name) onNewCrate;

  @override
  State<_CratePickerDialog> createState() => _CratePickerDialogState();
}

class _CratePickerDialogState extends State<_CratePickerDialog> {
  final _newCtrl = TextEditingController();
  bool _creatingNew = false;

  @override
  void dispose() {
    _newCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.playlist_add_rounded, color: AppTheme.violet, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(widget.title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
            const SizedBox(height: 4),
            Text(widget.subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 16),

            if (widget.crates.isEmpty && !_creatingNew)
              const Text('No crates yet — create one below.', style: TextStyle(color: AppTheme.textTertiary, fontSize: 12)),

            if (widget.crates.isNotEmpty && !_creatingNew) ...[
              const Text('EXISTING CRATES', style: TextStyle(color: AppTheme.textTertiary, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              ...widget.crates.map((name) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.folder_rounded, color: AppTheme.violet, size: 18),
                    title: Text(name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                    onTap: () {
                      widget.onPick(name);
                      Navigator.of(context).pop();
                    },
                  )),
              const Divider(color: AppTheme.edge, height: 20),
            ],

            if (_creatingNew) ...[
              TextField(
                controller: _newCtrl,
                autofocus: true,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'New crate name...',
                  hintStyle: const TextStyle(color: AppTheme.textTertiary),
                  filled: true,
                  fillColor: AppTheme.panelRaised,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.edge)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.edge)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.violet)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onSubmitted: (v) {
                  if (v.trim().isEmpty) return;
                  widget.onNewCrate(v.trim());
                  Navigator.of(context).pop();
                },
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _creatingNew = false),
                    child: const Text('Back', style: TextStyle(color: AppTheme.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final name = _newCtrl.text.trim();
                      if (name.isEmpty) return;
                      widget.onNewCrate(name);
                      Navigator.of(context).pop();
                    },
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.violet),
                    child: const Text('Create & Add'),
                  ),
                ],
              ),
            ] else
              TextButton.icon(
                onPressed: () => setState(() => _creatingNew = true),
                icon: const Icon(Icons.add_rounded, size: 16, color: AppTheme.violet),
                label: const Text('New Crate', style: TextStyle(color: AppTheme.violet)),
              ),
          ],
        ),
      ),
    );
  }
}
