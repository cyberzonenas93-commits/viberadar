import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../services/ai_copilot_service.dart';

export '../services/ai_copilot_service.dart' show AiCopilotMessage;

final aiCopilotServiceProvider = Provider((ref) => AiCopilotService());

final chatHistoryProvider =
    StateNotifierProvider<ChatHistoryNotifier, List<AiCopilotMessage>>((ref) {
      return ChatHistoryNotifier(ref.watch(aiCopilotServiceProvider));
    });

final isAiLoadingProvider = StateProvider<bool>((ref) => false);

final aiModelNameProvider = FutureProvider<String>((ref) async {
  return AppConfig.getOpenAiModel();
});

class ChatHistoryNotifier extends StateNotifier<List<AiCopilotMessage>> {
  ChatHistoryNotifier(this._service)
    : super([
        AiCopilotMessage(
          id: 'init',
          role: 'assistant',
          text:
              'Hey DJ! I\'m Vibe Radar AI Copilot, powered by OpenAI. Ask me about trending tracks, set building, harmonic mixing, or regional music intelligence.',
          timestamp: DateTime.now(),
        ),
      ]);

  final AiCopilotService _service;
  bool _loading = false;
  bool get isLoading => _loading;

  Future<void> send(
    String text, {
    required void Function(bool) onLoadingChanged,
  }) async {
    if (text.trim().isEmpty || _loading) return;

    final userMsg = AiCopilotMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: 'user',
      text: text.trim(),
      timestamp: DateTime.now(),
    );
    state = [...state, userMsg];
    _loading = true;
    onLoadingChanged(true);

    final historyForApi = state.where((m) => m.role != 'system').toList();
    final apiResponse = await _service.sendToOpenAi(historyForApi, text);
    final responseText = apiResponse ?? _service.simulateResponse(text);

    final assistantMsg = AiCopilotMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: 'assistant',
      text: responseText,
      timestamp: DateTime.now(),
    );
    state = [...state, assistantMsg];
    _loading = false;
    onLoadingChanged(false);
  }

  void clear() {
    state = [state.first];
  }
}
