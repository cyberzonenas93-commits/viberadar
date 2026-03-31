import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── Structured command model ──────────────────────────────────────────────────

enum CopilotIntent {
  buildSet,
  findArtist,
  setReleaseRange,
  matchLibrary,
  cleanDuplicates,
  createCrate,
  general,
}

class AiCopilotCommand {
  const AiCopilotCommand({
    required this.intent,
    required this.params,
    required this.naturalResponse,
  });

  final CopilotIntent intent;

  /// Structured params extracted by GPT (genre, artist, yearFrom, yearTo,
  /// region, bpm, etc.)
  final Map<String, dynamic> params;

  /// The human-readable AI reply to show in the chat bubble.
  final String naturalResponse;

  @override
  String toString() =>
      'AiCopilotCommand(intent: $intent, params: $params)';
}

// ── AI Copilot service ────────────────────────────────────────────────────────

class AiCopilotService {
  static const _prefKeyApiKey = 'openai_api_key';
  static const _prefKeyModel = 'openai_model';
  static const _endpoint = 'https://api.openai.com/v1/chat/completions';

  static const _baseSystemPrompt =
      'You are VibeRadar AI Copilot — an expert DJ intelligence assistant '
      'specializing in Afrobeats, Amapiano, R&B, Hip-Hop, House, Dancehall, '
      'Pop, Latin, and all open-format music.\n\n'
      'IMPORTANT: You have access to the ENTIRE catalogue of Apple Music, Spotify, '
      'YouTube, Deezer, and Billboard charts. You are NOT limited to the tracks below. '
      'The tracks below are what the user currently has in their radar — but you can and '
      'should recommend ANY song that exists on these platforms when building sets. '
      'Use your full knowledge of music across all genres, eras, and regions.\n\n'
      '*** MANDATORY RULE FOR SET/CRATE/PLAYLIST REQUESTS ***\n'
      'When a user asks you to BUILD, CREATE, or MAKE a set, crate, or playlist:\n'
      'You MUST ALWAYS end your response with a ```crate JSON block. NO EXCEPTIONS.\n'
      'This is how the app creates the actual crate. Without it, nothing gets created.\n\n'
      'Response format:\n'
      '1. One brief sentence about the vibe\n'
      '2. Numbered track list: "1. Artist - Title (BPM, Key)"\n'
      '3. One brief mixing tip\n'
      '4. MANDATORY crate block at the very end:\n'
      '```crate\n'
      '{"name":"Crate Name","tracks":[{"title":"Song","artist":"Artist","bpm":120,"key":"7A"}]}\n'
      '```\n'
      'NEVER skip the crate block. NEVER. The app will not create the crate without it.\n'
      'Include 15-30 tracks. Always include BPM and Camelot key.\n\n'
      'For non-set questions (mixing advice, artist info, etc), respond normally without a crate block.\n\n'
      'You also help with: harmonic mixing (Camelot wheel), regional scene intel '
      '(Ghana, Nigeria, South Africa, UK, US), BPM/energy flow, artist deep-dives.\n\n'
      'TRACKS CURRENTLY IN RADAR (prefer these when relevant, but use ANY songs):\n';

  /// System prompt for structured command parsing.
  static const _parseCommandSystemPrompt =
      'You are VibeRadar AI Copilot. Parse the user message and return a JSON '
      'object with two keys:\n'
      '1. "intent": one of ["buildSet","findArtist","setReleaseRange",'
      '"matchLibrary","cleanDuplicates","createCrate","general"]\n'
      '2. "params": an object with any of: genre, artist, yearFrom (int), '
      'yearTo (int), region, bpm (int), key, energy\n'
      '3. "naturalResponse": your friendly reply to show the user\n\n'
      'Examples:\n'
      '- "Build me an Afrobeats set from 2020-2024" → '
      '{"intent":"buildSet","params":{"genre":"Afrobeats","yearFrom":2020,"yearTo":2024},'
      '"naturalResponse":"Sure! Building an Afrobeats set from 2020–2024..."}\n'
      '- "Find tracks by Burna Boy" → '
      '{"intent":"findArtist","params":{"artist":"Burna Boy"},'
      '"naturalResponse":"Searching for Burna Boy in your library..."}\n'
      '- "Show me tracks from 2019 to 2022" → '
      '{"intent":"setReleaseRange","params":{"yearFrom":2019,"yearTo":2022},'
      '"naturalResponse":"Filtering to 2019–2022 releases..."}\n'
      'ONLY return valid JSON. No extra text outside the JSON object.\n\n'
      'LIBRARY CONTEXT:\n';

