import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/ai_copilot_provider.dart';
import '../../../services/ai_copilot_service.dart';

class AiCopilotScreen extends ConsumerStatefulWidget {
  const AiCopilotScreen({super.key});

  @override
  ConsumerState<AiCopilotScreen> createState() => _AiCopilotScreenState();
}

class _AiCopilotScreenState extends ConsumerState<AiCopilotScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _hasText = false;

  static const _suggestions = [
    'What\'s trending in Ghana?',
    'Build me an Afrobeats set for 2am',
    'Which tracks mix with Last Last?',
    'Top Amapiano this month',
    'Harmonic mixing tips for Amapiano',
  ];

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
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

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    _controller.clear();
    final notifier = ref.read(chatHistoryProvider.notifier);
    _scrollToBottom();
    await notifier.sendMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final messages = ref.watch(chatHistoryProvider);
    final notifier = ref.read(chatHistoryProvider.notifier);
    final isLoading = notifier.isLoading;
    final showSuggestions = messages.length <= 1;

    return Column(
      children: [
        // Top bar
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 12),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: AppTheme.violet, size: 22),
              const SizedBox(width: 10),
              Text(
                'AI Copilot',
                style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  // TODO: open settings
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.edge,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'GPT-5 · Simulation Mode',
                    style: TextStyle(color: Color(0xFF9099B8), fontSize: 11),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                color: const Color(0xFF9099B8),
                tooltip: 'Clear chat',
                onPressed: () => ref.read(chatHistoryProvider.notifier).clear(),
              ),
            ],
          ),
        ),

        // Chat area
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(28, 4, 28, 12),
            itemCount: messages.length + (isLoading ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == messages.length) {
                return const _LoadingBubble();
              }
              return _MessageBubble(message: messages[i]);
            },
          ),
        ),

        // Suggestion chips
        if (showSuggestions && !isLoading)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _suggestions
                    .map((s) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            label: Text(
                              s,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF9099B8),
                              ),
                            ),
                            backgroundColor: AppTheme.edge,
                            side: BorderSide.none,
                            onPressed: () => _send(s),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),

        // Input row
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 4, 28, 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.attach_file_rounded, size: 18),
                color: const Color(0xFF9099B8),
                onPressed: null, // no-op for now
                tooltip: 'Attach context',
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLines: 3,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  decoration: InputDecoration(
                    hintText: 'Ask about trends, mixes, regions...',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
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
                      borderSide: const BorderSide(color: AppTheme.violet, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              AnimatedOpacity(
                opacity: _hasText ? 1.0 : 0.4,
                duration: const Duration(milliseconds: 150),
                child: IconButton(
                  icon: const Icon(Icons.send_rounded, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.violet,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _hasText ? () => _send(_controller.text) : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final AiCopilotMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final timeStr = DateFormat('h:mm a').format(message.timestamp);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.65,
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment:
                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isUser)
                const Padding(
                  padding: EdgeInsets.only(left: 14, bottom: 4),
                  child: Text(
                    'Vibe Radar AI',
                    style: TextStyle(
                      color: Color(0xFF9099B8),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isUser
                      ? AppTheme.violet.withOpacity(0.22)
                      : AppTheme.panel,
                  borderRadius: BorderRadius.circular(14),
                  border: isUser
                      ? Border.all(color: AppTheme.violet.withOpacity(0.4))
                      : null,
                  boxShadow: isUser
                      ? null
                      : const [
                          BoxShadow(
                            color: Color(0x18000000),
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          )
                        ],
                ),
                child: Stack(
                  children: [
                    // Violet left border for assistant
                    if (!isUser)
                      Positioned(
                        left: -14,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 3,
                          decoration: BoxDecoration(
                            color: AppTheme.violet,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    Text(
                      message.text,
                      style: const TextStyle(
                        color: Colors.white,
                        height: 1.55,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                  top: 4,
                  left: isUser ? 0 : 14,
                  right: isUser ? 4 : 0,
                ),
                child: Text(
                  timeStr,
                  style: const TextStyle(
                    color: Color(0xFF555E7A),
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingBubble extends StatefulWidget {
  const _LoadingBubble();

  @override
  State<_LoadingBubble> createState() => _LoadingBubbleState();
}

class _LoadingBubbleState extends State<_LoadingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.edge),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return AnimatedBuilder(
              animation: _anim,
              builder: (_, __) {
                final t = (_anim.value - i * 0.2).clamp(0.0, 1.0);
                final opacity = (0.3 + 0.7 * (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0));
                return Container(
                  margin: EdgeInsets.only(right: i < 2 ? 5 : 0),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppTheme.violet.withOpacity(opacity),
                    shape: BoxShape.circle,
                  ),
                );
              },
            );
          }),
        ),
      ),
    );
  }
}
