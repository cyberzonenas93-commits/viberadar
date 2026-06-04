part of 'for_you_screen.dart';

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyForYou extends StatelessWidget {
  const _EmptyForYou({required this.onAddArtists});
  final VoidCallback onAddArtists;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppTheme.violet.withValues(alpha: 0.2),
                  AppTheme.cyan.withValues(alpha: 0.1),
                ],
              ),
              border: Border.all(
                color: AppTheme.violet.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                colors: [AppTheme.violet, AppTheme.cyan],
              ).createShader(b),
              child: const Icon(
                Icons.favorite_rounded,
                size: 40,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Your personal feed',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Follow artists to see their latest releases,\ntop tracks, and personalized recommendations.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: onAddArtists,
            icon: const Icon(Icons.add_rounded),
            label: const Text(
              'Follow Artists',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.violet,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Artist picker dialog ──────────────────────────────────────────────────────

class _ArtistPickerDialog extends StatefulWidget {
  const _ArtistPickerDialog({
    required this.initialFollowed,
    required this.onSave,
  });
  final List<String> initialFollowed;
  final void Function(List<String> selected) onSave;

  @override
  State<_ArtistPickerDialog> createState() => _ArtistPickerDialogState();
}

class _ArtistPickerDialogState extends State<_ArtistPickerDialog> {
  final _searchCtrl = TextEditingController();
  final _spotify = SpotifyArtistService();
  late final Set<String> _selected;
  List<SpotifyArtistResult> _searchResults = [];
  bool _searching = false;
  Timer? _debounce;
  // Cached images for popular artists
  final Map<String, String?> _popularImages = {};

  // Popular artists to show by default
  static const _popular = [
    'Drake',
    'Kendrick Lamar',
    'Bad Bunny',
    'The Weeknd',
    'Taylor Swift',
    'Asake',
    'Wizkid',
    'Burna Boy',
    'Davido',
    'Fireboy DML',
    'Rema',
    'Tems',
    'Ayra Starr',
    'Ckay',
    'Beyoncé',
    'SZA',
    'Doja Cat',
    'Cardi B',
    'Nicki Minaj',
    'Travis Scott',
    'Future',
    'Lil Baby',
    'Gunna',
    'J. Cole',
    'Nas',
    'Jay-Z',
    'Kanye West',
    'Tyler the Creator',
    'Frank Ocean',
    'Bryson Tiller',
    'H.E.R.',
    'Jhené Aiko',
    'Summer Walker',
    'Chris Brown',
    'Usher',
    'Brent Faiyaz',
    'PartyNextDoor',
    'Headie One',
    'Central Cee',
    'Dave',
    'Stormzy',
    'AJ Tracey',
    'Fivio Foreign',
    'Lil Durk',
    'Rod Wave',
    'Morgan Wallen',
    'Luke Combs',
    'Zach Bryan',
    'Peso Pluma',
    'Feid',
    'J Balvin',
    'Maluma',
    'Daddy Yankee',
    'Farruko',
    'Ozuna',
  ];

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.initialFollowed);
    unawaited(_loadPopularImages());
  }

  /// Load images for popular artists in batches via Spotify search.
  Future<void> _loadPopularImages() async {
    // Search in batches of 5 to avoid rate limits
    for (var i = 0; i < _popular.length; i += 5) {
      final batch = _popular.skip(i).take(5);
      await Future.wait(
        batch.map((name) async {
          try {
            final results = await _spotify.searchArtistsByName(name);
            if (results.isNotEmpty && mounted) {
              setState(() => _popularImages[name] = results.first.imageUrl);
            }
          } catch (e, st) {
            developer.log(
              'Failed to fetch image for popular artist $name',
              name: 'ForYou',
              error: e,
              stackTrace: st,
            );
          }
        }),
      );
      if (!mounted) return;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.length < 2) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      try {
        final results = await _spotify.searchArtistsByName(query);
        if (mounted) {
          setState(() {
            _searchResults = results;
            _searching = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showSearch = _searchCtrl.text.length >= 2;
    final displayItems = showSearch
        ? _searchResults.map((r) => r.name).toList()
        : _popular;

    return Dialog(
      backgroundColor: AppTheme.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SizedBox(
          width: 620,
          height: 600,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Follow Artists',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Pick artists you love. We'll build your personal feed around them.",
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Search field
                    TextField(
                      controller: _searchCtrl,
                      onChanged: _onSearchChanged,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search any artist...',
                        hintStyle: const TextStyle(
                          color: AppTheme.textTertiary,
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: AppTheme.textTertiary,
                          size: 18,
                        ),
                        suffixIcon: _searching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.violet,
                                  ),
                                ),
                              )
                            : null,
                        filled: true,
                        fillColor: AppTheme.panelRaised,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.edge),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.edge),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppTheme.violet,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Selected chips
              if (_selected.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _selected
                        .take(8)
                        .map(
                          (name) => GestureDetector(
                            onTap: () => setState(() => _selected.remove(name)),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.violet.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: AppTheme.violet.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      color: AppTheme.violet,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.close_rounded,
                                    color: AppTheme.violet,
                                    size: 12,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              const SizedBox(height: 8),
              Divider(color: AppTheme.edge.withValues(alpha: 0.4), height: 1),
              // Grid
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(20),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 140,
                    childAspectRatio: 0.85,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: displayItems.length,
                  itemBuilder: (context, i) {
                    final name = displayItems[i];
                    final imageUrl = showSearch
                        ? _searchResults[i].imageUrl
                        : _popularImages[name];
                    final isSelected = _selected.contains(name);
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (isSelected) {
                          _selected.remove(name);
                        } else {
                          _selected.add(name);
                        }
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.violet.withValues(alpha: 0.15)
                              : AppTheme.panelRaised,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.violet
                                : AppTheme.edge.withValues(alpha: 0.5),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(30),
                                  child: imageUrl != null
                                      ? CachedNetworkImage(
                                          imageUrl: imageUrl,
                                          width: 56,
                                          height: 56,
                                          fit: BoxFit.cover,
                                        )
                                      : Container(
                                          width: 56,
                                          height: 56,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: LinearGradient(
                                              colors: [
                                                AppTheme.violet.withValues(
                                                  alpha: 0.3,
                                                ),
                                                AppTheme.cyan.withValues(
                                                  alpha: 0.2,
                                                ),
                                              ],
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(
                                              name.isNotEmpty
                                                  ? name[0].toUpperCase()
                                                  : '?',
                                              style: const TextStyle(
                                                color: AppTheme.textPrimary,
                                                fontSize: 22,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ),
                                ),
                                if (isSelected)
                                  Container(
                                    width: 18,
                                    height: 18,
                                    decoration: const BoxDecoration(
                                      color: AppTheme.violet,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 12,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: Text(
                                name,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isSelected
                                      ? AppTheme.violet
                                      : AppTheme.textPrimary,
                                  fontSize: 11,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Footer
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                child: Row(
                  children: [
                    Text(
                      '${_selected.length} selected',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: AppTheme.textTertiary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _selected.isEmpty
                          ? null
                          : () {
                              widget.onSave(_selected.toList());
                              Navigator.pop(context);
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.violet,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Save',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
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
