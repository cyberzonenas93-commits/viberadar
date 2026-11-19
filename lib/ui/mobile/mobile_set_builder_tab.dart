import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/music_genres.dart';
import '../../core/theme/app_theme.dart';
import '../../models/crate.dart';
import '../../models/crate_track.dart';
import '../../models/track.dart';
import '../../providers/setlist_provider.dart';
import '../../services/platform_search_service.dart';
import '../../services/set_builder_behavior_service.dart';
import '../../services/set_sequence_planner.dart';
import '../../services/soundcharts_ai_ranking_service.dart';
import '../widgets/platform_play_actions.dart';
import '../widgets/track_action_menu.dart';

class MobileSetBuilderTab extends ConsumerStatefulWidget {
  const MobileSetBuilderTab({super.key});

  @override
  ConsumerState<MobileSetBuilderTab> createState() =>
      _MobileSetBuilderTabState();
}

class _MobileSetBuilderTabState extends ConsumerState<MobileSetBuilderTab> {
  final _platformSearch = PlatformSearchService();
  final _ranking = SoundchartsAiRankingService();
  final _planner = const SetSequencePlanner();
  final _behaviorService = const SetBuilderBehaviorService();

  final _nameController = TextEditingController(text: 'Pop Set');
  final _eventController = TextEditingController(text: 'Club night');
  final _cityController = TextEditingController(text: 'Global');
  final _crowdController = TextEditingController(text: '21-34');
  final _genreController = TextEditingController(
    text: 'Pop, Hip-Hop, R&B, House, Afrobeats',
  );
  final _mustPlayController = TextEditingController();
  final _avoidController = TextEditingController();

  String _region = 'All';
  SetEnergyCurve _energyCurve = SetEnergyCurve.smoothRise;
  SetContentPreference _contentPreference = SetContentPreference.cleanPreferred;
  int _setLengthMinutes = 75;
  bool _allowHardSwitches = false;

