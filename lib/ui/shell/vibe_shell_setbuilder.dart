part of 'vibe_shell.dart';

// ── Set slot model ────────────────────────────────────────────────────────────

enum _SortMode { all, trending, hottest, rising, greatestOf }

class _SetSlot {
  String genre;
  _SortMode mode;
  int count;
  String artist = ''; // comma-separated artist names
  String region = '';
  int? yearFrom;
  int? yearTo;
  int minBpm = 0;
  int maxBpm = 0;

  _SetSlot({
    this.genre = 'Afrobeats',
    this.mode = _SortMode.trending,
    this.count = 20,
  });

  String get modeLabel => switch (mode) {
    _SortMode.all => 'All Best',
    _SortMode.trending => 'Top Trending',
    _SortMode.hottest => 'Hottest',
    _SortMode.rising => 'Rising Fast',
    _SortMode.greatestOf => 'Greatest Of',
  };
}

// ── Set Builder View ──────────────────────────────────────────────────────────

class _SetBuilderView extends ConsumerStatefulWidget {
  const _SetBuilderView({
    required this.allTracks,
    required this.genres,
    required this.vibes,
    required this.session,
    required this.userProfile,
  });

  final List<Track> allTracks;
  final List<String> genres;
  final List<String> vibes;
  final SessionState session;
  final UserProfile userProfile;

  @override
  ConsumerState<_SetBuilderView> createState() => _SetBuilderViewState();
}

class _SetBuilderViewState extends ConsumerState<_SetBuilderView> {
  final _platformSearch = PlatformSearchService();
  final List<_SetSlot> _slots = [
    _SetSlot(genre: 'Afrobeats', mode: _SortMode.trending, count: 30),
    _SetSlot(genre: 'R&B', mode: _SortMode.hottest, count: 20),
    _SetSlot(genre: 'Hip-Hop', mode: _SortMode.trending, count: 20),
  ];
  List<AiCrateTrack> _platformTracks = const [];
  bool _searchingPlatforms = false;
  String _crateName = 'My Set';

  @override
  void initState() {
    super.initState();
    _regenerate();
  }

