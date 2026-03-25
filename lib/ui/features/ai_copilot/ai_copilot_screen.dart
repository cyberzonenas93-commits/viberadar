import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class AiCopilotScreen extends StatefulWidget {
  const AiCopilotScreen({super.key});
  @override
  State<AiCopilotScreen> createState() => _AiCopilotScreenState();
}

class _AiCopilotScreenState extends State<AiCopilotScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<({bool isUser, String text})> _messages = [
    (isUser: false, text: 'Hey DJ! I\'m your Vibe Radar AI Copilot. Ask me anything — trending tracks, set recommendations, harmonic mixing advice, or regional music intel.'),
  ];
  bool _isTyping = false;

  static const _suggestions = [
    'What\'s trending in Ghana right now?',
    'Build me an Afrobeats set for a 2am crowd',
    'Which tracks mix well with Burna Boy Last Last?',
    'Top Amapiano tracks from South Africa this month',
  ];

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    setState(() {
      _messages.add((isUser: true, text: text));
      _isTyping = true;
    });
    _controller.clear();
    await Future.delayed(const Duration(milliseconds: 1200));
    setState(() {
      _isTyping = false;
      _messages.add((isUser: false, text: 'Great question! Based on current trend data, I\'d recommend starting with high-energy Afrobeats around 95–105 BPM in compatible Camelot keys. I\'ll need API access to give you live recommendations — connect your API keys in Settings to unlock full AI Copilot capabilities.'));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: AppTheme.violet, size: 24),
              const SizedBox(width: 10),
              Text('AI Copilot', style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: AppTheme.edge, borderRadius: BorderRadius.circular(8)),
                child: const Text('GPT-5 · Connect in Settings', style: TextStyle(color: Color(0xFF9099B8), fontSize: 11)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
            itemCount: _messages.length + (_isTyping ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == _messages.length) {
                return _TypingIndicator();
              }
              final m = _messages[i];
              return _MessageBubble(isUser: m.isUser, text: m.text);
            },
          ),
        ),
        if (!_isTyping)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _suggestions.map((s) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(s, style: const TextStyle(fontSize: 11, color: Color(0xFF9099B8))),
                    backgroundColor: AppTheme.edge,
                    side: BorderSide.none,
                    onPressed: () => _send(s),
                  ),
                )).toList(),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  onSubmitted: _send,
                  decoration: InputDecoration(
                    hintText: 'Ask about trends, mixes, regions...',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.edge)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () => _send(_controller.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.violet,
                  padding: const EdgeInsets.all(14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Icon(Icons.send_rounded, size: 20),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final bool isUser;
  final String text;
  const _MessageBubble({required this.isUser, required this.text});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.6),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUser ? AppTheme.violet.withOpacity(0.25) : AppTheme.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isUser ? AppTheme.violet.withOpacity(0.4) : AppTheme.edge),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white, height: 1.5, fontSize: 13)),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.edge),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dot(delay: 0), SizedBox(width: 4),
            _Dot(delay: 150), SizedBox(width: 4),
            _Dot(delay: 300),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final int delay;
  const _Dot({required this.delay});
  @override
  Widget build(BuildContext context) {
    return Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppTheme.violet, shape: BoxShape.circle));
  }
}
