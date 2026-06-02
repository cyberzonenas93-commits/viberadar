part of 'search_screen.dart';

// ── Discovery (no query) ──────────────────────────────────────────────────────

class _DiscoveryView extends StatelessWidget {
  const _DiscoveryView({required this.topTracks, required this.onGenreSearch});
  final List<Track> topTracks;
  final void Function(String genre) onGenreSearch;

  @override
  Widget build(BuildContext context) {
    final trending = topTracks.take(12).toList();
    final recent = [...topTracks]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final recentTop = recent.take(12).toList();

    final genres = <String>[
      'Afrobeats', 'Amapiano', 'Hip-Hop', 'House', 'R&B',
      'Dancehall', 'Drill', 'Dance', 'Latin', 'UK Garage',
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Genre shortcuts
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: genres
                .map((g) => _GenreChip(
                      label: g,
                      onTap: () => onGenreSearch(g),
                    ))
                .toList(),
          ),
          const SizedBox(height: 32),

          if (trending.isNotEmpty) ...[
            _SectionLabel(icon: Icons.local_fire_department_rounded, color: AppTheme.amber, label: 'Trending Now'),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: trending.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (ctx, i) => _FirestoreTrackCard(track: trending[i], rank: i + 1),
              ),
            ),
            const SizedBox(height: 32),
          ],

          if (recentTop.isNotEmpty) ...[
            _SectionLabel(icon: Icons.new_releases_rounded, color: AppTheme.cyan, label: 'Hot This Week'),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: recentTop.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (ctx, i) => _FirestoreTrackCard(track: recentTop[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.color, required this.label});
  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
      ],
    );
  }
}

class _GenreChip extends StatelessWidget {
  const _GenreChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.panelRaised,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
          ),
          child: Text(label, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }
}

class _FirestoreTrackCard extends StatelessWidget {
  const _FirestoreTrackCard({required this.track, this.rank});
  final Track track;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130,
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                  child: SizedBox.expand(
                    child: track.artworkUrl.isNotEmpty
                        ? CachedNetworkImage(imageUrl: track.artworkUrl, fit: BoxFit.cover)
                        : Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppTheme.edge, AppTheme.panelRaised],
                              ),
                            ),
                            child: const Icon(Icons.music_note_rounded, color: AppTheme.textTertiary, size: 28),
                          ),
                  ),
                ),
                if (rank != null)
                  Positioned(
                    top: 6, left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text('#$rank', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(track.title, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(track.artist, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.label, required this.color, required this.tooltip});
  final String label;
  final Color color;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 20, height: 20,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Center(
          child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.color, required this.tooltip, required this.onTap});
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 31, height: 31,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
      ),
    );
  }
}

// ── Add to crate dialog ───────────────────────────────────────────────────────

class _AddToCrateDialog extends StatefulWidget {
  const _AddToCrateDialog({
    required this.trackTitle,
    required this.crates,
    required this.onAddToCrate,
    required this.onNewCrate,
  });
  final String trackTitle;
  final List<String> crates;
  final void Function(String name) onAddToCrate;
  final void Function(String name) onNewCrate;

  @override
  State<_AddToCrateDialog> createState() => _AddToCrateDialogState();
}

class _AddToCrateDialogState extends State<_AddToCrateDialog> {
  final _newCrateCtrl = TextEditingController();
  bool _creatingNew = false;

  @override
  void dispose() {
    _newCrateCtrl.dispose();
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
                const Text('Add to Crate', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 4),
            Text('"${widget.trackTitle}"', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
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
                  widget.onAddToCrate(name);
                  Navigator.of(context).pop();
                },
              )),
              const Divider(color: AppTheme.edge, height: 20),
            ],

            if (_creatingNew) ...[
              TextField(
                controller: _newCrateCtrl,
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
                      final name = _newCrateCtrl.text.trim();
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