  SetBuilderBehaviorProfile _behaviorProfile = SetBuilderBehaviorProfile.empty;
  SetSequencePlan? _plan;
  bool _building = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBehaviorProfile());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _eventController.dispose();
    _cityController.dispose();
    _crowdController.dispose();
    _genreController.dispose();
    _mustPlayController.dispose();
    _avoidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plannedTracks = _plan?.tracks ?? const <SequencePlannedTrack>[];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _BuilderPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_fix_high_rounded,
                    color: AppTheme.amber,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$_targetCount tracks from live regional evidence',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _TextInput(label: 'Setlist name', controller: _nameController),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _TextInput(
                      label: 'Event',
                      controller: _eventController,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 108,
                    child: _DropdownInput<String>(
                      label: 'Region',
                      value: _region,
                      values: _regions,
                      labelFor: (value) => value,
                      onChanged: (value) => setState(() => _region = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _TextInput(
                      label: 'City / market',
                      controller: _cityController,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 120,
                    child: _TextInput(
                      label: 'Crowd age',
                      controller: _crowdController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _TextInput(label: 'Genre lane', controller: _genreController),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _DropdownInput<SetEnergyCurve>(
                      label: 'Energy',
                      value: _energyCurve,
                      values: SetEnergyCurve.values,
                      labelFor: (value) => value.label,
                      onChanged: (value) =>
                          setState(() => _energyCurve = value),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DropdownInput<SetContentPreference>(
                      label: 'Content',
                      value: _contentPreference,
                      values: SetContentPreference.values,
                      labelFor: (value) => value.label,
                      onChanged: (value) =>
                          setState(() => _contentPreference = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Length: $_setLengthMinutes min',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Slider(
                value: _setLengthMinutes.toDouble(),
                min: 30,
                max: 180,
                divisions: 10,
                activeColor: AppTheme.cyan,
                inactiveColor: AppTheme.edge,
                onChanged: (value) =>
                    setState(() => _setLengthMinutes = value.round()),
              ),
              SwitchListTile.adaptive(
                value: _allowHardSwitches,
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppTheme.cyan,
                title: const Text(
                  'Allow hard switches',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onChanged: (value) =>
                    setState(() => _allowHardSwitches = value),
              ),
              const SizedBox(height: 8),
              _TextInput(label: 'Must play', controller: _mustPlayController),
              const SizedBox(height: 10),
              _TextInput(label: 'Avoid', controller: _avoidController),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _building ? null : _buildSet,
                      icon: _building
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: Text(_building ? 'Building...' : 'Build Set'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: plannedTracks.isEmpty || _saving
                          ? null
                          : _saveSet,
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: Text(_saving ? 'Saving...' : 'Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _StatusPanel(icon: Icons.error_outline_rounded, text: _error!),
        ],
        if (_plan != null) ...[
          const SizedBox(height: 14),
          _StatusPanel(
            icon: Icons.timeline_rounded,
            text:
                '${plannedTracks.length} sequenced tracks'
                '${_plan!.removedDuplicates > 0 ? ' after removing ${_plan!.removedDuplicates} duplicates' : ''}',
          ),
        ],
        const SizedBox(height: 12),
        for (var i = 0; i < plannedTracks.length; i++) ...[
          _PlannedTrackTile(
            index: i + 1,
            planned: plannedTracks[i],
            ref: ref,
            genreFallback: _primaryGenreLane,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Future<void> _loadBehaviorProfile() async {
    final profile = await _behaviorService.load();
    if (!mounted) return;
    setState(() => _behaviorProfile = profile);
  }

  Future<void> _buildSet() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _building = true;
      _error = null;
    });

    try {
      final context = _djContext();
      final genres = _terms(_genreController.text);
      final target = _targetCount;
      final perGenre = (target / genres.length).ceil().clamp(12, 42).toInt();
      final candidates = <PlatformTrackResult>[];
      final seen = <String>{};

      for (final genre in genres.take(4)) {
        final results = await _platformSearch.searchByGenre(
          genre,
          limit: perGenre + 20,
          region: _region,
          genreLane: genre,
        );
        final ranked = await _ranking.rankForSetBuilder(
          results: results,
          mode: 'Top Trending',
          genre: genre,
          region: _region,
          djContext: context.summary,
        );
        _appendUnique(candidates, seen, ranked);
      }

      for (final mustPlay in context.mustPlay.take(6)) {
        final results = await _platformSearch.search(
          mustPlay,
          limit: 14,
          region: _region,
        );
        _appendUnique(candidates, seen, results);
      }

      final plan = _planner.planPlatformSet(
        candidates: candidates,
        targetCount: target,
        context: context,
        behavior: _behaviorProfile,
      );

      if (!mounted) return;
      setState(() {
        _plan = plan;
        _error = plan.tracks.isEmpty
            ? 'No eligible live tracks came back for this region and context.'
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Set Builder could not reach live services.');
    } finally {
      if (mounted) setState(() => _building = false);
    }
  }

  Future<void> _saveSet() async {
    final plan = _plan;
    if (plan == null || plan.tracks.isEmpty) return;
    setState(() => _saving = true);

    final now = DateTime.now();
    final crate = Crate(
      id: const Uuid().v4(),
      name: _nameController.text.trim().isEmpty
          ? 'Mobile Set Builder'
          : _nameController.text.trim(),
      context: _djContext().summary,
      tracks: [
        for (final planned in plan.tracks)
          CrateTrack(
            title: planned.track.title,
            artist: planned.track.artist,
            bpm: planned.bpm,
            key: planned.key,
            spotifyUrl: planned.track.spotifyUrl,
            appleUrl: planned.track.appleUrl,
            youtubeUrl: planned.track.youtubeUrl,
            artworkUrl: planned.track.artworkUrl,
          ),
      ],
      createdAt: now,
      updatedAt: now,
    );

    try {
      await ref.read(setlistActionsProvider).save(crate);
      _behaviorProfile = await _behaviorService.recordTracks(
        event: SetBuilderBehaviorEvent.save,
        tracks: plan.tracks.map((planned) => planned.track),
        genre: _genreController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Setlist saved to your account')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Setlist could not be saved.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  DjSetContext _djContext() => DjSetContext(
    eventType: _nonEmpty(_eventController.text, 'Club night'),
    cityMarket: _nonEmpty(_cityController.text, 'Global'),
    crowdAge: _nonEmpty(_crowdController.text, '21-34'),
    genreLane: _nonEmpty(_genreController.text, 'Pop'),
    energyCurve: _energyCurve,
    contentPreference: _contentPreference,
    setLengthMinutes: _setLengthMinutes,
    allowHardSwitches: _allowHardSwitches,
    mustPlay: _terms(_mustPlayController.text),
    avoid: _terms(_avoidController.text),
  );

  int get _targetCount =>
      (_setLengthMinutes / 3.6).round().clamp(8, 60).toInt();

  void _appendUnique(
    List<PlatformTrackResult> target,
    Set<String> seen,
    Iterable<PlatformTrackResult> source,
  ) {
    for (final track in source) {
      final key = '${track.artist.toLowerCase()}::${track.title.toLowerCase()}';
      if (seen.add(key)) target.add(track);
    }
  }

  List<String> _terms(String value) {
    final terms = value
        .split(RegExp(r'[,;\n]+'))
        .map((term) => term.trim())
        .where((term) => term.isNotEmpty)
        .toList();
    return terms.isEmpty ? ['Pop'] : terms;
  }

  String get _primaryGenreLane => _terms(_genreController.text).first;

  String _nonEmpty(String value, String fallback) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }
}

class _BuilderPanel extends StatelessWidget {
  const _BuilderPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.panel.withValues(alpha: 0.78),
        border: Border.all(color: AppTheme.hairline),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.panelRaised.withValues(alpha: 0.72),
        border: Border.all(color: AppTheme.hairline),
        borderRadius: BorderRadius.circular(AppTheme.rSm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.cyan, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlannedTrackTile extends StatelessWidget {
  const _PlannedTrackTile({
    required this.index,
    required this.planned,
    required this.ref,
    required this.genreFallback,
  });

  final int index;
  final SequencePlannedTrack planned;
  final WidgetRef ref;
  final String genreFallback;

  @override
  Widget build(BuildContext context) {
    final track = planned.track;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showTrackActionMenu(
        context,
        ref,
        _trackFromPlatformResult(track, genreFallback: genreFallback),
        preferSyncedSetlists: true,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.panel.withValues(alpha: 0.72),
          border: Border.all(color: AppTheme.hairline),
          borderRadius: BorderRadius.circular(AppTheme.rMd),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: track.artworkUrl == null || track.artworkUrl!.isEmpty
                      ? const ColoredBox(
                          color: AppTheme.panelRaised,
                          child: Icon(
                            Icons.music_note_rounded,
                            color: AppTheme.textTertiary,
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: track.artworkUrl!,
                          fit: BoxFit.cover,
                          memCacheWidth: 160,
                          memCacheHeight: 160,
                          errorWidget: (_, _, _) => const ColoredBox(
                            color: AppTheme.panelRaised,
                            child: Icon(
                              Icons.music_note_rounded,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$index. ${planned.phase.label}',
                      style: const TextStyle(
                        color: AppTheme.amber,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _MiniBadge(
                          '${(planned.confidence * 100).round()}% confidence',
                        ),
                        if (track.soundchartsRegion != null)
                          _MiniBadge(track.soundchartsRegion!),
                        if (track.appleChartRank != null)
                          _MiniBadge('Apple #${track.appleChartRank}'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      planned.reasons.take(2).join('  '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 8),
                    PlatformPlayActions.fromUrls(
                      spotifyUrl: track.spotifyUrl,
                      appleUrl: track.appleUrl,
                      youtubeUrl: track.youtubeUrl,
                      soundchartsUrl: track.soundchartsUrl,
                      deezerUrl: track.deezerUrl,
                      labelStyle: PlatformPlayLabelStyle.platform,
                      compact: true,
                      maxLinks: 3,
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

Track _trackFromPlatformResult(
  PlatformTrackResult result, {
  required String genreFallback,
}) {
  final now = DateTime.now();
  final links = <String, String>{
    if (result.appleUrl != null && result.appleUrl!.isNotEmpty)
      'apple': result.appleUrl!,
    if (result.spotifyUrl != null && result.spotifyUrl!.isNotEmpty)
      'spotify': result.spotifyUrl!,
    if (result.youtubeUrl != null && result.youtubeUrl!.isNotEmpty)
      'youtube': result.youtubeUrl!,
    if (result.deezerUrl != null && result.deezerUrl!.isNotEmpty)
      'deezer': result.deezerUrl!,
    if (result.soundchartsUrl != null && result.soundchartsUrl!.isNotEmpty)
      'soundcharts': result.soundchartsUrl!,
  };
  final genre = isSpecificGenre(result.genre)
      ? canonicalGenre(result.genre)
      : isSpecificGenre(genreFallback)
      ? canonicalGenre(genreFallback)
      : 'Pop';
  return Track(
    id: 'ai:${_stableActionTrackId(result.title, result.artist)}',
    title: result.title,
    artist: result.artist,
    artworkUrl: result.artworkUrl ?? '',
    bpm: 0,
    keySignature: '--',
    genre: genre,
    vibe: 'set builder',
    trendScore: result.trendScore,
    regionScores: const {},
    platformLinks: links,
    createdAt: now,
    updatedAt: now,
    energyLevel: result.trendScore.clamp(0.25, 0.95).toDouble(),
    trendHistory: const [],
    sources: links.keys.toList(),
  );
}

String _stableActionTrackId(String title, String artist) {
  return '$artist::$title'
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.cyan.withValues(alpha: 0.08),
        border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          label,
          style: const TextStyle(
            color: AppTheme.cyan,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _TextInput extends StatelessWidget {
  const _TextInput({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLength: 120,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        labelStyle: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
        filled: true,
        fillColor: AppTheme.panelRaised,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.4)),
        ),
      ),
    );
  }
}

class _DropdownInput<T> extends StatelessWidget {
  const _DropdownInput({
    required this.label,
    required this.value,
    required this.values,
    required this.labelFor,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T) labelFor;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
        filled: true,
        fillColor: AppTheme.panelRaised,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.4)),
        ),
      ),
      dropdownColor: AppTheme.panelRaised,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
      items: [
        for (final item in values)
          DropdownMenuItem<T>(value: item, child: Text(labelFor(item))),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

const _regions = ['All', 'GH', 'NG', 'ZA', 'GB', 'US', 'CA', 'AU', 'DE', 'FR'];
