import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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
  String toString() => 'AiCopilotCommand(intent: $intent, params: $params)';
}

// ── AI Copilot service ────────────────────────────────────────────────────────

class AiCopilotService {
  AiCopilotService();

  static const defaultOpenAiModel = 'gpt-4.1';
  static const allowedOpenAiModels = ['gpt-4.1', 'gpt-4o-mini'];
  static const _prefKeyModel = 'openai_model';

  // The backend caps total message chars (and message count). Keep the prompt
  // well under that so a long, multi-turn chat with a full catalog loaded can
  // never blow the limit (which would surface as "couldn't reach the AI
  // service"). The track context is the per-call cost; history is the per-turn
  // growth — bound both. Budgets are deliberately conservative: the base prompt
  // is ~2k chars, so ~7k tracks + ~9k history + user stays comfortably under the
  // 24k server limit with room to spare.
  static const maxTrackContextChars = 7000;
  static const maxHistoryMessages = 16;
  static const maxHistoryChars = 9000;

  static const _baseSystemPrompt =
      'You are VibeRadar AI Copilot — an expert DJ intelligence assistant '
      'specializing in Afrobeats, Amapiano, R&B, Hip-Hop, House, Dancehall, '
      'Pop, Latin, and all open-format music.\n\n'
      'IMPORTANT: You have access to the ENTIRE catalogue of Soundcharts trend evidence '
      '(Shazam, TikTok, and Boomplay charts), Apple Music, Spotify, YouTube, Deezer, '
      'and Billboard charts. You are NOT limited to the tracks below. '
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

  Future<String> getModel() async {
    final prefs = await SharedPreferences.getInstance();
    final userModel = prefs.getString(_prefKeyModel);
    final normalizedUserModel = _normalizeModel(userModel);
    if (normalizedUserModel != null) return normalizedUserModel;

    if (userModel != null && userModel.trim().isNotEmpty) {
      await prefs.remove(_prefKeyModel);
    }

    final envModel = _normalizeModel(dotenv.env['OPENAI_MODEL']);
    return envModel ?? defaultOpenAiModel;
  }

