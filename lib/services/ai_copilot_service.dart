import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';

class AiCopilotMessage {
  const AiCopilotMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.timestamp,
  });

  final String id;
  final String role;
  final String text;
  final DateTime timestamp;

  Map<String, dynamic> toOpenAiFormat() => {'role': role, 'content': text};
}

class AiCopilotService {
  static const _systemPrompt =
      '''You are Vibe Radar AI Copilot, an expert DJ intelligence assistant. You specialize in:
- Afrobeats, Amapiano, R&B, Hip-Hop, House, and Afro House music trends
- Harmonic mixing using Camelot Wheel notation
- Regional music trends across Africa (Ghana, Nigeria, South Africa, Kenya) and globally
- Set building recommendations for different crowd types and time slots
- Track metadata analysis (BPM, key, energy, vibe)

Be concise, specific, and DJ-focused. Use music industry terminology. When recommending tracks, include BPM and Camelot key when known.''';

  /// Send a message and get a real OpenAI response.
  /// Returns null if no API key is configured (caller should fall back to simulation).
  Future<String?> sendToOpenAi(
    List<AiCopilotMessage> history,
    String userMessage,
  ) async {
    final apiKey = await AppConfig.getOpenAiKey();
    if (apiKey == null || apiKey.isEmpty) return null;

    final model = await AppConfig.getOpenAiModel();

    final messages = [
      {'role': 'system', 'content': _systemPrompt},
      ...history.map((m) => m.toOpenAiFormat()),
      {'role': 'user', 'content': userMessage},
    ];

    try {
      final response = await http
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': model,
              'messages': messages,
              'max_tokens': 600,
              'temperature': 0.8,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'] as String;
      } else {
        return 'API error ${response.statusCode}. Check your API key in Settings.';
      }
    } catch (e) {
      return 'Connection error: $e. Check your internet connection.';
    }
  }

  /// Simulation fallback when no API key is configured.
  String simulateResponse(String userMessage) {
    final lower = userMessage.toLowerCase();
    if (lower.contains('ghana') || lower.contains('gh')) {
      return 'Ghana is trending hard right now. Top tracks: Burna Boy "Last Last" (10A, 93 BPM, score 96), Rema "Calm Down" (10A, 107 BPM, score 94). Afrobeats and Amapiano are both performing well in Accra.';
    }
    if (lower.contains('mix') ||
        lower.contains('harmonic') ||
        lower.contains('camelot')) {
      return 'For harmonic mixing, "Last Last" is in 10A. Compatible keys: 9A (one step down), 11A (one step up), 10B (relative major). Tracks nearby: Davido "Fall" (9A, 88 BPM), Wizkid "Essence" (11A, 94 BPM).';
    }
    if (lower.contains('2am') ||
        lower.contains('late night') ||
        lower.contains('peak')) {
      return 'For a 2am peak set, build energy gradually: start Amapiano ~112 BPM, transition to Afrobeats 95–105 BPM, peak with high-energy Afro House 120+ BPM. Try: Sponono → Essence → Last Last → Midnight Signal.';
    }
    if (lower.contains('amapiano')) {
      return 'Amapiano is strongest in ZA (0.93 trend), KE (0.81), GH (0.74). Leaders: Kabza De Small, DJ Maphorisa, Uncle Waffles. Typical BPM: 110–115. Log drum patterns are key. Connect your API key for live data.';
    }
    return 'Connect your OpenAI API key in Settings → API Keys to get live AI responses with real-time trend data and personalized DJ recommendations.';
  }
}
