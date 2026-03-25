import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/track.dart';
import '../../../providers/app_state.dart';

/// Aggregated artist derived from real track data.
class _ArtistInfo {
  final String name;
  final String topGenre;
  final String topRegion;
  final double avgTrendScore;
  final int trackCount;
  final String? artworkUrl;
  final String? spotifyUrl;
  final List<Track> tracks;

  const _ArtistInfo({
    required this.name,
    required this.topGenre,
    required this.topRegion,
    required this.avgTrendScore,
    required this.trackCount,
    required this.artworkUrl,
    required this.spotifyUrl,
    required this.tracks,
  });
}

class ArtistsScreen extends ConsumerStatefulWidget {
  const ArtistsScreen({super.key});

  @override
  ConsumerState<ArtistsScreen> createState() => _ArtistsScreenState();
}

class _ArtistsScreenState extends ConsumerState<ArtistsScreen> {
  String _search = '';
  String? _selectedArtist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tracksAsync = ref.watch(trackStreamProvider);
    final allTracks = tracksAsync.value ?? const <Track>[];

    // Aggregate artists from real track data
    final artistMap = <String, List<Track>>{};
    for (final track in allTracks) {
      final name = track.artist.trim();
      if (name.isEmpty) continue;
      artistMap.putIfAbsent(name, () => []).add(track);
    }

    var artists = artistMap.entries.map((entry) {
      final tracks = entry.value;
      final genreCounts = <String, int>{};
      final regionCounts = <String, int>{};
      for (final t in tracks) {
        genreCounts[t.genre] = (genreCounts[t.genre] ?? 0) + 1;
        genreCounts[t.leadRegion] = (regionCounts[t.leadRegion] ?? 0) + 1;
      }
      final topGenre = genreCounts.entries.isNotEmpty
          ? (genreCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key
          : 'Open Format';
      final topRegion = tracks.first.leadRegion;
      final avgScore = tracks.map((t) => t.trendScore).reduce((a, b) => a + b) / tracks.length;
      final bestTrack = tracks.reduce((a, b) => a.trendScore > b.trendScore ? a : b);

      return _ArtistInfo(
        name: entry.key,
        topGenre: topGenre,
        topRegion: topRegion,
        avgTrendScore: avgScore,
        trackCount: tracks.length,
        artworkUrl: bestTrack.artworkUrl.isNotEmpty ? bestTrack.artworkUrl : null,
        spotifyUrl: bestTrack.platformLinks['spotify'],
        tracks: tracks,
      );
    }).toList();

    // Sort by avg trend score descending
    artists.sort((a, b) => b.avgTrendScore.compareTo(a.avgTrendScore));

    // Filter by search
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      artists = artists.where((a) =>
        a.name.toLowerCase().contains(q) ||
        a.topGenre.toLowerCase().contains(q) ||
        a.topRegion.toLowerCase().contains(q)
      ).toList();
    }

    final selected = _selectedArtist != null
        ? artists.where((a) => a.name == _selectedArtist).firstOrNull
        : null;

    return Row(
      children: [
        // Artist grid
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Artists', style: theme.textTheme.headlineSmall?.copyWith(color: AppTheme.textPrimary)),
                        const SizedBox(height: 4),
                        Text(
                          '${artists.length} artists from ${allTracks.length} tracks',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 240,
                      child: TextField(
                        onChanged: (v) => setState(() => _search = v),
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Search artists...',
                          hintStyle: const TextStyle(color: AppTheme.textTertiary),
                          prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppTheme.textTertiary),
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          isDense: true,
                          filled: true,
                          fillColor: AppTheme.panelRaised,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.5)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.5)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: artists.isEmpty
                    ? const Center(
                        child: Text('No artists found', style: TextStyle(color: AppTheme.textTertiary)),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          childAspectRatio: 0.82,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: artists.length,
                        itemBuilder: (context, i) => _ArtistCard(
                          artist: artists[i],
                          isSelected: artists[i].name == _selectedArtist,
                          onTap: () => setState(() {
                            _selectedArtist = _selectedArtist == artists[i].name ? null : artists[i].name;
                          }),
                        ),
                      ),
              ),
            ],
          ),
        ),
        // Detail panel
        if (selected != null)
          SizedBox(
            width: 340,
            child: _ArtistDetailPanel(artist: selected),
          ),
      ],
    );
  }
}

