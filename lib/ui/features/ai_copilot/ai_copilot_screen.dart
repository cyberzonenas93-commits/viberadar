import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/ai_copilot_service.dart';

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
          'Hey DJ! I\'m your Vibe Radar AI Copilot powered by gpt-5.4. '
          'Ask me anything — trending tracks, set recommendations, '
          'harmonic mixing advice, or regional music intel.',
    ),
  ];
  bool _isTyping = false;
  bool _showSettings = false;
  String? _apiKey;
  String _model = 'gpt-5.4';

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
      setState(() {
        _apiKey = key;
        _model = model;
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
    final connected =
        _apiKey != null && _apiKey!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI Copilot',
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(color: Colors.white)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.violet.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(_model,
                          style: const TextStyle(
                              color: AppTheme.violet,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: connected
                            ? AppTheme.lime
                            : AppTheme.pink,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      connected ? 'Connected' : 'Simulation mode',
                      style: const TextStyle(
                          color: Color(0xFF9099B8), fontSize: 11),
                    ),
                  ]),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                _showSettings
                    ? Icons.close
                    : Icons.settings_rounded,
                color: const Color(0xFF9099B8),
              ),
              onPressed: () =>
                  setState(() => _showSettings = !_showSettings),
            ),
          ]),
        ),

        // Settings panel
        if (_showSettings)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.edge),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('OpenAI API Key',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _apiKeyController,
                        obscureText: true,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'sk-…',
                          hintStyle: const TextStyle(
                              color: Color(0xFF9099B8)),
                          filled: true,
                          fillColor: AppTheme.panelRaised,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: AppTheme.edge),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: AppTheme.edge),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () async {
                        final key =
                            _apiKeyController.text.trim();
                        await ref
                            .read(_aiServiceProvider)
                            .setApiKey(key);
                        if (mounted) {
                          setState(() {
                            _apiKey = key;
                            _showSettings = false;
                          });
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.violet,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                      ),
                      child: const Text('Save'),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  const Text('Model',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  DropdownButton<String>(
                    value: _model,
                    dropdownColor: AppTheme.panel,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12),
                    underline: const SizedBox(),
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
                        await ref
                            .read(_aiServiceProvider)
                            .setModel(v);
                        if (mounted) setState(() => _model = v);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

        const SizedBox(height: 16),
        const Divider(color: AppTheme.edge, height: 1),

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
              return _ChatBubble(
                  isUser: msg.isUser, text: msg.text);
            },
          ),
        ),

        // Suggestions
        if (_messages.length == 1)
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: 28),
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: 8),
              itemBuilder: (ctx, i) => GestureDetector(
                onTap: () => _send(_suggestions[i]),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.panel,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.edge),
                  ),
                  child: Text(_suggestions[i],
                      style: const TextStyle(
                          color: Color(0xFF9099B8),
                          fontSize: 11)),
                ),
              ),
            ),
          ),

        // Input bar
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 20),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _controller,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13),
                onSubmitted: _send,
                decoration: InputDecoration(
                  hintText:
                      'Ask about trends, mixing tips, set ideas…',
                  hintStyle: const TextStyle(
                      color: Color(0xFF9099B8), fontSize: 13),
                  filled: true,
                  fillColor: AppTheme.panel,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppTheme.edge),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppTheme.edge),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _isTyping
                  ? null
                  : () => _send(_controller.text),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _isTyping
                      ? AppTheme.edge
                      : AppTheme.violet,
                  borderRadius: BorderRadius.circular(12),
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
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 18),
              ),
            ),
          ]),
        ),
      ],
    );
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty || _isTyping) return;
    setState(() {
      _messages.add((isUser: true, text: text));
      _isTyping = true;
    });
    _controller.clear();
    _scrollToBottom();

    final response =
        await ref.read(_aiServiceProvider).chat(_history, text);
    _history.add({'role': 'user', 'content': text});
    _history.add({'role': 'assistant', 'content': response});

    if (mounted) {
      setState(() {
        _isTyping = false;
        _messages.add((isUser: false, text: response));
      });
      _scrollToBottom();
    }
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppTheme.violet.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: AppTheme.violet, size: 14),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? AppTheme.violet : AppTheme.panel,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft:
                      Radius.circular(isUser ? 16 : 4),
                  bottomRight:
                      Radius.circular(isUser ? 4 : 16),
                ),
                border: isUser
                    ? null
                    : Border.all(color: AppTheme.edge),
              ),
              child: Text(text,
                  style: TextStyle(
                    color: isUser
                        ? Colors.white
                        : const Color(0xFFCDD3F0),
                    fontSize: 13,
                    height: 1.5,
                  )),
            ),
          ),
          if (isUser) const SizedBox(width: 38),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppTheme.violet.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.auto_awesome_rounded,
              color: AppTheme.violet, size: 14),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.edge),
          ),
          child: const Text('···',
              style: TextStyle(
                  color: AppTheme.cyan,
                  fontSize: 18,
                  letterSpacing: 4)),
        ),
      ]),
    );
  }
}
