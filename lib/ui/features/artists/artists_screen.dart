import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/artist.dart';
import '../../../providers/artists_provider.dart';

const _genreFilters = ['All', 'Afrobeats', 'Amapiano', 'R&B', 'Hip-Hop', 'House', 'Electronic'];

const _countryFlags = {
  'NG': '🇳🇬',
  'ZA': '🇿🇦',
  'US': '🇺🇸',
  'CA': '🇨🇦',
  'GB': '🇬🇧',
};

String _flagFor(String country) => _countryFlags[country] ?? '🌍';

String _formatListeners(int n) {
  if (n >= 1000000) {
    final m = n / 1000000;
    final s = m.toStringAsFixed(1);
    return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}M';
  }
  if (n >= 1000) {
    final k = n / 1000;
    final s = k.toStringAsFixed(1);
    return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}K';
  }
  return n.toString();
}

// ---------------------------------------------------------------------------
// Top-level screen
// ---------------------------------------------------------------------------

class ArtistsScreen extends ConsumerStatefulWidget {
  const ArtistsScreen({super.key});

  @override
  ConsumerState<ArtistsScreen> createState() => _ArtistsScreenState();
}

class _ArtistsScreenState extends ConsumerState<ArtistsScreen> {
  final _searchController = TextEditingController();
  String _activeGenre = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Artist> _applyGenreFilter(List<Artist> artists) {
    if (_activeGenre == 'All') return artists;
    return artists
        .where((a) => a.genres.any(
              (g) => g.toLowerCase().contains(_activeGenre.toLowerCase()),
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final allFiltered = ref.watch(filteredArtistsProvider);
    final displayed = _applyGenreFilter(allFiltered);
    final selectedId = ref.watch(selectedArtistIdProvider);
    final repo = ref.watch(artistRepositoryProvider);
    final selectedArtist = selectedId != null ? repo.findById(selectedId) : null;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Toolbar(searchController: _searchController),
              const SizedBox(height: 16),
              _GenreFilterRow(
                active: _activeGenre,
                onTap: (g) => setState(() => _activeGenre = g),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _ArtistGrid(artists: displayed),
              ),
            ],
          ),
        ),
        if (selectedArtist != null) ...[
          const SizedBox(width: 16),
          _ArtistDetailPanel(artist: selectedArtist),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Toolbar
// ---------------------------------------------------------------------------

class _Toolbar extends ConsumerWidget {
  const _Toolbar({required this.searchController});

  final TextEditingController searchController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
      child: Row(
        children: [
          Text(
            'Artists',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const Spacer(),
          SizedBox(
            width: 280,
            child: TextField(
              controller: searchController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              onChanged: (v) =>
                  ref.read(artistSearchQueryProvider.notifier).state = v,
              decoration: InputDecoration(
                hintText: 'Search artists…',
                hintStyle: const TextStyle(color: Color(0xFF5C6380), fontSize: 14),
                prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF5C6380)),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                isDense: true,
                filled: true,
                fillColor: AppTheme.panel,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.edge),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.edge),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.violet),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Genre filter pills
// ---------------------------------------------------------------------------

class _GenreFilterRow extends StatelessWidget {
  const _GenreFilterRow({required this.active, required this.onTap});

  final String active;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _genreFilters.map((g) {
          final isActive = g == active;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onTap(g),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive ? AppTheme.violet : AppTheme.panel,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isActive ? AppTheme.violet : AppTheme.edge,
                  ),
                ),
                child: Text(
                  g,
                  style: TextStyle(
                    color: isActive ? Colors.white : const Color(0xFF9099B8),
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Artist grid
// ---------------------------------------------------------------------------

class _ArtistGrid extends StatelessWidget {
  const _ArtistGrid({required this.artists});

  final List<Artist> artists;

  @override
  Widget build(BuildContext context) {
    if (artists.isEmpty) {
      return const Center(
        child: Text(
          'No artists found',
          style: TextStyle(color: Color(0xFF5C6380), fontSize: 14),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 28),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240,
        childAspectRatio: 0.82,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: artists.length,
      itemBuilder: (context, i) => _ArtistCard(artist: artists[i]),
    );
  }
}

// ---------------------------------------------------------------------------
// Artist card
// ---------------------------------------------------------------------------

class _ArtistCard extends ConsumerWidget {
  const _ArtistCard({required this.artist});

  final Artist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.edge),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Avatar header ──────────────────────────────────────────────
          Expanded(
            flex: 5,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Gradient background
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppTheme.violet, AppTheme.ink],
                    ),
                  ),
                ),
                // Network image overlay
                Image.network(
                  artist.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  loadingBuilder: (_, child, progress) =>
                      progress == null ? child : const SizedBox.shrink(),
                ),
                // Initials fallback (shown behind image via stack order)
                Center(
                  child: Text(
                    artist.initials,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                // Verified badge
                if (artist.verified)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppTheme.ink,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.verified_rounded,
                        color: AppTheme.cyan,
                        size: 14,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Info section ───────────────────────────────────────────────
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    artist.genres.join(' · '),
                    style: const TextStyle(color: Color(0xFF9099B8), fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_formatListeners(artist.monthlyListeners)} listeners',
                    style: const TextStyle(color: Color(0xFF9099B8), fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  // Trend score bar
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: artist.trendScore,
                            minHeight: 5,
                            backgroundColor: AppTheme.edge,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                AppTheme.violet),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(artist.trendScore * 100).round()}',
                        style: const TextStyle(
                          color: AppTheme.violet,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // View profile button
                  SizedBox(
                    width: double.infinity,
                    height: 32,
                    child: OutlinedButton(
                      onPressed: () => ref
                          .read(selectedArtistIdProvider.notifier)
                          .state = artist.id,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.violet,
                        side: const BorderSide(color: AppTheme.violet),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'View Profile',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Artist detail panel (300 px wide)
// ---------------------------------------------------------------------------

class _ArtistDetailPanel extends ConsumerWidget {
  const _ArtistDetailPanel({required this.artist});

  final Artist artist;

  // Placeholder top tracks
  static const _trackNames = [
    'City Boys',
    'Love Damini',
    'Last Last',
    'Kilometre',
    'Alone',
  ];
  static const _bpms = [102, 98, 106, 112, 95];
  static const _keys = ['Gm', 'F#m', 'Dm', 'Am', 'Cm'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.edge),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────
          Stack(
            children: [
              // Gradient header
              Container(
                height: 140,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppTheme.violet, Color(0xFF2A1B5E)],
                  ),
                ),
              ),
              // Image
              SizedBox(
                height: 140,
                width: double.infinity,
                child: Image.network(
                  artist.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  loadingBuilder: (_, child, progress) =>
                      progress == null ? child : const SizedBox.shrink(),
                ),
              ),
              // Initials
              SizedBox(
                height: 140,
                child: Center(
                  child: Text(
                    artist.initials,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 56,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              // Close button
              Positioned(
                top: 10,
                right: 10,
                child: GestureDetector(
                  onTap: () =>
                      ref.read(selectedArtistIdProvider.notifier).state = null,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Color(0xCC080914),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 16),
                  ),
                ),
              ),
            ],
          ),

          // ── Scrollable body ───────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + verified + flag
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          artist.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      if (artist.verified)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(Icons.verified_rounded,
                              color: AppTheme.cyan, size: 18),
                        ),
                      const SizedBox(width: 8),
                      Text(
                        _flagFor(artist.country),
                        style: const TextStyle(fontSize: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Genre chips
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: artist.genres
                        .map(
                          (g) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.violet.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: AppTheme.violet.withOpacity(0.4)),
                            ),
                            child: Text(
                              g,
                              style: const TextStyle(
                                color: AppTheme.violet,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 14),

                  // Stats row
                  Row(
                    children: [
                      _StatBox(
                        label: 'Monthly',
                        value: _formatListeners(artist.monthlyListeners),
                      ),
                      const SizedBox(width: 10),
                      _StatBox(
                        label: 'Trend',
                        value: '${(artist.trendScore * 100).round()}',
                        valueColor: AppTheme.violet,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Bio
                  Text(
                    artist.bio,
                    style: const TextStyle(
                      color: Color(0xFF9099B8),
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Top Tracks
                  const Text(
                    'Top Tracks',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...List.generate(
                    5,
                    (i) => _TrackRow(
                      index: i + 1,
                      name: _trackNames[i],
                      bpm: _bpms[i],
                      key: _keys[i],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Follow button
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.violet,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                      label: const Text(
                        'Follow Artist',
                        style:
                            TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.panelRaised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.edge),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Color(0xFF9099B8), fontSize: 10),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.index,
    required this.name,
    required this.bpm,
    required this.key,
  });

  final int index;
  final String name;
  final int bpm;
  final String key;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.edge),
      ),
      child: Row(
        children: [
          Text(
            '$index',
            style: const TextStyle(
                color: Color(0xFF5C6380), fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${bpm} BPM',
            style: const TextStyle(color: Color(0xFF9099B8), fontSize: 10),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.edge,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              key,
              style: const TextStyle(
                  color: AppTheme.cyan, fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
