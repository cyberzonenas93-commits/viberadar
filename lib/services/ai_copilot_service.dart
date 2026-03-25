import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AiCopilotService {
  static const _prefKeyApiKey = 'openai_api_key';
  static const _prefKeyModel = 'openai_model';
  static const _endpoint = 'https://api.openai.com/v1/chat/completions';

  static const _systemPrompt =
      'You are VibeRadar AI Copilot — an expert DJ intelligence assistant '
      'specializing in Afrobeats, Amapiano, R&B, Hip-Hop, and House music. '
      'You help DJs with: identifying trending tracks and artists, building '
      'setlists and crate recommendations, harmonic mixing advice using '
      'Camelot wheel notation, regional music scene intelligence (Nigeria, '
      'South Africa, UK, US), BPM and energy flow for DJ sets, and artist '
      'deep-dives. Be concise, knowledgeable, and speak in DJ/music-industry '
      'language.';

  /// Returns the effective API key: user-override from SharedPreferences first,
  /// then falls back to the .env file value.
  Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final userKey = prefs.getString(_prefKeyApiKey);
    if (userKey != null && userKey.trim().isNotEmpty) return userKey;
    // Fall back to .env
    final envKey = dotenv.env['OPENAI_API_KEY'];
    if (envKey != null && envKey.trim().isNotEmpty) return envKey;
    return null;
  }

  Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyApiKey, key);
  }

  Future<String> getModel() async {
    final prefs = await SharedPreferences.getInstance();
    final userModel = prefs.getString(_prefKeyModel);
    if (userModel != null && userModel.trim().isNotEmpty) return userModel;
    return dotenv.env['OPENAI_MODEL'] ?? 'gpt-4.1';
  }

  Future<void> setModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyModel, model);
  }

  Future<String> chat(
    List<Map<String, String>> history,
    String userMessage,
  ) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      return _simulateResponse(userMessage);
    }

    final model = await getModel();
    final messages = [
      {'role': 'system', 'content': _systemPrompt},
      ...history,
      {'role': 'user', 'content': userMessage},
    ];

    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'messages': messages,
              'max_tokens': 600,
              'temperature': 0.7,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['choices'][0]['message']['content'] as String;
      } else {
        final err = jsonDecode(response.body);
        final errMsg = err['error']?['message'] ?? 'API error ${response.statusCode}';
        return '⚠️ OpenAI error: $errMsg';
      }
    } catch (e) {
      return '⚠️ Network error — check your connection and try again.';
    }
  }

  String _simulateResponse(String query) {
    final q = query.toLowerCase();
    if (q.contains('trending') &&
        (q.contains('ghana') || q.contains('nigeria') || q.contains('afrobeat'))) {
      return 'Right now in West Africa, Rema\'s "Calm Down" is still commanding '
          'dancefloors globally. Watch for newer drops from Asake gaining ground. '
          'BPM sweet spot: 95–105 for peak-hour Afrobeats.';
    }
    if (q.contains('amapiano') || q.contains('south africa')) {
      return 'Amapiano continues to dominate. Kabza De Small & DJ Maphorisa\'s '
          '"Sponono" remains a floor-stopper. Uncle Waffles is pushing the sound '
          'into mainstream House crossover territory. Log drum: 130–135 BPM.';
    }
    if (q.contains('mix') || q.contains('harmonic') || q.contains('camelot')) {
      return 'For harmonic mixing, move within ±1 on the Camelot wheel. '
          '10A (Burna Boy "Last Last") mixes cleanly into 9A, 11A, or 10B. '
          'Avoid jumping more than 3 positions without a key-neutral bridge track.';
    }
    if (q.contains('set') || q.contains('playlist') || q.contains('crate')) {
      return 'Peak-hour Afrobeats set: Open with Rema – Calm Down (93 BPM, 7A) '
          '→ build through Wizkid – Essence (88 BPM) → peak with Burna Boy – '
          'Last Last (93 BPM, 10A) → transition to Amapiano with Black Coffee '
          '(126 BPM).';
    }
    return 'Connect your OpenAI API key in Settings to unlock the full AI Copilot. '
        'In the meantime: the Afrobeats/Amapiano scene is at peak global influence '
        '— now is the time to deep-dive the catalog.';
  }
}
