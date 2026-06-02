part of 'vibe_shell.dart';

class _RegionsView extends StatefulWidget {
  const _RegionsView({
    required this.tracks,
    required this.activeRegion,
    required this.ref,
    required this.onSelectRegion,
    required this.onOpenRegionWorkbench,
    required this.onActivateTrack,
  });

  final List<Track> tracks;
  final String activeRegion;
  final WidgetRef ref;
  final ValueChanged<String> onSelectRegion;
  final ValueChanged<String> onOpenRegionWorkbench;
  final ValueChanged<String> onActivateTrack;

  @override
  State<_RegionsView> createState() => _RegionsViewState();
}

class _RegionsViewState extends State<_RegionsView> {
  String _selectedGenre = 'All';

  @override
  Widget build(BuildContext context) {
    // Build genre list from tracks
    final genreSet = <String>{};
    for (final t in widget.tracks) {
      if (t.genre.isNotEmpty) genreSet.add(t.genre);
    }
    final genres = ['All', ...genreSet.toList()..sort()];

    // Apply genre filter
    final tracks = _selectedGenre == 'All'
        ? widget.tracks
        : widget.tracks.where((t) => t.genre == _selectedGenre).toList();

    final regionStats = <String, double>{};
    for (final track in tracks) {
      for (final entry in track.regionScores.entries) {
        regionStats.update(
          entry.key,
          (value) => value + entry.value,
          ifAbsent: () => entry.value,
        );
      }
    }

    final regions = regionStats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final fallbackRegion = regions.firstOrNull?.key ?? 'Global';
    final selectedRegion = widget.activeRegion == 'Global'
        ? fallbackRegion
        : widget.activeRegion;
    final focusedTracks = [...tracks]
      ..sort(
        (a, b) => regionScoreForTrack(
          b,
          selectedRegion,
        ).compareTo(regionScoreForTrack(a, selectedRegion)),
      );
    final regionalLeaders = focusedTracks
        .where((track) => regionScoreForTrack(track, selectedRegion) > 0)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                      const Icon(
                        Icons.public_rounded,
                        color: AppTheme.pink,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Regional Pulse',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(color: AppTheme.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${regionalLeaders.length} tracks in ${formatRegionLabel(selectedRegion)}${_selectedGenre != 'All' ? ' · $_selectedGenre' : ''}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Genre filter dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppTheme.panelRaised,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.edge.withValues(alpha: 0.5),
                  ),
                ),
                child: DropdownButton<String>(
                  value: genres.contains(_selectedGenre)
                      ? _selectedGenre
                      : 'All',
                  dropdownColor: AppTheme.panelRaised,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                  ),
                  underline: const SizedBox(),
                  isDense: true,
                  items: genres
                      .map(
                        (g) => DropdownMenuItem(
                          value: g,
                          child: Text(g, style: const TextStyle(fontSize: 12)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedGenre = v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: () => widget.onOpenRegionWorkbench(selectedRegion),
                icon: const Icon(Icons.table_rows_rounded, size: 16),
                label: const Text('Open in table'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Region selector chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: regions.take(12).map((entry) {
                final selected = entry.key == selectedRegion;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    selected: selected,
                    label: Text(entry.key),
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                    backgroundColor: AppTheme.panel,
                    selectedColor: AppTheme.cyan.withValues(alpha: 0.25),
                    side: BorderSide(
                      color: selected
                          ? AppTheme.cyan.withValues(alpha: 0.5)
                          : AppTheme.edge.withValues(alpha: 0.5),
                    ),
                    onSelected: (_) => widget.onSelectRegion(entry.key),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Artwork grid
        Expanded(
          child: regionalLeaders.isEmpty
              ? const Center(
                  child: Text(
                    'No tracks match this region',
                    style: TextStyle(color: AppTheme.textTertiary),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: regionalLeaders.length,
                  itemBuilder: (context, i) {
                    final track = regionalLeaders[i];
                    final score =
                        (regionScoreForTrack(track, selectedRegion) * 100)
                            .toInt();
                    return _ShellTrackCard(
                      track: track,
                      rank: i + 1,
                      score: score,
                      ref: widget.ref,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _GenresView extends StatefulWidget {
  const _GenresView({
    required this.tracks,
    required this.ref,
    required this.onSelectGenre,
  });

  final List<Track> tracks;
  final WidgetRef ref;
  final ValueChanged<String> onSelectGenre;

  @override
  State<_GenresView> createState() => _GenresViewState();
}

class _GenresViewState extends State<_GenresView> {
  String _selectedGenre = 'All';

  @override
  Widget build(BuildContext context) {
    final genreStats = <String, List<Track>>{};
    for (final track in widget.tracks) {
      if (track.genre.isNotEmpty) {
        genreStats.putIfAbsent(track.genre, () => []).add(track);
      }
    }
    final genreNames = genreStats.keys.toList()..sort();

    final displayTracks = _selectedGenre == 'All'
        ? ([...widget.tracks]
            ..sort((a, b) => b.trendScore.compareTo(a.trendScore)))
        : ([...(genreStats[_selectedGenre] ?? <Track>[])]
            ..sort((a, b) => b.trendScore.compareTo(a.trendScore)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                      const Icon(
                        Icons.library_music_rounded,
                        color: AppTheme.violet,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Genre Landscape',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(color: AppTheme.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${displayTracks.length} tracks${_selectedGenre != 'All' ? ' in $_selectedGenre' : ' across ${genreNames.length} genres'}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Genre selector chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    selected: _selectedGenre == 'All',
                    label: const Text('All'),
                    labelStyle: TextStyle(
                      color: _selectedGenre == 'All'
                          ? Colors.white
                          : AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                    backgroundColor: AppTheme.panel,
                    selectedColor: AppTheme.violet.withValues(alpha: 0.25),
                    side: BorderSide(
                      color: _selectedGenre == 'All'
                          ? AppTheme.violet.withValues(alpha: 0.5)
                          : AppTheme.edge.withValues(alpha: 0.5),
                    ),
                    onSelected: (_) => setState(() => _selectedGenre = 'All'),
                  ),
                ),
                ...genreNames.map((genre) {
                  final selected = genre == _selectedGenre;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: selected,
                      label: Text('$genre (${genreStats[genre]!.length})'),
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                      backgroundColor: AppTheme.panel,
                      selectedColor: AppTheme.violet.withValues(alpha: 0.25),
                      side: BorderSide(
                        color: selected
                            ? AppTheme.violet.withValues(alpha: 0.5)
                            : AppTheme.edge.withValues(alpha: 0.5),
                      ),
                      onSelected: (_) => setState(() => _selectedGenre = genre),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Artwork grid
        Expanded(
          child: displayTracks.isEmpty
              ? const Center(
                  child: Text(
                    'No tracks in this genre',
                    style: TextStyle(color: AppTheme.textTertiary),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: displayTracks.length,
                  itemBuilder: (context, i) {
                    final track = displayTracks[i];
                    final score = (track.trendScore * 100).toInt();
                    return _ShellTrackCard(
                      track: track,
                      rank: i + 1,
                      score: score,
                      ref: widget.ref,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _WatchlistView extends StatelessWidget {
  const _WatchlistView({required this.tracks, required this.onRemove});

  final List<Track> tracks;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TitleBlock(
          title: 'Watchlist',
          subtitle:
              'Keep an eye on records with breakout potential and react before they peak in your market.',
        ),
        const SizedBox(height: 18),
        Expanded(
          child: tracks.isEmpty
              ? Center(
                  child: Text(
                    'No watched tracks yet. Hit Watch in the detail panel to track movement.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: Colors.white70),
                  ),
                )
              : ListView.separated(
                  itemCount: tracks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    final delta =
                        ((track.trendHistory.last.score -
                                    track.trendHistory.first.score) *
                                100)
                            .round();
                    return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppTheme.panel,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppTheme.edge),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${track.artist} · ${track.genre} · ${track.bpm} BPM',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: Colors.white60),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            delta >= 0 ? '+$delta' : '$delta',
                            style: const TextStyle(
                              color: AppTheme.pink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            onPressed: () => onRemove(track.id),
                            icon: const Icon(Icons.visibility_off_rounded),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SettingsView extends ConsumerStatefulWidget {
  const _SettingsView({
    required this.session,
    required this.userProfile,
    required this.regions,
  });

  final SessionState session;
  final UserProfile userProfile;
  final List<String> regions;

  @override
  ConsumerState<_SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<_SettingsView> {
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  late final TextEditingController _displayNameController;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.session.email);
    _passwordController = TextEditingController();
    _displayNameController = TextEditingController(
      text: widget.session.displayName,
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TitleBlock(
          title: 'Settings & Auth',
          subtitle:
              'Configure your preferred market and switch between demo mode, email auth, or Google login once Firebase keys are wired in.',
        ),
        const SizedBox(height: 18),
        Expanded(
          child: ListView(
            children: [
              _settingsCard(
                context,
                title: 'Account',
                child: Column(
                  children: [
                    TextField(
                      controller: _displayNameController,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton(
                          onPressed: () => _runAuthAction(() async {
                            await ref
                                .read(sessionRepositoryProvider)
                                .signInWithEmail(
                                  email: _emailController.text.trim(),
                                  password: _passwordController.text,
                                );
                          }),
                          child: const Text('Sign in with Email'),
                        ),
                        FilledButton.tonal(
                          onPressed: () => _runAuthAction(() async {
                            await ref
                                .read(sessionRepositoryProvider)
                                .createAccount(
                                  email: _emailController.text.trim(),
                                  password: _passwordController.text,
                                  displayName: _displayNameController.text
                                      .trim(),
                                );
                          }),
                          child: const Text('Create Account'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => _runAuthAction(
                            () => ref.read(sessionRepositoryProvider).signOut(),
                          ),
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Sign Out'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.session.isDemo
                          ? 'You are in demo mode right now. Email and Google actions will work once Firebase and platform keys are present.'
                          : 'Signed in as ${widget.session.displayName} via ${widget.session.providerLabel}.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _settingsCard(
                context,
                title: 'DJ defaults',
                child: Consumer(
                  builder: (context, ref, _) {
                    final effectiveRegion =
                        ref.watch(selectedRegionProvider) ??
                            widget.userProfile.preferredRegion;
                    return DropdownButtonFormField<String>(
                      initialValue: widget.regions.contains(effectiveRegion)
                          ? effectiveRegion
                          : widget.regions.firstOrNull,
                      decoration: const InputDecoration(
                        labelText: 'Preferred region',
                      ),
                      items: widget.regions
                          .map(
                            (region) => DropdownMenuItem(
                              value: region,
                              child: Text(region),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        // Apply immediately for everyone (incl. guests)…
                        ref.read(selectedRegionProvider.notifier).set(value);
                        // …and persist only for a genuinely signed-in user.
                        final session = widget.session;
                        if (session.isAuthenticated &&
                            session.userId.isNotEmpty) {
                          ref
                              .read(userRepositoryProvider)
                              .updatePreferredRegion(
                                userId: session.userId,
                                fallbackName: session.displayName,
                                region: value,
                              );
                        }
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              _settingsCard(
                context,
                title: 'Runtime config',
                child: Text(
                  'Use dart-defines for FIREBASE_API_KEY, FIREBASE_APP_ID, FIREBASE_MESSAGING_SENDER_ID, FIREBASE_PROJECT_ID, FIREBASE_STORAGE_BUCKET, GOOGLE_CLIENT_ID, and GOOGLE_SERVER_CLIENT_ID when running the macOS app.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 14),
              _settingsCard(
                context,
                title: 'Mobile companion',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pair your phone to share setlists wirelessly between the VibeRadar mobile app and this desktop.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => const PairPhoneScreen(),
                      ),
                      icon: const Icon(Icons.phone_iphone_rounded),
                      label: const Text('Pair a phone'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _settingsCard(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.edge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Future<void> _runAuthAction(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Authentication request completed.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Auth request failed: $error')));
      }
    }
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: Colors.white70),
        ),
      ],
    );
  }
}
