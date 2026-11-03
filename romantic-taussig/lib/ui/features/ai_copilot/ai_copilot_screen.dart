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
import '../../../services/spotify_artist_service.dart';
import '../../../services/apple_music_artist_service.dart';
import '../../../services/youtube_search_service.dart';

// ── Persistent chat state ─────────────────────────────────────────────────────

class _CopilotChatState {
  final List<Map<String, String>> history;
  final List<({bool isUser, String text, bool isStreaming})> messages;
  final int? yearFrom;
  final int? yearTo;

  const _CopilotChatState({
    this.history = const [],
    this.messages = const [],
    this.yearFrom,
    this.yearTo,
  });

  _CopilotChatState copyWith({
    List<Map<String, String>>? history,
    List<({bool isUser, String text, bool isStreaming})>? messages,
    int? yearFrom,
    int? yearTo,
    bool clearYearFrom = false,
    bool clearYearTo = false,
  }) {
    return _CopilotChatState(
      history: history ?? this.history,
      messages: messages ?? this.messages,
      yearFrom: clearYearFrom ? null : (yearFrom ?? this.yearFrom),
      yearTo: clearYearTo ? null : (yearTo ?? this.yearTo),
    );
  }
}

class _CopilotChatNotifier extends Notifier<_CopilotChatState> {
  @override
  _CopilotChatState build() => _CopilotChatState(
        messages: [
          (
            isUser: false,
            text: 'Hey DJ! I\'m your VibeRadar AI Copilot powered by GPT-5.4. '
                'I have access to the entire Apple Music, Spotify, YouTube, and Billboard '
                'catalogue. Ask me anything — build sets, find tracks, harmonic mixing advice, '
                'or regional music intel.',
            isStreaming: false,
          ),
        ],
      );

  void addUserMessage(String text) {
    state = state.copyWith(
      messages: [
        ...state.messages,
        (isUser: true, text: text, isStreaming: false),
      ],
      history: [
        ...state.history,
        {'role': 'user', 'content': text},
      ],
    );
  }

  void addStreamingMessage() {
    state = state.copyWith(
      messages: [
        ...state.messages,
        (isUser: false, text: '', isStreaming: true),
      ],
    );
  }

  void updateStreamingMessage(String text) {
    final msgs = [...state.messages];
    if (msgs.isNotEmpty && msgs.last.isStreaming) {
      msgs[msgs.length - 1] = (isUser: false, text: text, isStreaming: true);
      state = state.copyWith(messages: msgs);
    }
  }

  void finalizeStreamingMessage(String text) {
    final msgs = [...state.messages];
    if (msgs.isNotEmpty && msgs.last.isStreaming) {
      msgs[msgs.length - 1] = (isUser: false, text: text, isStreaming: false);
      state = state.copyWith(
        messages: msgs,
        history: [
          ...state.history,
          {'role': 'assistant', 'content': text},
        ],
      );
    }
  }

  void addErrorMessage(String text) {
    final msgs = [...state.messages];
    // Remove streaming placeholder if present
    if (msgs.isNotEmpty && msgs.last.isStreaming) {
      msgs[msgs.length - 1] = (isUser: false, text: text, isStreaming: false);
    } else {
      msgs.add((isUser: false, text: text, isStreaming: false));
    }
    state = state.copyWith(messages: msgs);
  }

  void setYearFilter({int? yearFrom, int? yearTo}) {
    state = state.copyWith(
      yearFrom: yearFrom,
      yearTo: yearTo,
      clearYearFrom: yearFrom == null,
      clearYearTo: yearTo == null,
    );
  }

  void addStatusMessage(String text) {
    state = state.copyWith(
      messages: [
        ...state.messages,
        (isUser: false, text: text, isStreaming: false),
      ],
    );
  }

  /// Update the last non-user message (used for progress updates).
  void updateLastStatusMessage(String text) {
    final msgs = [...state.messages];
    // Find last non-user message and update it
    for (var i = msgs.length - 1; i >= 0; i--) {
      if (!msgs[i].isUser) {
        msgs[i] = (isUser: false, text: text, isStreaming: false);
        state = state.copyWith(messages: msgs);
        return;
      }
    }
  }

  void clearChat() {
    state = build(); // Reset to initial state
  }
}

final _copilotChatProvider =
    NotifierProvider<_CopilotChatNotifier, _CopilotChatState>(
        _CopilotChatNotifier.new);

// ── Year filter provider (shared with other screens) ──────────────────────────