  // ── API key / model helpers ──────────────────────────────────────────────

  Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final userKey = prefs.getString(_prefKeyApiKey);
    if (userKey != null && userKey.trim().isNotEmpty) return userKey;
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
    return dotenv.env['OPENAI_MODEL'] ?? 'gpt-5.4';
  }

  Future<void> setModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyModel, model);
  }

  // ── Prompt builders ──────────────────────────────────────────────────────

  String _buildSystemPrompt(
    List<Map<String, String>>? trackContext, {
    int? yearFrom,
    int? yearTo,
  }) {
    final buffer = StringBuffer(_baseSystemPrompt);
    if (trackContext != null && trackContext.isNotEmpty) {
      for (final t in trackContext.take(80)) {
        buffer.write(
            '${t["title"]} - ${t["artist"]} | ${t["bpm"]} BPM | ${t["key"]} | ${t["genre"]}\n');
      }
    } else {
      buffer.write('(No tracks loaded yet)\n');
    }
    if (yearFrom != null || yearTo != null) {
      buffer.write('\nACTIVE YEAR FILTER: ');
      if (yearFrom != null && yearTo != null) {
        buffer.write('$yearFrom–$yearTo\n');
      } else if (yearFrom != null) {
        buffer.write('from $yearFrom\n');
      } else {
        buffer.write('up to $yearTo\n');
      }
    }
    return buffer.toString();
  }

  String _buildParseCommandContext(
    List<Map<String, String>>? trackContext, {
    int? yearFrom,
    int? yearTo,
  }) {
    final buffer = StringBuffer(_parseCommandSystemPrompt);

    if (trackContext != null && trackContext.isNotEmpty) {
      // Genre breakdown
      final genreCounts = <String, int>{};
      final artists = <String>{};
      int minYear = 9999, maxYear = 0;

      for (final t in trackContext) {
        final g = t['genre'] ?? '';
        if (g.isNotEmpty) genreCounts[g] = (genreCounts[g] ?? 0) + 1;
        final a = t['artist'] ?? '';
        if (a.isNotEmpty) artists.add(a);
        final y = int.tryParse(t['year'] ?? '') ?? 0;
        if (y > 1900 && y < minYear) minYear = y;
        if (y > maxYear) maxYear = y;
      }

      final topGenres = (genreCounts.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(5)
          .map((e) => '${e.key}(${e.value})')
          .join(', ');

      final topArtists = artists.take(10).join(', ');

      buffer.write('Track count: ${trackContext.length}\n');
      buffer.write('Top genres: $topGenres\n');
      buffer.write('Sample artists: $topArtists\n');

      if (minYear < 9999 && maxYear > 0) {
        buffer.write('Year range available: $minYear–$maxYear\n');
      }
    } else {
      buffer.write('(No library tracks loaded)\n');
    }

    if (yearFrom != null || yearTo != null) {
      buffer.write('Current active year filter: ');
      buffer.write(yearFrom != null ? '$yearFrom' : '(any)');
      buffer.write('–');
      buffer.write(yearTo != null ? '$yearTo' : '(any)');
      buffer.write('\n');
    }

    return buffer.toString();
  }

  // ── Core chat method ─────────────────────────────────────────────────────

  Future<String> chat(
    List<Map<String, String>> history,
    String userMessage, {
    List<Map<String, String>>? trackContext,
    int? yearFrom,
    int? yearTo,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      return _simulateResponse(userMessage);
    }

    final model = await getModel();
    final messages = [
      {
        'role': 'system',
        'content': _buildSystemPrompt(trackContext,
            yearFrom: yearFrom, yearTo: yearTo)
      },
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
              'max_completion_tokens': 16384,
              'temperature': 0.7,
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['choices'][0]['message']['content'] as String;
      } else {
        final err = jsonDecode(response.body);
        final errMsg =
            err['error']?['message'] ?? 'API error ${response.statusCode}';
        return '⚠️ OpenAI error: $errMsg';
      }
    } catch (e) {
      return '⚠️ Network error — check your connection and try again.';
    }
  }

  // ── Streaming chat ─────────────────────────────────────────────────────

  /// Streams the AI response token-by-token via SSE.
  /// Calls [onToken] with each new chunk of text as it arrives.
  /// Returns the full completed response when done.
  Stream<String> chatStream(
    List<Map<String, String>> history,
    String userMessage, {
    List<Map<String, String>>? trackContext,
    int? yearFrom,
    int? yearTo,
  }) async* {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      yield _simulateResponse(userMessage);
      return;
    }

    final model = await getModel();
    final messages = [
      {
        'role': 'system',
        'content': _buildSystemPrompt(trackContext,
            yearFrom: yearFrom, yearTo: yearTo)
      },
      ...history,
      {'role': 'user', 'content': userMessage},
    ];

    final request = http.Request('POST', Uri.parse(_endpoint));
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode({
      'model': model,
      'messages': messages,
      'max_completion_tokens': 4096,
      'temperature': 0.7,
      'stream': true,
    });

    try {
      final client = http.Client();
      final response = await client.send(request).timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        try {
          final err = jsonDecode(body);
          yield '⚠️ OpenAI error: ${err['error']?['message'] ?? 'API error ${response.statusCode}'}';
        } catch (_) {
          yield '⚠️ API error ${response.statusCode}';
        }
        client.close();
        return;
      }

      final buffer = StringBuffer();
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        // SSE: each line starts with "data: "
        for (final line in chunk.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed == 'data: [DONE]') continue;
          if (!trimmed.startsWith('data: ')) continue;

          try {
            final json = jsonDecode(trimmed.substring(6)) as Map<String, dynamic>;
            final delta = json['choices']?[0]?['delta']?['content'] as String?;
            if (delta != null && delta.isNotEmpty) {
              buffer.write(delta);
              yield buffer.toString();
            }
          } catch (_) {}
        }
      }
      client.close();
    } catch (e) {
      yield '⚠️ Network error — check your connection and try again.';
    }
  }

  // ── Structured command parsing ───────────────────────────────────────────

  /// Parses [userMessage] via GPT-5.4 and returns a structured [AiCopilotCommand].
  ///
  /// The model returns a JSON object containing `intent`, `params`, and
  /// `naturalResponse`. Falls back to [CopilotIntent.general] on any error.
  Future<AiCopilotCommand> parseCommand(
    String userMessage,
    List<Map<String, String>>? trackContext, {
    int? yearFrom,
    int? yearTo,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      // No API key — return a general intent with simulated text.
      return AiCopilotCommand(
        intent: CopilotIntent.general,
        params: const {},
        naturalResponse: _simulateResponse(userMessage),
      );
    }

    final model = await getModel();
    final systemPrompt = _buildParseCommandContext(trackContext,
        yearFrom: yearFrom, yearTo: yearTo);

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
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': userMessage},
              ],
              'max_completion_tokens': 400,
              'temperature': 0.3,
              'response_format': {'type': 'json_object'},
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final content = json['choices'][0]['message']['content'] as String;
        return _parseCommandJson(content, userMessage);
      } else {
        final err = jsonDecode(response.body);
        final errMsg =
            err['error']?['message'] ?? 'API error ${response.statusCode}';
        return AiCopilotCommand(
          intent: CopilotIntent.general,
          params: const {},
          naturalResponse: '⚠️ OpenAI error: $errMsg',
        );
      }
    } catch (e) {
      return AiCopilotCommand(
        intent: CopilotIntent.general,
        params: const {},
        naturalResponse: '⚠️ Network error — check your connection and try again.',
      );
    }
  }

  AiCopilotCommand _parseCommandJson(String raw, String fallback) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final intentStr = data['intent'] as String? ?? 'general';
      final params =
          (data['params'] as Map<String, dynamic>?) ?? const {};
      final naturalResponse =
          data['naturalResponse'] as String? ?? raw;

      final intent = _intentFromString(intentStr);
      return AiCopilotCommand(
        intent: intent,
        params: params,
        naturalResponse: naturalResponse,
      );
    } catch (_) {
      return AiCopilotCommand(
        intent: CopilotIntent.general,
        params: const {},
        naturalResponse: raw,
      );
    }
  }

  CopilotIntent _intentFromString(String s) {
    switch (s) {
      case 'buildSet':
        return CopilotIntent.buildSet;
      case 'findArtist':
        return CopilotIntent.findArtist;
      case 'setReleaseRange':
        return CopilotIntent.setReleaseRange;
      case 'matchLibrary':
        return CopilotIntent.matchLibrary;
      case 'cleanDuplicates':
        return CopilotIntent.cleanDuplicates;
      case 'createCrate':
        return CopilotIntent.createCrate;
      default:
        return CopilotIntent.general;
    }
  }

  // ── Fallback simulation ──────────────────────────────────────────────────

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