class _ArtistCard extends StatefulWidget {
  final _ArtistInfo artist;
  final bool isSelected;
  final VoidCallback onTap;

  const _ArtistCard({
    required this.artist,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_ArtistCard> createState() => _ArtistCardState();
}

class _ArtistCardState extends State<_ArtistCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.artist;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? AppTheme.violet.withValues(alpha: 0.1)
                : _hovered
                    ? AppTheme.panelRaised
                    : AppTheme.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.isSelected
                  ? AppTheme.violet.withValues(alpha: 0.4)
                  : AppTheme.edge.withValues(alpha: 0.4),
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Artist image
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(40),
                  child: a.artworkUrl != null
                      ? CachedNetworkImage(
                          imageUrl: a.artworkUrl!,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          placeholder: (_, p) => _AvatarFallback(name: a.name),
                          errorWidget: (_, e1, e2) => _AvatarFallback(name: a.name),
                        )
                      : _AvatarFallback(name: a.name),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                a.name,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                a.topGenre,
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.edge.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      a.topRegion,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 9, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${a.trackCount} track${a.trackCount > 1 ? 's' : ''}',
                    style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10),
                  ),
                  const Spacer(),
                  Text(
                    '${(a.avgTrendScore * 100).toInt()}',
                    style: const TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  final String name;
  const _AvatarFallback({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.violet.withValues(alpha: 0.3),
            AppTheme.pink.withValues(alpha: 0.2),
          ],
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(color: AppTheme.violet, fontSize: 24, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _ArtistDetailPanel extends StatelessWidget {
  final _ArtistInfo artist;
  const _ArtistDetailPanel({required this.artist});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(48),
                  child: artist.artworkUrl != null
                      ? CachedNetworkImage(
                          imageUrl: artist.artworkUrl!,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorWidget: (_, e1, e2) => _AvatarFallback(name: artist.name),
                        )
                      : _AvatarFallback(name: artist.name),
                ),
                const SizedBox(height: 14),
                Text(
                  artist.name,
                  style: theme.textTheme.titleLarge?.copyWith(color: AppTheme.textPrimary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  '${artist.topGenre}  ·  ${artist.topRegion}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _StatChip(label: 'Tracks', value: '${artist.trackCount}', color: AppTheme.cyan),
                    const SizedBox(width: 10),
                    _StatChip(label: 'Score', value: '${(artist.avgTrendScore * 100).toInt()}', color: AppTheme.violet),
                  ],
                ),
                if (artist.spotifyUrl != null) ...[
                  const SizedBox(height: 12),
                  Material(
                    color: const Color(0xFF1DB954).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () async {
                        final uri = Uri.tryParse(artist.spotifyUrl!);
                        if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(
                          'Open in Spotify',
                          style: TextStyle(color: Color(0xFF1DB954), fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(color: AppTheme.edge.withValues(alpha: 0.4), height: 1),
          // Tracks list
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'TRACKS',
                style: TextStyle(
                  color: AppTheme.sectionHeader,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              itemCount: artist.tracks.length,
              itemBuilder: (context, i) {
                final track = artist.tracks[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.panelRaised,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      if (track.artworkUrl.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: CachedNetworkImage(
                            imageUrl: track.artworkUrl,
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
                            color: AppTheme.edge,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.music_note, size: 16, color: AppTheme.textTertiary),
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${track.bpm} BPM  ·  ${track.keySignature}',
                              style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${(track.trendScore * 100).toInt()}',
                        style: const TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
        ],
      ),
    );
  }
}
