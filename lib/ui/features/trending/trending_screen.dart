import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/track.dart';
import '../../../providers/app_state.dart';

class TrendingScreen extends ConsumerStatefulWidget {
  const TrendingScreen({super.key});
  @override
  ConsumerState<TrendingScreen> createState() => _TrendingScreenState();
}

class _TrendingScreenState extends ConsumerState<TrendingScreen> {
  String _selectedGenre = 'All';
  String _selectedRegion = 'All';
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tracksAsync = ref.watch(trackStreamProvider);
    final allTracks = tracksAsync.value ?? const <Track>[];

    final genres = ['All', ...{for (final t in allTracks) if (t.genre.isNotEmpty) t.genre}.toList()..sort()];
    final regions = ['All', ...{for (final t in allTracks) if (t.leadRegion.isNotEmpty) t.leadRegion}.toList()..sort()];

    var filtered = allTracks.toList();
    if (_selectedGenre != 'All') filtered = filtered.where((t) => t.genre == _selectedGenre).toList();
    if (_selectedRegion != 'All') filtered = filtered.where((t) => t.leadRegion == _selectedRegion).toList();
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      filtered = filtered.where((t) => t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q)).toList();
    }
    filtered.sort((a, b) => b.trendScore.compareTo(a.trendScore));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.local_fire_department_rounded, color: AppTheme.amber, size: 24),
                      const SizedBox(width: 10),
                      Text('Trending', style: theme.textTheme.headlineSmall?.copyWith(color: AppTheme.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${filtered.length} tracks sorted by momentum score',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
              const Spacer(),
              _FilterChip(label: 'Genre', value: _selectedGenre, options: genres, onChanged: (v) => setState(() => _selectedGenre = v)),
              const SizedBox(width: 8),
              _FilterChip(label: 'Region', value: _selectedRegion, options: regions, onChanged: (v) => setState(() => _selectedRegion = v)),
              const SizedBox(width: 12),
              SizedBox(
                width: 180,
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Search...',
                    hintStyle: const TextStyle(color: AppTheme.textTertiary),
                    prefixIcon: const Icon(Icons.search_rounded, size: 16, color: AppTheme.textTertiary),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    filled: true,
                    fillColor: AppTheme.panelRaised,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.5))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.5))),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Grid
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No tracks match your filters', style: TextStyle(color: AppTheme.textTertiary)))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) => _TrackCard(track: filtered[i], rank: i + 1),
                ),
        ),
      ],
    );
  }
}

class _TrackCard extends StatefulWidget {
  final Track track;
  final int rank;
  const _TrackCard({required this.track, required this.rank});

  @override
  State<_TrackCard> createState() => _TrackCardState();
}

class _TrackCardState extends State<_TrackCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final score = (t.trendScore * 100).toInt();
    final isTop3 = widget.rank <= 3;
    final rankColor = widget.rank == 1 ? AppTheme.amber : widget.rank == 2 ? const Color(0xFFC0C0C0) : widget.rank == 3 ? const Color(0xFFCD7F32) : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _openTrack(t),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isTop3
                  ? rankColor!.withValues(alpha: _hovered ? 0.5 : 0.3)
                  : AppTheme.edge.withValues(alpha: _hovered ? 0.6 : 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                      child: SizedBox.expand(
                        child: t.artworkUrl.isNotEmpty
                            ? CachedNetworkImage(imageUrl: t.artworkUrl, fit: BoxFit.cover, errorWidget: (_, e, s) => _ArtPlaceholder())
                            : _ArtPlaceholder(),
                      ),
                    ),
                    // Rank badge
                    Positioned(
                      top: 8, left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: isTop3 ? rankColor!.withValues(alpha: 0.9) : Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('#${widget.rank}', style: TextStyle(color: Colors.white, fontWeight: isTop3 ? FontWeight.w800 : FontWeight.w700, fontSize: 10)),
                      ),
                    ),
                    // Score
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: AppTheme.cyan.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(6)),
                        child: Text('$score', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10)),
                      ),
                    ),
                    // Play hover
                    if (_hovered)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                          ),
                          child: Center(
                            child: Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: AppTheme.cyan, shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: AppTheme.cyan.withValues(alpha: 0.5), blurRadius: 16)],
                              ),
                              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(t.artist, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text('${t.bpm}', style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(color: AppTheme.edge.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(3)),
                          child: Text(t.keySignature, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 9, fontWeight: FontWeight.w600)),
                        ),
                        const Spacer(),
                        Text(t.genre, style: TextStyle(color: AppTheme.violet.withValues(alpha: 0.7), fontSize: 9)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppTheme.edge, AppTheme.panelRaised]),
      ),
      child: const Center(child: Icon(Icons.music_note_rounded, color: AppTheme.textTertiary, size: 32)),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  const _FilterChip({required this.label, required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised, borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: options.contains(value) ? value : options.first,
              isDense: true, dropdownColor: AppTheme.panelRaised,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
              items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
              onChanged: (v) { if (v != null) onChanged(v); },
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _openTrack(Track track) async {
  const priority = ['spotify', 'apple', 'youtube', 'deezer', 'soundcloud', 'audius'];
  String? url;
  for (final key in priority) {
    final u = track.platformLinks[key];
    if (u != null && u.isNotEmpty) { url = u; break; }
  }
  url ??= track.platformLinks.values.firstOrNull;
  if (url == null) return;
  final uri = Uri.tryParse(url);
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}