class _CopilotYearFilterNotifier
    extends Notifier<({int? yearFrom, int? yearTo})> {
  @override
  ({int? yearFrom, int? yearTo}) build() => (yearFrom: null, yearTo: null);

  void update({required int? yearFrom, required int? yearTo}) {
    state = (yearFrom: yearFrom, yearTo: yearTo);
  }
}

final copilotYearFilterProvider = NotifierProvider<_CopilotYearFilterNotifier,
    ({int? yearFrom, int? yearTo})>(_CopilotYearFilterNotifier.new);

final _aiServiceProvider =
    Provider<AiCopilotService>((_) => AiCopilotService());

// ── Screen ────────────────────────────────────────────────────────────────────

class AiCopilotScreen extends ConsumerStatefulWidget {
  const AiCopilotScreen({super.key});
  @override
  ConsumerState<AiCopilotScreen> createState() => _AiCopilotScreenState();
}

class _AiCopilotScreenState extends ConsumerState<AiCopilotScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _apiKeyController = TextEditingController();
  bool _isTyping = false;
  bool _showSettings = false;
  String? _apiKey;
  String _model = 'gpt-5.4';
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
    final key = await svc.getApiKey();
    final model = await svc.getModel();
    if (mounted) {
      setState(() {
        _apiKey = key;
        _model = model;
        if (key != null) _apiKeyController.text = key;
      });
    }
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = _apiKey != null && _apiKey!.isNotEmpty;
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
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.violet, AppTheme.pink],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI Copilot',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.violet.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(_model,
                          style: const TextStyle(
                              color: AppTheme.violet,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: connected ? AppTheme.lime : AppTheme.amber,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      connected ? 'Connected' : 'No API key',
                      style: TextStyle(
                        color: connected ? AppTheme.lime : AppTheme.amber,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
            // Clear chat button
            if (messages.length > 1)
              Tooltip(
                message: 'Clear chat',
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () =>
                        ref.read(_copilotChatProvider.notifier).clearChat(),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.delete_outline_rounded,
                          color: AppTheme.textTertiary, size: 20),
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
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
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
          ]),
        ),

        // Settings panel
        if (_showSettings) _buildSettingsPanel(),

        if (!connected && !_showSettings) _buildApiKeyBanner(),

        // Active year filter indicator
        if (chatState.yearFrom != null || chatState.yearTo != null)
          _buildYearFilterBar(chatState),

        const SizedBox(height: 8),
        Divider(color: AppTheme.edge.withValues(alpha: 0.4), height: 1),

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
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) => GestureDetector(
                onTap: () => _send(_suggestions[i]),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.violet.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppTheme.violet.withValues(alpha: 0.2)),
                  ),
                  child: Text(_suggestions[i],
                      style: const TextStyle(
                          color: AppTheme.violet,
                          fontSize: 11,
                          fontWeight: FontWeight.w500)),
                ),
              ),
            ),
          ),

        // Input bar
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 10, 28, 20),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _controller,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 13),
                onSubmitted: _send,
                decoration: InputDecoration(
                  hintText:
                      'Build a set, find tracks, ask anything about music…',
                  hintStyle: const TextStyle(
                      color: AppTheme.textTertiary, fontSize: 13),
                  filled: true,
                  fillColor: AppTheme.panelRaised,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: AppTheme.edge.withValues(alpha: 0.5)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: AppTheme.edge.withValues(alpha: 0.5)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.violet),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
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
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _isTyping
                    ? const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 18),
              ),
            ),
          ]),
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
        decoration: BoxDecoration(
          color: AppTheme.panelRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('OpenAI API Key',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _apiKeyController,
                  obscureText: true,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'sk-…',
                    hintStyle: const TextStyle(color: AppTheme.textTertiary),
                    filled: true,
                    fillColor: AppTheme.panel,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: AppTheme.edge.withValues(alpha: 0.5)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: AppTheme.edge.withValues(alpha: 0.5)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () async {
                  final key = _apiKeyController.text.trim();
                  await ref.read(_aiServiceProvider).setApiKey(key);
                  if (mounted) {
                    setState(() {
                      _apiKey = key;
                      _showSettings = false;
                    });
                  }
                },
                child: const Text('Save'),
              ),
            ]),
            const SizedBox(height: 12),
            const Text('Model',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppTheme.panel,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppTheme.edge.withValues(alpha: 0.5)),
              ),
              child: DropdownButton<String>(
                value: ['gpt-5.4', 'gpt-4.1', 'gpt-4o', 'gpt-4o-mini']
                        .contains(_model)
                    ? _model
                    : 'gpt-5.4',
                dropdownColor: AppTheme.panelRaised,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 12),
                underline: const SizedBox(),
                isExpanded: true,
                items: ['gpt-5.4', 'gpt-4.1', 'gpt-4o', 'gpt-4o-mini']
                    .map((m) =>
                        DropdownMenuItem(value: m, child: Text(m)))
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

  Widget _buildApiKeyBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.amber.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: AppTheme.amber.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Icon(Icons.key_rounded,
              color: AppTheme.amber.withValues(alpha: 0.7), size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Add your OpenAI API key in Settings to get live AI responses.',
              style: TextStyle(
                color: AppTheme.amber.withValues(alpha: 0.8),
                fontSize: 11,
              ),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _showSettings = true),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.amber,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
            ),
            child: const Text('Add Key',
                style:
                    TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ]),
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
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          const Icon(Icons.date_range_rounded,
              color: AppTheme.cyan, size: 12),
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
            child:
                const Icon(Icons.close, color: AppTheme.cyan, size: 12),
          ),
        ]),
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

    return filtered.take(80).map((t) => {
          'title': t.title,
          'artist': t.artist,
          'bpm': t.bpm.toString(),
          'key': t.keySignature,
          'genre': t.genre,
          'year': t.effectiveReleaseYear.toString(),
        }).toList();
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
              '⚠️ Something went wrong: ${e.toString()}');
          setState(() => _isTyping = false);
        },
      );
    } catch (e) {
      chatNotifier.addErrorMessage(
          '⚠️ Something went wrong: ${e.toString()}');
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
      '🔍 Searching Spotify & Apple Music for ${aiTracks.length} tracks…',
    );

    // Search platforms in background
    _resolveTracksOnPlatforms(crateName, aiTracks);
  }

  ({String name, List<({String title, String artist, int bpm, String key})> tracks})
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
            if (title.isNotEmpty) tracks.add((title: title, artist: artist, bpm: bpm, key: key));
          }
        }
      } catch (_) {}
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
        final bpmMatch = RegExp(r'(\d+)\s*BPM', caseSensitive: false).firstMatch(meta);
        final keyMatch = RegExp(r'(\d{1,2}[AB])', caseSensitive: false).firstMatch(meta);
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
        final byRegex = RegExp(r'^\d+[\.\)]\s+"?(.+?)"?\s+by\s+(.+?)(?:\s*[\(\[].*)?$', multiLine: true);
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
      final userMsg = userMsgs.isNotEmpty ? (userMsgs.last['content'] ?? '') : '';
      if (userMsg.length > 5) {
        crateName = userMsg.length > 40 ? '${userMsg.substring(0, 40)}...' : userMsg;
      }
    }

    return (name: crateName, tracks: tracks);
  }

  /// Clean query — strip feat., ft., parenthetical, brackets
  String _cleanQuery(String s) => s
      .replaceAll(RegExp(r'\(feat\.?[^)]*\)', caseSensitive: false), '')
      .replaceAll(RegExp(r'\(ft\.?[^)]*\)', caseSensitive: false), '')
      .replaceAll(RegExp(r'\(.*?\)'), '')
      .replaceAll(RegExp(r'\[.*?\]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Try multiple search strategies to find a track on Spotify
  Future<SpotifyTrackInfo?> _searchSpotify(SpotifyArtistService spotify, String title, String artist) async {
    final cleanTitle = _cleanQuery(title);
    final cleanArtist = _cleanQuery(artist);

    // Strategy 1: "artist title"
    var results = await spotify.searchTracks('$cleanArtist $cleanTitle', limit: 5).catchError((_) => <SpotifyTrackInfo>[]);
    if (results.isNotEmpty) return results.first;

    // Strategy 2: "title artist" (reversed)
    results = await spotify.searchTracks('$cleanTitle $cleanArtist', limit: 5).catchError((_) => <SpotifyTrackInfo>[]);
    if (results.isNotEmpty) return results.first;

    // Strategy 3: title only (for unique song names)
    if (cleanTitle.length > 4) {
      results = await spotify.searchTracks(cleanTitle, limit: 5).catchError((_) => <SpotifyTrackInfo>[]);
      if (results.isNotEmpty) return results.first;
    }

    return null;
  }

  /// Try multiple search strategies to find a track on Apple Music
  Future<AppleMusicTrack?> _searchApple(AppleMusicArtistService apple, String title, String artist) async {
    final cleanTitle = _cleanQuery(title);
    final cleanArtist = _cleanQuery(artist);

    var results = await apple.searchSongs('$cleanArtist $cleanTitle', limit: 5).catchError((_) => <AppleMusicTrack>[]);
    if (results.isNotEmpty) return results.first;

    results = await apple.searchSongs('$cleanTitle $cleanArtist', limit: 5).catchError((_) => <AppleMusicTrack>[]);
    if (results.isNotEmpty) return results.first;

    if (cleanTitle.length > 4) {
      results = await apple.searchSongs(cleanTitle, limit: 5).catchError((_) => <AppleMusicTrack>[]);
      if (results.isNotEmpty) return results.first;
    }

    return null;
  }

  /// Search Spotify + Apple Music for each AI track and store results
  Future<void> _resolveTracksOnPlatforms(
    String crateName,
    List<({String title, String artist, int bpm, String key})> aiTracks,
  ) async {
    final spotify = SpotifyArtistService();
    final apple = AppleMusicArtistService();
    final youtube = YoutubeSearchService();
    final chatNotifier = ref.read(_copilotChatProvider.notifier);
    final resolvedTracks = <AiCrateTrack>[];
    int found = 0;

    for (var i = 0; i < aiTracks.length; i++) {
      final ai = aiTracks[i];

      String? spotifyUrl;
      String? appleUrl;
      String? youtubeUrl;
      String? artworkUrl;

      // Search Spotify (multi-strategy)
      final spotifyHit = await _searchSpotify(spotify, ai.title, ai.artist);
      if (spotifyHit != null) {
        spotifyUrl = spotifyHit.spotifyUrl;
        artworkUrl = spotifyHit.albumArt;
      }

      // Search Apple Music (multi-strategy)
      final appleHit = await _searchApple(apple, ai.title, ai.artist);
      if (appleHit != null) {
        appleUrl = appleHit.appleUrl;
        artworkUrl ??= appleHit.artworkUrl;
      }

      // Search YouTube
      try {
        final ytResults = await youtube.searchMusic(
          '${ai.artist} ${ai.title}', limit: 1,
        ).catchError((_) => <YoutubeVideoResult>[]);
        if (ytResults.isNotEmpty) {
          youtubeUrl = ytResults.first.youtubeUrl;
          artworkUrl ??= ytResults.first.thumbnailUrl;
        }
      } catch (_) {}

      final resolved = spotifyUrl != null || appleUrl != null || youtubeUrl != null;
      if (resolved) found++;

      resolvedTracks.add(AiCrateTrack(
        title: ai.title,
        artist: ai.artist,
        bpm: ai.bpm,
        key: ai.key,
        spotifyUrl: spotifyUrl,
        appleUrl: appleUrl,
        youtubeUrl: youtubeUrl,
        artworkUrl: artworkUrl,
        resolved: resolved,
      ));

      // Update progress every 3 tracks
      if ((i + 1) % 3 == 0 && mounted) {
        chatNotifier.updateLastStatusMessage(
          '🔍 Found $found/${i + 1} tracks on Spotify, Apple Music & YouTube… (${aiTracks.length - i - 1} remaining)',
        );
      }
    }

    // Store the AI crate
    ref.read(aiCrateProvider.notifier).setCrate(crateName, resolvedTracks);

    if (!mounted) return;

    final missing = aiTracks.length - found;
    chatNotifier.addStatusMessage(
      '🎧 Crate "$crateName" ready — $found/${aiTracks.length} tracks found with playable links'
      '${missing > 0 ? '\n⚠️ $missing tracks could not be found on any platform' : ''}',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🎧 "$crateName" — $found tracks with play links'),
        backgroundColor: AppTheme.violet,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'View Crate',
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

// ── Chat bubble ─────────────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.isUser,
    required this.text,
    this.isStreaming = false,
  });

  final bool isUser;
  final String text;
  final bool isStreaming;

  /// Strip the ```crate ... ``` JSON block from display text.
  String get _displayText {
    if (isUser) return text;
    return text
        .replaceAll(RegExp(r'```crate\s*\n[\s\S]*?\n```'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final display = _displayText;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser
              ? AppTheme.violet.withValues(alpha: 0.15)
              : AppTheme.panelRaised,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isUser ? const Radius.circular(4) : null,
            bottomLeft: !isUser ? const Radius.circular(4) : null,
          ),
          border: Border.all(
            color: isUser
                ? AppTheme.violet.withValues(alpha: 0.3)
                : AppTheme.edge.withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (display.isEmpty && isStreaming)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.violet.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('Building your set…',
                      style: TextStyle(
                          color: AppTheme.violet.withValues(alpha: 0.6),
                          fontSize: 12,
                          fontStyle: FontStyle.italic)),
                ],
              )
            else
              SelectableText(
                display,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            if (isStreaming && display.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AppTheme.violet.withValues(alpha: 0.4),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('Generating…',
                        style: TextStyle(
                            color: AppTheme.textTertiary,
                            fontSize: 10,
                            fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
