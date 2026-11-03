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
    this.genre = 'Pop',
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
    required this.localLibrary,
    required this.genres,
    required this.vibes,
    required this.session,
    required this.userProfile,
  });

  final List<Track> allTracks;
  final List<LibraryTrack> localLibrary;
  final List<String> genres;
  final List<String> vibes;
  final SessionState session;
  final UserProfile userProfile;

  @override
  ConsumerState<_SetBuilderView> createState() => _SetBuilderViewState();
}

class _SetBuilderViewState extends ConsumerState<_SetBuilderView> {
  final _platformSearch = PlatformSearchService();
  final _ranking = SoundchartsAiRankingService();
  final _planner = const SetSequencePlanner();
  final _behaviorService = const SetBuilderBehaviorService();
  final List<_SetSlot> _slots = [
    _SetSlot(genre: 'Pop', mode: _SortMode.trending, count: 30),
    _SetSlot(genre: 'R&B', mode: _SortMode.hottest, count: 20),
    _SetSlot(genre: 'Hip-Hop', mode: _SortMode.trending, count: 20),
  ];
  List<AiCrateTrack> _platformTracks = const [];
  List<PlatformTrackResult> _plannedResults = const [];
  SetSequencePlan? _lastPlan;
  SetBuilderBehaviorProfile _behaviorProfile = SetBuilderBehaviorProfile.empty;
  bool _searchingPlatforms = false;
  String _crateName = 'My Set';
  String _eventType = 'Club night';
  String _cityMarket = 'Global';
  String _crowdAge = '21-34';
  String _genreLane = 'Pop, R&B, Hip-Hop';
  SetEnergyCurve _energyCurve = SetEnergyCurve.smoothRise;
  SetContentPreference _contentPreference = SetContentPreference.cleanPreferred;
  int _setLengthMinutes = 90;
  bool _allowHardSwitches = false;
  String _mustPlay = '';
  String _avoid = '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadBehaviorProfile());
    _regenerate();
  }

  @override
  Widget build(BuildContext context) {
    final totalRequested = _slots.fold<int>(0, (sum, s) => sum + s.count);
    final targetCount = _targetCount(totalRequested);
    final localMatches = _platformTracks.where((t) => t.localMatch).length;

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
                      '${_platformTracks.length} / $targetCount tracks sequenced from Apple Music, Spotify, YouTube Music, Deezer, Soundcharts & AI'
                      '${localMatches > 0 ? ' · $localMatches found locally' : ''}'
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
                      hintText: 'Setlist name…',
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
                  label: const Text('Save Setlist'),
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

        SliverToBoxAdapter(
          child: _buildContextPanel(totalRequested, targetCount),
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
                    'Searching Apple Music, Spotify, YouTube Music, Deezer and Soundcharts with AI…',
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
                maxCrossAxisExtent: 220,
                childAspectRatio: 0.58,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate((context, i) {
                final t = _platformTracks[i];
                return _PlatformResultCard(
                  track: t,
                  index: i,
                  ref: ref,
                  genreFallback: _primaryGenreLane,
                  onRemove: () => _removeTrackAt(i),
                  onMarkWrong: () => _markWrongAt(i),
                  onMoveUp: i == 0 ? null : () => _moveTrack(i, i - 1),
                  onMoveDown: i == _platformTracks.length - 1
                      ? null
                      : () => _moveTrack(i, i + 1),
                );
              }, childCount: _platformTracks.length),
            ),
          ),
      ],
    );
  }

  Widget _buildContextPanel(int totalRequested, int targetCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.panel.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.edge.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.route_rounded, color: AppTheme.cyan, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'DJ context',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  '$targetCount planned from $totalRequested requested'
                  '${(_lastPlan?.removedDuplicates ?? 0) > 0 ? ' · ${_lastPlan!.removedDuplicates} duplicates grouped' : ''}'
                  ' · ${_energyCurve.label}',
                  style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _contextTextField(
                    label: 'Event',
                    value: _eventType,
                    hint: 'Club night',
                    onChanged: (value) => _eventType = value,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _contextTextField(
                    label: 'City/market',
                    value: _cityMarket,
                    hint: 'Global',
                    onChanged: (value) => _cityMarket = value,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  child: _contextTextField(
                    label: 'Crowd age',
                    value: _crowdAge,
                    hint: '21-34',
                    onChanged: (value) => _crowdAge = value,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 92,
                  child: _contextTextField(
                    label: 'Minutes',
                    value: '$_setLengthMinutes',
                    hint: '90',
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      final minutes = int.tryParse(value);
                      if (minutes != null) {
                        _setLengthMinutes = minutes.clamp(15, 480).toInt();
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _contextTextField(
                    label: 'Genre lane',
                    value: _genreLane,
                    hint: 'Pop, R&B',
                    onChanged: (value) => _genreLane = value,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 150,
                  child: _contextDropdown<SetEnergyCurve>(
                    label: 'Energy',
                    value: _energyCurve,
                    values: SetEnergyCurve.values,
                    labelFor: (value) => value.label,
                    onChanged: (value) => setState(() => _energyCurve = value),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 160,
                  child: _contextDropdown<SetContentPreference>(
                    label: 'Content',
                    value: _contentPreference,
                    values: SetContentPreference.values,
                    labelFor: (value) => value.label,
                    onChanged: (value) =>
                        setState(() => _contentPreference = value),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 150,
                  child: SwitchListTile.adaptive(
                    value: _allowHardSwitches,
                    onChanged: (value) =>
                        setState(() => _allowHardSwitches = value),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Hard switch',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    activeThumbColor: AppTheme.amber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _contextTextField(
                    label: 'Must play',
                    value: _mustPlay,
                    hint: 'artist or song, comma separated',
                    onChanged: (value) => _mustPlay = value,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _contextTextField(
                    label: 'Avoid',
                    value: _avoid,
                    hint: 'songs, artists, versions to avoid',
                    onChanged: (value) => _avoid = value,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _contextTextField({
    required String label,
    required String value,
    required String hint,
    required ValueChanged<String> onChanged,
    TextInputType? keyboardType,
  }) {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: TextEditingController(text: value),
        onChanged: onChanged,
        keyboardType: keyboardType,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(
            color: AppTheme.textTertiary,
            fontSize: 10,
          ),
          hintStyle: const TextStyle(
            color: AppTheme.textTertiary,
            fontSize: 11,
          ),
          filled: true,
          fillColor: AppTheme.panelRaised,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _contextDropdown<T>({
    required String label,
    required T value,
    required List<T> values,
    required String Function(T value) labelFor,
    required ValueChanged<T> onChanged,
  }) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButton<T>(
        value: value,
        dropdownColor: AppTheme.panelRaised,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
        hint: Text(label),
        items: values
            .map(
              (item) => DropdownMenuItem<T>(
                value: item,
                child: Text(labelFor(item), overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (item) {
          if (item != null) onChanged(item);
        },
      ),
    );
  }

  Widget _buildSlotRow(int index) {
    final slot = _slots[index];
    final genreOptions = mergedGenreOptions(
      widget.genres.where((genre) => genre != 'All'),
    );
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
    if (_platformTracks.isNotEmpty) {
      unawaited(
        _behaviorService
            .record(event: SetBuilderBehaviorEvent.searchAgain)
            .then((profile) {
              if (mounted) setState(() => _behaviorProfile = profile);
            }),
      );
    }
    setState(() {
      _platformTracks = [];
      _plannedResults = const [];
      _lastPlan = null;
      _searchingPlatforms = true;
    });
    unawaited(_buildFromPlatforms());
  }

  Future<void> _buildFromPlatforms() async {
    final candidates = <PlatformTrackResult>[];
    final seen = <String>{};
    final context = _djContext();

    for (final slot in _slots) {
      final genre = slot.genre == 'All' ? 'music' : slot.genre;
      final region = _searchRegion(slot.region);
      final modeHint = switch (slot.mode) {
        _SortMode.all => 'best top popular',
        _SortMode.trending => 'trending',
        _SortMode.hottest => 'hot new',
        _SortMode.rising => 'new rising',
        _SortMode.greatestOf => 'best greatest',
      };
      final bpmHint = (slot.minBpm > 60 || slot.maxBpm < 200)
          ? '${slot.minBpm}-${slot.maxBpm} bpm'
          : '';

      try {
        List<PlatformTrackResult> results;

        if (slot.artist.isNotEmpty) {
          results = await _platformSearch.searchByArtist(
            '${slot.artist} $bpmHint'.trim(),
            limit: slot.count + 50,
            region: region,
          );
        } else if (slot.mode == _SortMode.all) {
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
              region: region,
              genreLane: genre,
            );
            for (final r in batch) {
              if (allSeen.add(_candidateKey(r))) allResults.add(r);
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
            region: region,
            genreLane: genre,
          );
        }

        results = await _ranking.rankForSetBuilder(
          results: results,
          mode: slot.modeLabel,
          genre: genre,
          artist: slot.artist,
          region: region,
          yearFrom: slot.yearFrom,
          yearTo: slot.yearTo,
          minBpm: slot.minBpm,
          maxBpm: slot.maxBpm,
          djContext: context.summary,
        );

        for (final r in results) {
          if (seen.add(_candidateKey(r))) candidates.add(r);
        }

        for (final mustPlay in context.mustPlay.take(6)) {
          final mustResults = await _platformSearch.search(
            mustPlay,
            limit: 12,
            region: region,
          );
          for (final r in mustResults) {
            if (seen.add(_candidateKey(r))) candidates.add(r);
          }
        }

        _planCandidates(candidates, context);
      } catch (e, st) {
        developer.log(
          'Platform search slot failed',
          name: 'VibeShell',
          error: e,
          stackTrace: st,
        );
      }
    }

    _planCandidates(candidates, context);

    if (mounted) {
      setState(() => _searchingPlatforms = false);
    }
  }

  void _planCandidates(
    List<PlatformTrackResult> candidates,
    DjSetContext context,
  ) {
    final totalRequested = _slots.fold<int>(0, (sum, s) => sum + s.count);
    final plan = _planner.planPlatformSet(
      candidates: candidates,
      targetCount: _targetCount(totalRequested),
      context: context,
      localLibrary: widget.localLibrary,
      behavior: _behaviorProfile,
    );

    final plannedResults = plan.tracks.map((planned) => planned.track).toList();
    final aiTracks = plan.tracks.map((planned) {
      final r = planned.track;
      return AiCrateTrack(
        title: r.title,
        artist: r.artist,
        bpm: planned.bpm,
        key: planned.key,
        artworkUrl: r.artworkUrl ?? planned.localMatch?.artworkUrl,
        spotifyUrl: r.spotifyUrl,
        appleUrl: r.appleUrl,
        youtubeUrl: r.youtubeUrl,
        soundchartsUrl: r.soundchartsUrl,
        soundchartsSource: r.soundchartsSource,
        soundchartsRegion: r.soundchartsRegion,
        resolved: r.hasUrl,
        phaseLabel: planned.phase.label,
        confidence: planned.confidence,
        reasons: planned.reasons,
        localMatch: planned.foundLocally,
        versionTag: _versionTag(r),
      );
    }).toList();

    if (mounted) {
      setState(() {
        _lastPlan = plan;
        _plannedResults = plannedResults;
        _platformTracks = aiTracks;
      });
    }
  }

  String _candidateKey(PlatformTrackResult track) =>
      '${track.title.toLowerCase().trim()}::${track.artist.toLowerCase().trim()}';

  DjSetContext _djContext() => DjSetContext(
    eventType: _eventType.trim().isEmpty ? 'Club night' : _eventType.trim(),
    cityMarket: _cityMarket.trim().isEmpty ? 'Global' : _cityMarket.trim(),
    crowdAge: _crowdAge.trim().isEmpty ? 'All ages' : _crowdAge.trim(),
    genreLane: _genreLane.trim().isEmpty ? 'Pop' : _genreLane.trim(),
    energyCurve: _energyCurve,
    contentPreference: _contentPreference,
    setLengthMinutes: _setLengthMinutes,
    allowHardSwitches: _allowHardSwitches,
    mustPlay: _splitTerms(_mustPlay),
    avoid: _splitTerms(_avoid),
  );

  List<String> _splitTerms(String value) => value
      .split(',')
      .map((term) => term.trim())
      .where((term) => term.isNotEmpty)
      .toList();

  String get _primaryGenreLane {
    final lanes = _splitTerms(_genreLane);
    return lanes.isEmpty ? 'Pop' : lanes.first;
  }

  int _targetCount(int totalRequested) {
    final byLength = (_setLengthMinutes / 3.5).round().clamp(6, 150).toInt();
    return totalRequested.clamp(1, byLength).toInt();
  }

  String? _versionTag(PlatformTrackResult track) {
    final text = '${track.title} ${track.artist}'.toLowerCase();
    if (text.contains('clean') || text.contains('radio edit')) return 'Clean';
    if (text.contains('remix')) return 'Remix';
    if (text.contains('edit')) return 'Edit';
    if (text.contains('explicit') || text.contains('dirty')) return 'Explicit';
    return null;
  }

  Future<void> _loadBehaviorProfile() async {
    final profile = await _behaviorService.load();
    if (mounted) setState(() => _behaviorProfile = profile);
  }

  Future<void> _recordBehavior(
    SetBuilderBehaviorEvent event, {
    PlatformTrackResult? track,
    String? genre,
  }) async {
    final profile = await _behaviorService.record(
      event: event,
      track: track,
      genre: genre,
    );
    if (mounted) setState(() => _behaviorProfile = profile);
  }

  void _removeTrackAt(int index) {
    if (index < 0 || index >= _platformTracks.length) return;
    final removed = _plannedResults.length > index
        ? _plannedResults[index]
        : null;
    setState(() {
      _platformTracks = [..._platformTracks]..removeAt(index);
      _plannedResults = [..._plannedResults]..removeAt(index);
    });
    if (removed != null) {
      unawaited(
        _recordBehavior(SetBuilderBehaviorEvent.delete, track: removed),
      );
    }
  }

  void _markWrongAt(int index) {
    if (index < 0 || index >= _platformTracks.length) return;
    final removed = _plannedResults.length > index
        ? _plannedResults[index]
        : null;
    setState(() {
      _platformTracks = [..._platformTracks]..removeAt(index);
      _plannedResults = [..._plannedResults]..removeAt(index);
    });
    if (removed != null) {
      unawaited(
        _recordBehavior(SetBuilderBehaviorEvent.markWrong, track: removed),
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Marked wrong and removed from this set.')),
    );
  }

  void _moveTrack(int from, int to) {
    if (from < 0 ||
        to < 0 ||
        from >= _platformTracks.length ||
        to >= _platformTracks.length) {
      return;
    }
    final movedResult = _plannedResults.length > from
        ? _plannedResults[from]
        : null;
    setState(() {
      final tracks = [..._platformTracks];
      final track = tracks.removeAt(from);
      tracks.insert(to, track);
      _platformTracks = tracks;

      final results = [..._plannedResults];
      if (results.length > from) {
        final result = results.removeAt(from);
        results.insert(to, result);
      }
      _plannedResults = results;
    });
    if (movedResult != null) {
      unawaited(
        _recordBehavior(SetBuilderBehaviorEvent.reorder, track: movedResult),
      );
    }
  }

  String? _searchRegion(String region) {
    final value = region.trim().toUpperCase();
    if (value.isEmpty || value == 'ALL' || value == 'GLOBAL') return null;
    return value;
  }

  Future<void> _saveCrate() async {
    if (_platformTracks.isEmpty) return;
    final name = _crateName.trim().isEmpty ? 'My Set' : _crateName.trim();

    // Save as AI setlist (with play URLs)
    ref.read(aiCrateProvider.notifier).setCrate(name, _platformTracks);
    for (final result in _plannedResults) {
      unawaited(
        _recordBehavior(
          SetBuilderBehaviorEvent.save,
          track: result,
          genre: result.genre,
        ),
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Setlist saved to your workspace.')),
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
