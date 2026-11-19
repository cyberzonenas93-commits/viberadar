import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/app_section.dart';
import '../../../models/track.dart';
import '../../../providers/app_state.dart';
import '../../../providers/library_provider.dart';
import '../../../services/ai_copilot_service.dart';
import '../../../services/platform_search_service.dart';
import '../../widgets/ui_kit.dart';

part 'ai_copilot_screen_models.dart';
part 'ai_copilot_screen_widgets.dart';

// ── Screen ────────────────────────────────────────────────────────────────────

class AiCopilotScreen extends ConsumerStatefulWidget {
  const AiCopilotScreen({super.key});
  @override
  ConsumerState<AiCopilotScreen> createState() => _AiCopilotScreenState();
}

class _AiCopilotScreenState extends ConsumerState<AiCopilotScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _isTyping = false;
  bool _showSettings = false;
  String _model = AiCopilotService.defaultOpenAiModel;
  StreamSubscription<String>? _streamSub;

  static const _suggestions = [
    'Build me a 20-track Afrobeats set for a club night',
    'Best R&B and Pop songs from 2000 to today',
    'Which tracks mix well with Burna Boy Last Last?',
    'Build me a greatest-of Hip-Hop set from the 2010s',
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final svc = ref.read(_aiServiceProvider);
    final model = await svc.getModel();
    if (mounted) {
      setState(() {
        _model = model;
      });
    }
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatState = ref.watch(_copilotChatProvider);
    final messages = chatState.messages;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.violet.withValues(alpha: 0.08),
                Colors.transparent,
              ],
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppTheme.violet, AppTheme.pink],
                  ),
                  borderRadius: BorderRadius.circular(AppTheme.rMd),
                  boxShadow: AppTheme.glow(
                    AppTheme.violet,
                    blur: 18,
                    opacity: 0.32,
                  ),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Copilot',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.violet.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _model,
                            style: const TextStyle(
                              color: AppTheme.violet,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Clear chat button
              if (messages.length > 1)
                Tooltip(
                  message: 'Clear chat',
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(AppTheme.rSm),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppTheme.rSm),
                      onTap: () =>
                          ref.read(_copilotChatProvider.notifier).clearChat(),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: AppTheme.textTertiary,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              // Settings button
              Material(
                color: _showSettings
                    ? AppTheme.violet.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.rSm),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.rSm),
                  onTap: () => setState(() => _showSettings = !_showSettings),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      _showSettings
                          ? Icons.close_rounded
                          : Icons.settings_rounded,
                      color: _showSettings
                          ? AppTheme.violet
                          : AppTheme.textTertiary,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Settings panel
        if (_showSettings) _buildSettingsPanel(),

        // Active year filter indicator
        if (chatState.yearFrom != null || chatState.yearTo != null)
          _buildYearFilterBar(chatState),

        const SizedBox(height: 8),
        const Divider(color: AppTheme.hairline, height: 1),

        // Messages
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 8),
            itemCount: messages.length,
            itemBuilder: (ctx, i) {
              final msg = messages[i];
              return _ChatBubble(
                isUser: msg.isUser,
                text: msg.text,
                isStreaming: msg.isStreaming,
              );
            },
          ),
        ),

        // Suggestions (only when chat is fresh)
        if (messages.length == 1)
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 28),
              itemCount: _suggestions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) => PressableScale(
                onTap: () => _send(_suggestions[i]),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.violet.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppTheme.rPill),
                    border: Border.all(
                      color: AppTheme.violet.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    _suggestions[i],
                    style: const TextStyle(
                      color: AppTheme.violet,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Input bar
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 10, 28, 20),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                  ),
                  onSubmitted: _send,
                  decoration: InputDecoration(
                    hintText:
                        'Build a set, find tracks, ask anything about music…',
                    hintStyle: const TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: AppTheme.panelRaised,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.rMd),
                      borderSide: const BorderSide(color: AppTheme.hairline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.rMd),
                      borderSide: const BorderSide(color: AppTheme.hairline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.rMd),
                      borderSide: const BorderSide(color: AppTheme.violet),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              PressableScale(
                onTap: _isTyping ? null : () => _send(_controller.text),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: _isTyping
                        ? null
                        : const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppTheme.violet, Color(0xFF6D4AE6)],
                          ),
                    color: _isTyping ? AppTheme.edge : null,
                    borderRadius: BorderRadius.circular(AppTheme.rMd),
                    boxShadow: _isTyping
                        ? null
                        : AppTheme.glow(
                            AppTheme.violet,
                            blur: 18,
                            opacity: 0.40,
                          ),
                  ),
                  child: _isTyping
                      ? const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Settings panel ────────────────────────────────────────────────────────

  Widget _buildSettingsPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.glass(
          radius: AppTheme.rMd,
          tint: AppTheme.violet,
          border: AppTheme.hairlineStrong,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.panel,
                borderRadius: BorderRadius.circular(AppTheme.rSm),
                border: Border.all(color: AppTheme.hairline),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    color: AppTheme.violet,
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AI access',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Model',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppTheme.panel,
                borderRadius: BorderRadius.circular(AppTheme.rSm),
                border: Border.all(color: AppTheme.hairline),
              ),
              child: DropdownButton<String>(
                value:
                    [...AiCopilotService.allowedOpenAiModels].contains(_model)
                    ? _model
                    : AiCopilotService.defaultOpenAiModel,
                dropdownColor: AppTheme.panelRaised,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                ),
                underline: const SizedBox(),
                isExpanded: true,
                items: AiCopilotService.allowedOpenAiModels
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) async {
                  if (v != null) {
                    await ref.read(_aiServiceProvider).setModel(v);
                    if (mounted) setState(() => _model = v);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildYearFilterBar(_CopilotChatState chatState) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 4, 28, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.cyan.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppTheme.rSm),
          border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.date_range_rounded,
              color: AppTheme.cyan,
              size: 12,
            ),
            const SizedBox(width: 6),
            Text(
              'Year filter: ${chatState.yearFrom ?? "any"} – ${chatState.yearTo ?? "any"}',
              style: const TextStyle(color: AppTheme.cyan, fontSize: 11),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () {
                ref
                    .read(_copilotChatProvider.notifier)
                    .setYearFilter(yearFrom: null, yearTo: null);
                ref
                    .read(copilotYearFilterProvider.notifier)
                    .update(yearFrom: null, yearTo: null);
              },
              child: const Icon(Icons.close, color: AppTheme.cyan, size: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ── Track context ─────────────────────────────────────────────────────────

  List<Map<String, String>> _getTrackContext() {
    final tracksAsync = ref.read(trackStreamProvider);
    final allTracks = tracksAsync.value ?? <Track>[];
    final chatState = ref.read(_copilotChatProvider);
    var filtered = [...allTracks];

    if (chatState.yearFrom != null) {
      filtered = filtered
          .where((t) => t.effectiveReleaseYear >= chatState.yearFrom!)
          .toList();
    }
    if (chatState.yearTo != null) {
      filtered = filtered
          .where((t) => t.effectiveReleaseYear <= chatState.yearTo!)
          .toList();
    }

    filtered.sort((a, b) => b.trendScore.compareTo(a.trendScore));

    return filtered
        .take(80)
        .map(
          (t) => {
            'title': t.title,
            'artist': t.artist,
            'bpm': t.bpm.toString(),
            'key': t.keySignature,
            'genre': t.genre,
            'year': t.effectiveReleaseYear.toString(),
            'region': t.leadRegion,
            'sources': t.effectiveSources.join(', '),
          },
        )
        .toList();
  }

  // ── Send with streaming ───────────────────────────────────────────────────

  Future<void> _send(String text) async {
    if (text.trim().isEmpty || _isTyping) return;

    final chatNotifier = ref.read(_copilotChatProvider.notifier);
    chatNotifier.addUserMessage(text);
    _controller.clear();
    setState(() => _isTyping = true);
    _scrollToBottom();

    // Add empty streaming placeholder
    chatNotifier.addStreamingMessage();
    _scrollToBottom();

    try {
      final trackContext = _getTrackContext();
      final svc = ref.read(_aiServiceProvider);
      final chatState = ref.read(_copilotChatProvider);

      String fullResponse = '';

      _streamSub = svc
          .chatStream(
            chatState.history.where((m) => m['role'] != 'system').toList(),
            text,
            trackContext: trackContext,
            yearFrom: chatState.yearFrom,
            yearTo: chatState.yearTo,
          )
          .listen(
            (partial) {
              fullResponse = partial;
              chatNotifier.updateStreamingMessage(partial);
              _scrollToBottom();
            },
            onDone: () {
              chatNotifier.finalizeStreamingMessage(fullResponse);
              setState(() => _isTyping = false);
              _scrollToBottom();

              // Parse crate from response and auto-navigate
              _parseCrateFromResponse(fullResponse);

              // Handle year filter commands
              _handleYearFilterFromResponse(text, fullResponse);
            },
            onError: (e) {
              chatNotifier.addErrorMessage(
                '⚠️ Something went wrong: ${e.toString()}',
              );
              setState(() => _isTyping = false);
            },
          );
    } catch (e) {
      chatNotifier.addErrorMessage('⚠️ Something went wrong: ${e.toString()}');
      setState(() => _isTyping = false);
    }
  }

  void _handleYearFilterFromResponse(String userText, String response) {
    // Simple heuristic: if user asked for a year range and response confirms it
    final yearPattern = RegExp(r'(\d{4})\s*[-–to]+\s*(\d{4})');
    final match = yearPattern.firstMatch(userText);
    if (match != null) {
      final yf = int.tryParse(match.group(1)!);
      final yt = int.tryParse(match.group(2)!);
      if (yf != null && yt != null && yf >= 1950 && yt <= 2030) {
        ref
            .read(_copilotChatProvider.notifier)
            .setYearFilter(yearFrom: yf, yearTo: yt);
        ref
            .read(copilotYearFilterProvider.notifier)
            .update(yearFrom: yf, yearTo: yt);
      }
    }
  }

  void _parseCrateFromResponse(String response) {
    // ── Extract track list from response ──
    final parsed = _extractTracksFromResponse(response);
    if (parsed.tracks.isEmpty) return;

    final crateName = parsed.name;
    final aiTracks = parsed.tracks;

    // Show searching status
    final chatNotifier = ref.read(_copilotChatProvider.notifier);
    chatNotifier.addStatusMessage(
      '🔍 Searching Soundcharts, Spotify, Apple Music & YouTube for ${aiTracks.length} tracks…',
    );

    // Search platforms in background
    _resolveTracksOnPlatforms(crateName, aiTracks);
  }

  ({
    String name,
    List<({String title, String artist, int bpm, String key})> tracks,
  })
  _extractTracksFromResponse(String response) {
    var tracks = <({String title, String artist, int bpm, String key})>[];
    var crateName = 'AI Set';

    // Try 1: Parse ```crate JSON block
    final crateRegex = RegExp(r'```crate\s*\n([\s\S]*?)\n```');
    final jsonMatch = crateRegex.firstMatch(response);
    if (jsonMatch != null) {
      try {
        final data = jsonDecode(jsonMatch.group(1)!) as Map<String, dynamic>;
        crateName = data['name'] as String? ?? 'AI Set';
        final list = data['tracks'] as List? ?? [];
        for (final t in list) {
          if (t is Map) {
            final title = t['title']?.toString() ?? '';
            final artist = t['artist']?.toString() ?? '';
            final bpm = (t['bpm'] as num?)?.toInt() ?? 0;
            final key = t['key']?.toString() ?? '';
            if (title.isNotEmpty) {
              tracks.add((title: title, artist: artist, bpm: bpm, key: key));
            }
          }
        }
      } catch (_) {
        // intentional: JSON parse of the ```crate block may fail for any AI
        // response that isn't valid JSON; the caller falls through to Try 2
        // (numbered-list regex), so this is expected graceful degradation.
      }
    }

    // Try 2: Parse numbered list
    if (tracks.isEmpty) {
      final lineRegex = RegExp(
        r'^\d+[\.\)]\s+(.+?)\s*[-–—]\s+(.+?)(?:\s*[\(\[](.+?)[\)\]])?(?:\s*[\(\[].*?[\)\]])*\s*$',
        multiLine: true,
      );
      for (final m in lineRegex.allMatches(response)) {
        final part1 = m.group(1)?.trim().replaceAll('"', '') ?? '';
        var part2 = m.group(2)?.trim() ?? '';
        // Strip trailing parenthetical from title
        part2 = part2.replaceAll(RegExp(r'\s*[\(\[].*'), '');
        final meta = m.group(3) ?? '';
        final bpmMatch = RegExp(
          r'(\d+)\s*BPM',
          caseSensitive: false,
        ).firstMatch(meta);
        final keyMatch = RegExp(
          r'(\d{1,2}[AB])',
          caseSensitive: false,
        ).firstMatch(meta);
        if (part1.isNotEmpty && part2.isNotEmpty) {
          tracks.add((
            title: part2,
            artist: part1,
            bpm: int.tryParse(bpmMatch?.group(1) ?? '') ?? 0,
            key: keyMatch?.group(1) ?? '',
          ));
        }
      }

      // Fallback: "N. "Title" by Artist"
      if (tracks.isEmpty) {
        final byRegex = RegExp(
          r'^\d+[\.\)]\s+"?(.+?)"?\s+by\s+(.+?)(?:\s*[\(\[].*)?$',
          multiLine: true,
        );
        for (final m in byRegex.allMatches(response)) {
          final title = m.group(1)?.trim() ?? '';
          final artist = m.group(2)?.trim() ?? '';
          if (title.isNotEmpty && artist.isNotEmpty) {
            tracks.add((title: title, artist: artist, bpm: 0, key: ''));
          }
        }
      }

      final history = ref.read(_copilotChatProvider).history;
      final userMsgs = history.where((m) => m['role'] == 'user');
      final userMsg = userMsgs.isNotEmpty
          ? (userMsgs.last['content'] ?? '')
          : '';
      if (userMsg.length > 5) {
        crateName = userMsg.length > 40
            ? '${userMsg.substring(0, 40)}...'
            : userMsg;
      }
    }

    return (name: crateName, tracks: tracks);
  }

  PlatformTrackResult? _bestPlatformResolution(
    List<PlatformTrackResult> hits,
    String title,
    String artist,
  ) {
    if (hits.isEmpty) return null;
    final scored =
        hits
            .map(
              (hit) => (hit: hit, score: _resolutionScore(hit, title, artist)),
            )
            .where((entry) => entry.score > 0)
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));
    return scored.isEmpty ? hits.first : scored.first.hit;
  }

  int _resolutionScore(PlatformTrackResult hit, String title, String artist) {
    final wantedTitle = _matchText(title);
    final wantedArtist = _matchText(artist);
    final hitTitle = _matchText(hit.title);
    final hitArtist = _matchText(hit.artist);
    var score = 0;

    if (wantedTitle.isNotEmpty) {
      if (hitTitle == wantedTitle) {
        score += 100;
      } else if (hitTitle.contains(wantedTitle) ||
          wantedTitle.contains(hitTitle)) {
        score += 55;
      }
    }

    if (wantedArtist.isNotEmpty) {
      if (hitArtist == wantedArtist) {
        score += 80;
      } else if (hitArtist.contains(wantedArtist) ||
          wantedArtist.contains(hitArtist)) {
        score += 40;
      }
    }

    if (hit.spotifyUrl != null) score += 8;
    if (hit.appleUrl != null) score += 8;
    if (hit.youtubeUrl != null) score += 4;
    if (hit.soundchartsUrl != null) score += 4;
    score += (hit.popularity / 20).round();
    return score;
  }

  String _matchText(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\(.*?\)'), ' ')
      .replaceAll(RegExp(r'\[.*?\]'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Search all live providers for each AI track and store resolved setlist links.
  Future<void> _resolveTracksOnPlatforms(
    String crateName,
    List<({String title, String artist, int bpm, String key})> aiTracks,
  ) async {
    final platformSearch = PlatformSearchService();
    final chatNotifier = ref.read(_copilotChatProvider.notifier);
    final resolvedTracks = <AiCrateTrack>[];
    int found = 0;

    for (var i = 0; i < aiTracks.length; i++) {
      final ai = aiTracks[i];

      final hits = await platformSearch.search(
        '${ai.artist} ${ai.title}',
        limit: 8,
      );
      final hit = _bestPlatformResolution(hits, ai.title, ai.artist);

      final resolved =
          hit != null &&
          (hit.spotifyUrl != null ||
              hit.appleUrl != null ||
              hit.youtubeUrl != null ||
              hit.soundchartsUrl != null);
      if (resolved) found++;

      resolvedTracks.add(
        AiCrateTrack(
          title: ai.title,
          artist: ai.artist,
          bpm: ai.bpm,
          key: ai.key,
          spotifyUrl: hit?.spotifyUrl,
          appleUrl: hit?.appleUrl,
          youtubeUrl: hit?.youtubeUrl,
          soundchartsUrl: hit?.soundchartsUrl,
          soundchartsSource: hit?.soundchartsSource,
          soundchartsRegion: hit?.soundchartsRegion,
          artworkUrl: hit?.artworkUrl,
          resolved: resolved,
        ),
      );

      // Update progress every 3 tracks
      if ((i + 1) % 3 == 0 && mounted) {
        chatNotifier.updateLastStatusMessage(
          '🔍 Found $found/${i + 1} tracks across Soundcharts, Spotify, Apple Music & YouTube… (${aiTracks.length - i - 1} remaining)',
        );
      }
    }

    // Store the AI setlist
    ref.read(aiCrateProvider.notifier).setCrate(crateName, resolvedTracks);

    if (!mounted) return;

    final missing = aiTracks.length - found;
    chatNotifier.addStatusMessage(
      '🎧 Setlist "$crateName" ready — $found/${aiTracks.length} tracks found with platform/source links'
      '${missing > 0 ? '\n⚠️ $missing tracks could not be found on any platform' : ''}',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🎧 "$crateName" — $found tracks with source links'),
        backgroundColor: AppTheme.violet,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'View Setlist',
          textColor: Colors.white,
          onPressed: () => ref
              .read(workspaceControllerProvider.notifier)
              .setSection(AppSection.savedCrates),
        ),
      ),
    );

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        ref
            .read(workspaceControllerProvider.notifier)
            .setSection(AppSection.savedCrates);
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }
}