  @override
  Widget build(BuildContext context) {
    final totalRequested = _slots.fold<int>(0, (sum, s) => sum + s.count);

    return CustomScrollView(
      slivers: [
        // ── Header ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
            child: Row(
              children: [
                const Icon(
                  Icons.auto_fix_high_rounded,
                  color: AppTheme.amber,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Set Builder',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(color: AppTheme.textPrimary),
                    ),
                    Text(
                      '${_platformTracks.length} / $totalRequested tracks from Apple Music, Spotify & YouTube'
                      '${_searchingPlatforms ? ' · searching…' : ''}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  width: 150,
                  height: 36,
                  child: TextField(
                    onChanged: (v) => _crateName = v,
                    controller: TextEditingController(text: _crateName),
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Crate name…',
                      hintStyle: const TextStyle(color: AppTheme.textTertiary),
                      filled: true,
                      fillColor: AppTheme.panelRaised,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 0,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _regenerate,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Build Set'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _platformTracks.isEmpty ? null : _saveCrate,
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: const Text('Save Crate'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () {
                    ref
                        .read(workspaceControllerProvider.notifier)
                        .setSection(AppSection.aiCopilot);
                  },
                  icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: const Text('Ask AI'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.amber.withValues(alpha: 0.2),
                    foregroundColor: AppTheme.amber,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Slot table ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
            child: Column(
              children: [
                // Column headers
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: const [
                      SizedBox(width: 32),
                      _ColHeader('MODE', 110),
                      _ColHeader('GENRE', 120),
                      _ColHeader('ARTIST', 0, flex: true),
                      _ColHeader('REGION', 70),
                      _ColHeader('YEARS', 110),
                      _ColHeader('BPM', 110),
                      _ColHeader('TRACKS', 100),
                      SizedBox(width: 32),
                    ],
                  ),
                ),
                // Slot rows
                for (var i = 0; i < _slots.length; i++) _buildSlotRow(i),
                // Add slot button
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => setState(() => _slots.add(_SetSlot())),
                        icon: const Icon(
                          Icons.add_circle_rounded,
                          size: 18,
                          color: AppTheme.cyan,
                        ),
                        label: const Text(
                          'Add Slot',
                          style: TextStyle(
                            color: AppTheme.cyan,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '$totalRequested tracks total',
                        style: const TextStyle(
                          color: AppTheme.amber,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 20)),

        // ── Generated grid (from platforms) ──
        if (_platformTracks.isEmpty && !_searchingPlatforms)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.library_music_rounded,
                    color: AppTheme.textTertiary.withValues(alpha: 0.4),
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Configure your slots and hit Build Set',
                    style: TextStyle(color: AppTheme.textTertiary),
                  ),
                ],
              ),
            ),
          )
        else if (_searchingPlatforms && _platformTracks.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: AppTheme.cyan,
                    strokeWidth: 2,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Searching Apple Music, Spotify & YouTube…',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                childAspectRatio: 0.72,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate((context, i) {
                final t = _platformTracks[i];
                return _PlatformResultCard(track: t, index: i);
              }, childCount: _platformTracks.length),
            ),
          ),
      ],
    );
  }

  Widget _buildSlotRow(int index) {
    final slot = _slots[index];
    final genreOptions = {
      'All',
      'Afrobeats',
      'Amapiano',
      'Hip-Hop',
      'R&B',
      'House',
      'Dancehall',
      'Pop',
      'Latin',
      'Drill',
      'Dance',
      'UK Garage',
      ...widget.genres.where((g) => g != 'All'),
    }.toList();
    final regionOptions = ['All', 'GH', 'NG', 'ZA', 'GB', 'US', 'DE'];

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          // Slot badge
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.violet, AppTheme.cyan],
              ),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Mode
          SizedBox(
            width: 110,
            child: _pill(
              child: DropdownButton<_SortMode>(
                value: slot.mode,
                dropdownColor: AppTheme.panelRaised,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                ),
                underline: const SizedBox(),
                isDense: true,
                isExpanded: true,
                items: _SortMode.values
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(switch (m) {
                          _SortMode.all => 'All Best',
                          _SortMode.trending => 'Trending',
                          _SortMode.hottest => 'Hottest',
                          _SortMode.rising => 'Rising',
                          _SortMode.greatestOf => 'Greatest',
                        }, style: const TextStyle(fontSize: 12)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => slot.mode = v);
                },
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Genre
          SizedBox(
            width: 120,
            child: _pill(
              child: DropdownButton<String>(
                value: genreOptions.contains(slot.genre) ? slot.genre : 'All',
                dropdownColor: AppTheme.panelRaised,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                ),
                underline: const SizedBox(),
                isDense: true,
                isExpanded: true,
                items: genreOptions
                    .map(
                      (g) => DropdownMenuItem(
                        value: g,
                        child: Text(g, style: const TextStyle(fontSize: 12)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => slot.genre = v);
                },
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Artist
          Expanded(
            child: SizedBox(
              height: 32,
              child: TextField(
                onChanged: (v) => slot.artist = v.trim(),
                controller: TextEditingController(text: slot.artist),
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                ),
                decoration: InputDecoration(
                  hintText: 'Drake, Wizkid…',
                  hintStyle: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 11,
                  ),
                  filled: true,
                  fillColor: AppTheme.panelRaised,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 0,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Region
          SizedBox(
            width: 70,
            child: _pill(
              child: DropdownButton<String>(
                value: regionOptions.contains(slot.region)
                    ? slot.region
                    : 'All',
                dropdownColor: AppTheme.panelRaised,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                ),
                underline: const SizedBox(),
                isDense: true,
                isExpanded: true,
                items: regionOptions
                    .map(
                      (r) => DropdownMenuItem(
                        value: r,
                        child: Text(r, style: const TextStyle(fontSize: 12)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => slot.region = v);
                },
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Year From-To
          SizedBox(
            width: 110,
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      onChanged: (v) => slot.yearFrom = int.tryParse(v),
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                      ),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'From',
                        hintStyle: const TextStyle(
                          color: AppTheme.textTertiary,
                          fontSize: 10,
                        ),
                        filled: true,
                        fillColor: AppTheme.panelRaised,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 0,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    '–',
                    style: TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      onChanged: (v) => slot.yearTo = int.tryParse(v),
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                      ),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'To',
                        hintStyle: const TextStyle(
                          color: AppTheme.textTertiary,
                          fontSize: 10,
                        ),
                        filled: true,
                        fillColor: AppTheme.panelRaised,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 0,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // BPM range
          SizedBox(
            width: 110,
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      onChanged: (v) => slot.minBpm = int.tryParse(v) ?? 60,
                      controller: TextEditingController(
                        text: slot.minBpm == 60 ? '' : '${slot.minBpm}',
                      ),
                      style: const TextStyle(
                        color: AppTheme.amber,
                        fontSize: 12,
                      ),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: '60',
                        hintStyle: const TextStyle(
                          color: AppTheme.textTertiary,
                          fontSize: 10,
                        ),
                        filled: true,
                        fillColor: AppTheme.panelRaised,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 0,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    '–',
                    style: TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      onChanged: (v) => slot.maxBpm = int.tryParse(v) ?? 200,
                      controller: TextEditingController(
                        text: slot.maxBpm == 200 ? '' : '${slot.maxBpm}',
                      ),
                      style: const TextStyle(
                        color: AppTheme.amber,
                        fontSize: 12,
                      ),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: '200',
                        hintStyle: const TextStyle(
                          color: AppTheme.textTertiary,
                          fontSize: 10,
                        ),
                        filled: true,
                        fillColor: AppTheme.panelRaised,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 0,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // Track count
          SizedBox(
            width: 100,
            child: Row(
              children: [
                Text(
                  '${slot.count}',
                  style: const TextStyle(
                    color: AppTheme.amber,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Expanded(
                  child: Slider(
                    min: 5,
                    max: 500,
                    divisions: 99,
                    value: slot.count.toDouble(),
                    onChanged: (v) => setState(() => slot.count = v.round()),
                  ),
                ),
              ],
            ),
          ),
          // Remove
          if (_slots.length > 1)
            IconButton(
              icon: const Icon(
                Icons.close_rounded,
                size: 16,
                color: AppTheme.textTertiary,
              ),
              onPressed: () => setState(() => _slots.removeAt(index)),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            )
          else
            const SizedBox(width: 24),
        ],
      ),
    );
  }

  Widget _pill({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }

  void _regenerate() {
    // Go straight to platforms — don't use Firestore
    setState(() {
      _platformTracks = [];
      _searchingPlatforms = true;
    });
    unawaited(_buildFromPlatforms());
  }

  Future<void> _buildFromPlatforms() async {
    final allFound = <AiCrateTrack>[];
    final seen = <String>{};

    for (final slot in _slots) {
      final genre = slot.genre == 'All' ? 'music' : slot.genre;
      final modeHint = switch (slot.mode) {
        _SortMode.all => 'best top popular',
        _SortMode.trending => 'trending',
        _SortMode.hottest => 'hot new',
        _SortMode.rising => 'new rising',
        _SortMode.greatestOf => 'best greatest',
      };
      // Build BPM hint for search query when range is narrowed
      final bpmHint = (slot.minBpm > 60 || slot.maxBpm < 200)
          ? '${slot.minBpm}-${slot.maxBpm} bpm'
          : '';

      try {
        List<PlatformTrackResult> results;

        if (slot.artist.isNotEmpty) {
          results = await _platformSearch.searchByArtist(
            '${slot.artist} $bpmHint'.trim(),
            limit: slot.count + 50,
          );
        } else if (slot.mode == _SortMode.all) {
          // "All Best" mode: run multiple search strategies for maximum coverage
          final yearHint = slot.yearFrom != null ? '${slot.yearFrom}s' : null;
          final allResults = <PlatformTrackResult>[];
          final allSeen = <String>{};
          for (final hint in [
            'best top popular',
            'trending hit',
            'classic essential',
            'new hot',
            'playlist',
          ]) {
            final batch = await _platformSearch.searchByGenre(
              '$hint $genre $bpmHint'.trim(),
              limit: (slot.count ~/ 3).clamp(20, 200),
              era: yearHint,
            );
            for (final r in batch) {
              final k = '${r.title.toLowerCase()}::${r.artist.toLowerCase()}';
              if (allSeen.add(k)) allResults.add(r);
            }
            if (allResults.length >= slot.count + 50) break;
          }
          results = allResults;
        } else {
          final yearHint = slot.yearFrom != null ? '${slot.yearFrom}s' : null;
          results = await _platformSearch.searchByGenre(
            '$modeHint $genre $bpmHint'.trim(),
            limit: slot.count + 50,
            era: yearHint,
          );
        }

        int added = 0;
        for (final r in results) {
          if (added >= slot.count) break;
          final key = '${r.title.toLowerCase()}::${r.artist.toLowerCase()}';
          if (seen.contains(key)) continue;
          seen.add(key);

          allFound.add(
            AiCrateTrack(
              title: r.title,
              artist: r.artist,
              artworkUrl: r.artworkUrl,
              spotifyUrl: r.spotifyUrl,
              appleUrl: r.appleUrl,
              resolved: r.hasUrl,
            ),
          );
          added++;
        }
      } catch (e, st) {
        developer.log(
          'Platform search slot failed',
          name: 'VibeShell',
          error: e,
          stackTrace: st,
        );
      }

      // Update UI after each slot completes
      if (mounted) {
        setState(() => _platformTracks = [...allFound]);
      }
    }

    if (mounted) {
      setState(() => _searchingPlatforms = false);
    }
  }

  Future<void> _saveCrate() async {
    if (_platformTracks.isEmpty) return;
    final name = _crateName.trim().isEmpty ? 'My Set' : _crateName.trim();

    // Save as AI crate (with play URLs)
    ref.read(aiCrateProvider.notifier).setCrate(name, _platformTracks);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Crate saved to your workspace.')),
      );
    }
  }
}

class _ColHeader extends StatelessWidget {
  const _ColHeader(this.label, this.width, {this.flex = false});
  final String label;
  final double width;
  final bool flex;

  @override
  Widget build(BuildContext context) {
    final child = Text(
      label,
      style: const TextStyle(
        color: AppTheme.textTertiary,
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
    if (flex) return Expanded(child: child);
    return SizedBox(width: width, child: child);
  }
}
