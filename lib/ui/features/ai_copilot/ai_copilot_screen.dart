import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/track.dart';
import '../../../providers/app_state.dart';
import '../../../providers/library_provider.dart';
import '../../../services/ai_copilot_service.dart';

// Exposed so parent shell can update year filter state from AI commands.
// Riverpod 3.x: StateProvider removed → NotifierProvider with same .state API.
class _CopilotYearFilterNotifier
    extends Notifier<({int? yearFrom, int? yearTo})> {
  @override
  ({int? yearFrom, int? yearTo}) build() => (yearFrom: null, yearTo: null);

  /// Update the year filter from outside the notifier.
  void update({required int? yearFrom, required int? yearTo}) {
    state = (yearFrom: yearFrom, yearTo: yearTo);
  }
}

final copilotYearFilterProvider = NotifierProvider<_CopilotYearFilterNotifier,
    ({int? yearFrom, int? yearTo})>(_CopilotYearFilterNotifier.new);

final _aiServiceProvider =
    Provider<AiCopilotService>((_) => AiCopilotService());

class AiCopilotScreen extends ConsumerStatefulWidget {
  const AiCopilotScreen({super.key});
  @override
  ConsumerState<AiCopilotScreen> createState() =>
      _AiCopilotScreenState();
}

class _AiCopilotScreenState extends ConsumerState<AiCopilotScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _apiKeyController = TextEditingController();
  final List<Map<String, String>> _history = [];
  final List<({bool isUser, String text})> _messages = [
    (
      isUser: false,
      text:
          'Hey DJ! I\'m your Vibe Radar AI Copilot powered by GPT-4.1. '
          'Ask me anything — trending tracks, set recommendations, '
          'harmonic mixing advice, or regional music intel.',
    ),
  ];
  bool _isTyping = false;
  bool _showSettings = false;
  String? _apiKey;
  String _model = 'gpt-5.4';

  // Year range context passed to GPT
  int? _yearFrom;
  int? _yearTo;

  static const _suggestions = [
    'What\'s trending in West Africa right now?',
    'Build me an Afrobeats set for a 2am crowd',
    'Which tracks mix well with Burna Boy Last Last?',
    'Top Amapiano picks from South Africa this month',
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
      const validModels = ['gpt-5.4', 'gpt-4.1', 'gpt-4o', 'gpt-4o-mini'];
      setState(() {
        _apiKey = key;
        _model = validModels.contains(model) ? model : 'gpt-5.4';
        if (key != null) _apiKeyController.text = key;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = _apiKey != null && _apiKey!.isNotEmpty;

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
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
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
                        boxShadow: [
                          BoxShadow(
                            color: (connected ? AppTheme.lime : AppTheme.amber)
                                .withValues(alpha: 0.4),
                            blurRadius: 6,
                          ),
                        ],
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
                    _showSettings ? Icons.close_rounded : Icons.settings_rounded,
                    color: _showSettings ? AppTheme.violet : AppTheme.textTertiary,
                    size: 20,
                  ),
                ),
              ),
            ),
          ]),
        ),

        // Settings panel
        if (_showSettings)
          Padding(
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
                            borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.5)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.5)),
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
                      border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
                    ),
                    child: DropdownButton<String>(
                      value: _model,
                      dropdownColor: AppTheme.panelRaised,
                      style: const TextStyle(
                          color: AppTheme.textPrimary, fontSize: 12),
                      underline: const SizedBox(),
                      isExpanded: true,
                      items: [
                        'gpt-5.4',
                        'gpt-4.1',
                        'gpt-4o',
                        'gpt-4o-mini',
                      ]
                          .map((m) => DropdownMenuItem(
                              value: m, child: Text(m)))
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
          ),

        if (!connected && !_showSettings)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.amber.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.amber.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                Icon(Icons.key_rounded, color: AppTheme.amber.withValues(alpha: 0.7), size: 16),
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  child: const Text('Add Key', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ),

        // Active year filter indicator
        if (_yearFrom != null || _yearTo != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 4, 28, 0),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.cyan.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AppTheme.cyan.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.date_range_rounded,
                    color: AppTheme.cyan, size: 12),
                const SizedBox(width: 6),
                Text(
                  'Year filter: ${_yearFrom ?? "any"} – ${_yearTo ?? "any"}',
                  style: const TextStyle(color: AppTheme.cyan, fontSize: 11),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _yearFrom = null;
                      _yearTo = null;
                    });
                    ref.read(copilotYearFilterProvider.notifier).update(yearFrom: null, yearTo: null);
                  },
                  child: const Icon(Icons.close,
                      color: AppTheme.cyan, size: 12),
                ),
              ]),
            ),
          ),

        const SizedBox(height: 8),
        Divider(color: AppTheme.edge.withValues(alpha: 0.4), height: 1),

        // Messages
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 8),
            itemCount: _messages.length + (_isTyping ? 1 : 0),
            itemBuilder: (ctx, i) {
              if (i == _messages.length) {
                return const _TypingIndicator();
              }
              final msg = _messages[i];
              return _ChatBubble(isUser: msg.isUser, text: msg.text);
            },
          ),
        ),

        // Suggestions
        if (_messages.length == 1)
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 28),
              itemCount: _suggestions.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) => GestureDetector(
                onTap: () => _send(_suggestions[i]),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.violet.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.violet.withValues(alpha: 0.2)),
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
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                onSubmitted: _send,
                decoration: InputDecoration(
                  hintText: 'Ask about trends, mixing tips, set ideas…',
                  hintStyle: const TextStyle(color: AppTheme.textTertiary, fontSize: 13),
                  filled: true,
                  fillColor: AppTheme.panelRaised,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.5)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.5)),
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
                  boxShadow: _isTyping
                      ? null
                      : [
                          BoxShadow(
                            color: AppTheme.violet.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: _isTyping
                    ? const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
              ),
            ),
          ]),
        ),
      ],
    );
  }

  /// Build track context from current radar data for the AI.
  /// Includes year, genre, and respects active year filter.
  List<Map<String, String>> _getTrackContext() {
    final tracksAsync = ref.read(trackStreamProvider);
    final allTracks = tracksAsync.value ?? <Track>[];
    var filtered = [...allTracks];

    // Apply year filter if active
    if (_yearFrom != null) {
      filtered =
          filtered.where((t) => t.createdAt.year >= _yearFrom!).toList();
    }
    if (_yearTo != null) {
      filtered =
          filtered.where((t) => t.createdAt.year <= _yearTo!).toList();
    }

    filtered.sort((a, b) => b.trendScore.compareTo(a.trendScore));

    return filtered.take(80).map((t) => {
      'title': t.title,
      'artist': t.artist,
      'bpm': t.bpm.toString(),
      'key': t.keySignature,
      'genre': t.genre,
      'year': t.createdAt.year.toString(),
    }).toList();
  }

  /// Parse crate blocks from AI response and save them.
  void _parseCrateFromResponse(String response) {
    final crateRegex = RegExp(r'```crate\s*\n([\s\S]*?)\n```');
    final match = crateRegex.firstMatch(response);
    if (match == null) return;

    try {
      final jsonStr = match.group(1)!;
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final crateName = data['name'] as String? ?? 'AI Crate';
      final tracks = data['tracks'] as List? ?? [];

      // Create the crate
      ref.read(crateProvider.notifier).createCrate(crateName);

      // Show snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Created crate "$crateName" with ${tracks.length} tracks'),
            backgroundColor: AppTheme.violet,
            action: SnackBarAction(
              label: 'View',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (_) {
      // JSON parse failed — that's OK, just show the text
    }
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty || _isTyping) return;
    setState(() {
      _messages.add((isUser: true, text: text));
      _isTyping = true;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final trackContext = _getTrackContext();
      final svc = ref.read(_aiServiceProvider);

      // Use structured command parsing so we can route the intent.
      final command = await svc.parseCommand(
        text,
        trackContext,
        yearFrom: _yearFrom,
        yearTo: _yearTo,
      );

      final response = command.naturalResponse;

      _history.add({'role': 'user', 'content': text});
      _history.add({'role': 'assistant', 'content': response});

      // Route structured intent to UI actions.
      _handleCopilotCommand(command);

      // Also parse any inline crate JSON blocks.
      _parseCrateFromResponse(response);

      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add((isUser: false, text: response));
        });
      }
    } catch (e) {
      final errMsg = _friendlyError(e.toString());
      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add((isUser: false, text: errMsg));
        });
      }
    } finally {
      if (mounted) _scrollToBottom();
    }
  }

  /// Routes a structured [AiCopilotCommand] to the appropriate UI action.
  void _handleCopilotCommand(AiCopilotCommand command) {
    if (!mounted) return;

    switch (command.intent) {
      case CopilotIntent.setReleaseRange:
        final yf = command.params['yearFrom'] as int?;
        final yt = command.params['yearTo'] as int?;
        if (yf != null || yt != null) {
          setState(() {
            _yearFrom = yf ?? _yearFrom;
            _yearTo = yt ?? _yearTo;
          });
          // Propagate to shared provider so other screens can react.
          ref.read(copilotYearFilterProvider.notifier).update(yearFrom: _yearFrom, yearTo: _yearTo);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Year filter set: ${_yearFrom ?? "any"} – ${_yearTo ?? "any"}'),
            backgroundColor: AppTheme.violet,
          ));
        }

      case CopilotIntent.buildSet:
        // The crate will be created from the ```crate``` block in the response
        // via _parseCrateFromResponse. Show a toast confirming the intent.
        final genre = command.params['genre'] as String? ?? '';
        final yf = command.params['yearFrom'] as int?;
        final yt = command.params['yearTo'] as int?;
        if (yf != null || yt != null) {
          setState(() {
            _yearFrom = yf ?? _yearFrom;
            _yearTo = yt ?? _yearTo;
          });
          ref.read(copilotYearFilterProvider.notifier).update(yearFrom: _yearFrom, yearTo: _yearTo);
        }
        if (genre.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Building $genre set${yf != null ? " from $yf" : ""}${yt != null ? "–$yt" : ""}…'),
            backgroundColor: AppTheme.violet,
          ));
        }

      case CopilotIntent.findArtist:
        final artist = command.params['artist'] as String? ?? '';
        if (artist.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Tip: Use the Artists screen to find "$artist"'),
            backgroundColor: AppTheme.cyan,
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ));
        }

      case CopilotIntent.cleanDuplicates:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tip: Head to the Duplicates screen to clean up'),
          backgroundColor: AppTheme.cyan,
        ));

      case CopilotIntent.createCrate:
      case CopilotIntent.matchLibrary:
      case CopilotIntent.general:
        // General intent — response text is all that's needed.
        break;
    }
  }

  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('connection') ||
        lower.contains('host lookup')) {
      return '⚠️ Network error — check your internet connection and try again.';
    }
    if (lower.contains('invalid_api_key') || lower.contains('401')) {
      return '⚠️ Invalid API key. Open Settings and re-enter your OpenAI key.';
    }
    if (lower.contains('model_not_found') ||
        lower.contains('does not exist') ||
        lower.contains('invalid model')) {
      return '⚠️ Invalid model "$_model". Open Settings and choose a different model.';
    }
    if (lower.contains('rate_limit') || lower.contains('429')) {
      return '⚠️ Rate limit reached. Wait a moment and try again.';
    }
    if (lower.contains('insufficient_quota') || lower.contains('402')) {
      return '⚠️ OpenAI quota exceeded. Check your billing at platform.openai.com.';
    }
    return '⚠️ Something went wrong: $raw';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }
}

class _ChatBubble extends StatelessWidget {
  final bool isUser;
  final String text;
  const _ChatBubble({required this.isUser, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.violet, AppTheme.pink],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 14),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser
                    ? AppTheme.violet
                    : AppTheme.panelRaised,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: isUser
                    ? null
                    : Border.all(color: AppTheme.edge.withValues(alpha: 0.4)),
                boxShadow: isUser
                    ? [
                        BoxShadow(
                          color: AppTheme.violet.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: SelectableText(
                text,
                style: TextStyle(
                  color: isUser
                      ? Colors.white
                      : AppTheme.textPrimary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.violet, AppTheme.pink],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.auto_awesome_rounded,
              color: Colors.white, size: 14),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.panelRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.edge.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DotPulse(delay: 0),
              const SizedBox(width: 4),
              _DotPulse(delay: 150),
              const SizedBox(width: 4),
              _DotPulse(delay: 300),
            ],
          ),
        ),
      ]),
    );
  }
}

class _DotPulse extends StatefulWidget {
  final int delay;
  const _DotPulse({required this.delay});

  @override
  State<_DotPulse> createState() => _DotPulseState();
}

class _DotPulseState extends State<_DotPulse> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, child) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: AppTheme.violet.withValues(alpha: _animation.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
