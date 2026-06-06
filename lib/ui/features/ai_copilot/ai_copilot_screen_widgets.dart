part of 'ai_copilot_screen.dart';

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
    final borderRadius = BorderRadius.circular(AppTheme.rLg).copyWith(
      bottomRight: isUser ? const Radius.circular(4) : null,
      bottomLeft: !isUser ? const Radius.circular(4) : null,
    );
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: isUser
            ? BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.violet.withValues(alpha: 0.22),
                    AppTheme.violet.withValues(alpha: 0.12),
                  ],
                ),
                borderRadius: borderRadius,
                border: Border.all(
                  color: AppTheme.violet.withValues(alpha: 0.35),
                ),
              )
            : BoxDecoration(
                gradient: AppTheme.surfaceGradient,
                borderRadius: borderRadius,
                border: Border.all(color: AppTheme.hairline),
                boxShadow: AppTheme.ambientShadow,
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
                  Text(
                    'Building your set…',
                    style: TextStyle(
                      color: AppTheme.violet.withValues(alpha: 0.6),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
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
                    Text(
                      'Generating…',
                      style: TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
