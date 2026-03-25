import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ai_copilot_service.dart';

final aiCopilotServiceProvider = Provider<AiCopilotService>((ref) => AiCopilotService());

final chatHistoryProvider =
    StateNotifierProvider<ChatHistoryNotifier, List<AiCopilotMessage>>((ref) {
  return ChatHistoryNotifier(ref.watch(aiCopilotServiceProvider));
});

class ChatHistoryNotifier extends StateNotifier<List<AiCopilotMessage>> {
  ChatHistoryNotifier(this._service)
      : super([
          AiCopilotMessage(
            id: 'init',
            role: 'assistant',
            text:
                'Hey DJ! I\'m your Vibe Radar AI Copilot. Ask me about trending tracks, set recommendations, harmonic mixing, or regional music intelligence.',
            timestamp: DateTime.now(),
          ),
        ]);

  final AiCopilotService _service;
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    final userMsg = AiCopilotMessage(
      id: DateTime.now().toIso8601String(),
      role: 'user',
      text: text,
      timestamp: DateTime.now(),
    );
    state = [...state, userMsg];
    _isLoading = true;
    await Future.delayed(const Duration(milliseconds: 900));
    final response = _service.simulateResponse(text);
    state = [...state, response];
    _isLoading = false;
  }

  void clear() {
    state = [state.first];
  }
}

final isAiLoadingProvider = StateProvider<bool>((ref) => false);