  Future<void> setModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefKeyModel,
      _normalizeModel(model) ?? defaultOpenAiModel,
    );
  }

  String? _normalizeModel(String? model) {
    final normalized = model?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return allowedOpenAiModels.contains(normalized) ? normalized : null;
  }

  Future<String> requestJson(List<Map<String, String>> messages) {
    return _callProxy(messages, jsonObject: true);
  }

  /// Calls the server-side `openaiProxy` callable — the OpenAI key lives in the
  /// backend (Secret Manager), never in the app bundle. Returns the assistant
  /// message content. Throws on transport/auth errors (callers fall back).
  Future<String> _callProxy(
    List<Map<String, String>> messages, {
    bool jsonObject = false,
  }) async {
    final model = await getModel();
    final callable = FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('openaiProxy');
    final result = await callable.call(<String, dynamic>{
      'messages': messages,
      'model': model,
      'maxCompletionTokens': jsonObject ? 400 : 1500,
      'temperature': jsonObject ? 0.3 : 0.7,
      'jsonObject': jsonObject,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return (data['content'] as String?) ?? '';
  }

  // ── Prompt builders ──────────────────────────────────────────────────────

  /// Render the radar track context for the system prompt, bounded to
  /// [maxChars] so the prompt can't approach the server message-char limit no
  /// matter how many tracks are loaded. Tracks are consumed in order (callers
  /// pass them highest-priority first), so the top tracks are always kept.
  static String renderTrackContext(
    List<Map<String, String>>? trackContext, {
    int maxChars = maxTrackContextChars,
  }) {
    if (trackContext == null || trackContext.isEmpty) {
      return '(No tracks loaded yet)\n';
    }
    final buffer = StringBuffer();
    for (final t in trackContext) {
      if (buffer.length >= maxChars) break;
      buffer.write(
        '${t["title"]} - ${t["artist"]} | ${t["bpm"]} BPM | ${t["key"]} | ${t["genre"]}\n',
      );
      final sources = t['sources'];
      final region = t['region'];
      if ((sources != null && sources.isNotEmpty) ||
          (region != null && region.isNotEmpty)) {
        buffer.write(
          '  evidence: ${sources ?? "unknown sources"}'
          '${region != null && region.isNotEmpty ? " | lead region $region" : ""}\n',
        );
      }
    }
    return buffer.toString();
  }

  /// Keep only the most recent slice of [history] — bounded by both message
  /// count and total chars — so a long chat can't grow the request past the
  /// server limits. Order (oldest→newest) of the kept slice is preserved.
  static List<Map<String, String>> boundedHistory(
    List<Map<String, String>> history, {
    int maxMessages = maxHistoryMessages,
    int maxChars = maxHistoryChars,
  }) {
    if (history.isEmpty) return history;
    final kept = <Map<String, String>>[];
    var total = 0;
    for (final message in history.reversed) {
      if (kept.length >= maxMessages) break;
      final length = (message['content'] ?? '').length;
      if (total + length > maxChars && kept.isNotEmpty) break;
      kept.add(message);
      total += length;
    }
    return kept.reversed.toList();
  }

  String _buildSystemPrompt(
    List<Map<String, String>>? trackContext, {
    int? yearFrom,
    int? yearTo,
  }) {
    final buffer = StringBuffer(_baseSystemPrompt);
    buffer.write(renderTrackContext(trackContext));
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

      final topGenres =
          (genreCounts.entries.toList()
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
    final messages = [
      {
        'role': 'system',
        'content': _buildSystemPrompt(
          trackContext,
          yearFrom: yearFrom,
          yearTo: yearTo,
        ),
      },
      ...boundedHistory(history),
      {'role': 'user', 'content': userMessage},
    ];
    try {
      return await _callProxy(messages);
    } catch (e) {
      if (_isUpgradeRequiredError(e)) return _upgradeRequiredMessage;
      if (_isUsageLimitError(e)) return _usageLimitMessage;
      return _simulateResponse(userMessage);
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
    final messages = [
      {
        'role': 'system',
        'content': _buildSystemPrompt(
          trackContext,
          yearFrom: yearFrom,
          yearTo: yearTo,
        ),
      },
      ...boundedHistory(history),
      {'role': 'user', 'content': userMessage},
    ];
    // The proxy returns the full completion (no token streaming) — yield once.
    try {
      yield await _callProxy(messages);
    } catch (e) {
      if (_isUpgradeRequiredError(e)) {
        yield _upgradeRequiredMessage;
        return;
      }
      if (_isUsageLimitError(e)) {
        yield _usageLimitMessage;
        return;
      }
      yield _simulateResponse(userMessage);
    }
  }

  // ── Structured command parsing ───────────────────────────────────────────

  /// Parses [userMessage] through the backend AI proxy and returns a structured [AiCopilotCommand].
  ///
  /// The model returns a JSON object containing `intent`, `params`, and
  /// `naturalResponse`. Falls back to [CopilotIntent.general] on any error.
  Future<AiCopilotCommand> parseCommand(
    String userMessage,
    List<Map<String, String>>? trackContext, {
    int? yearFrom,
    int? yearTo,
  }) async {
    final systemPrompt = _buildParseCommandContext(
      trackContext,
      yearFrom: yearFrom,
      yearTo: yearTo,
    );
    final messages = [
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userMessage},
    ];
    try {
      final content = await _callProxy(messages, jsonObject: true);
      return _parseCommandJson(content, userMessage);
    } catch (e) {
      if (_isUpgradeRequiredError(e)) {
        return const AiCopilotCommand(
          intent: CopilotIntent.general,
          params: {},
          naturalResponse: _upgradeRequiredMessage,
        );
      }
      if (_isUsageLimitError(e)) {
        return const AiCopilotCommand(
          intent: CopilotIntent.general,
          params: {},
          naturalResponse: _usageLimitMessage,
        );
      }
      return AiCopilotCommand(
        intent: CopilotIntent.general,
        params: const {},
        naturalResponse: _simulateResponse(userMessage),
      );
    }
  }

  AiCopilotCommand _parseCommandJson(String raw, String fallback) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final intentStr = data['intent'] as String? ?? 'general';
      final params = (data['params'] as Map<String, dynamic>?) ?? const {};
      final naturalResponse = data['naturalResponse'] as String? ?? raw;

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

  static const _usageLimitMessage =
      "You've reached this month's AI usage limit. It resets at the start of "
      "next month.";
  static const _upgradeRequiredMessage =
      'VibeRadar Pro is required for AI set building.';

  bool _isUsageLimitError(Object error) =>
      error is FirebaseFunctionsException && error.code == 'resource-exhausted';
  bool _isUpgradeRequiredError(Object error) =>
      error is FirebaseFunctionsException &&
      error.code == 'failed-precondition';

  /// Honest fallback when the AI proxy is unreachable. The OpenAI key lives in
  /// the backend, so a failure here is a transient network/service error — we
  /// say so plainly rather than presenting canned content as real AI output
  /// (App Store Guideline 2.1, accurate functionality).
  String _simulateResponse(String query) {
    return "I couldn't reach the AI service just now — please check your "
        "connection and try again in a moment.";
  }
}
