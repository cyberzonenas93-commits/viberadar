part of 'ai_copilot_screen.dart';

// ── Persistent chat state ─────────────────────────────────────────────────────

class _CopilotChatState {
  final List<Map<String, String>> history;
  final List<({bool isUser, String text, bool isStreaming})> messages;
  final int? yearFrom;
  final int? yearTo;

  const _CopilotChatState({
    this.history = const [],
    this.messages = const [],
    this.yearFrom,
    this.yearTo,
  });

  _CopilotChatState copyWith({
    List<Map<String, String>>? history,
    List<({bool isUser, String text, bool isStreaming})>? messages,
    int? yearFrom,
    int? yearTo,
    bool clearYearFrom = false,
    bool clearYearTo = false,
  }) {
    return _CopilotChatState(
      history: history ?? this.history,
      messages: messages ?? this.messages,
      yearFrom: clearYearFrom ? null : (yearFrom ?? this.yearFrom),
      yearTo: clearYearTo ? null : (yearTo ?? this.yearTo),
    );
  }
}

class _CopilotChatNotifier extends Notifier<_CopilotChatState> {
  @override
  _CopilotChatState build() => _CopilotChatState(
        messages: [
          (
            isUser: false,
            text: 'Hey DJ! I\'m your VibeRadar AI Copilot powered by GPT-5.4. '
                'I have access to the entire Apple Music, Spotify, YouTube, and Billboard '
                'catalogue. Ask me anything — build sets, find tracks, harmonic mixing advice, '
                'or regional music intel.',
            isStreaming: false,
          ),
        ],
      );

  void addUserMessage(String text) {
    state = state.copyWith(
      messages: [
        ...state.messages,
        (isUser: true, text: text, isStreaming: false),
      ],
      history: [
        ...state.history,
        {'role': 'user', 'content': text},
      ],
    );
  }

  void addStreamingMessage() {
    state = state.copyWith(
      messages: [
        ...state.messages,
        (isUser: false, text: '', isStreaming: true),
      ],
    );
  }

  void updateStreamingMessage(String text) {
    final msgs = [...state.messages];
    if (msgs.isNotEmpty && msgs.last.isStreaming) {
      msgs[msgs.length - 1] = (isUser: false, text: text, isStreaming: true);
      state = state.copyWith(messages: msgs);
    }
  }

  void finalizeStreamingMessage(String text) {
    final msgs = [...state.messages];
    if (msgs.isNotEmpty && msgs.last.isStreaming) {
      msgs[msgs.length - 1] = (isUser: false, text: text, isStreaming: false);
      state = state.copyWith(
        messages: msgs,
        history: [
          ...state.history,
          {'role': 'assistant', 'content': text},
        ],
      );
    }
  }

  void addErrorMessage(String text) {
    final msgs = [...state.messages];
    // Remove streaming placeholder if present
    if (msgs.isNotEmpty && msgs.last.isStreaming) {
      msgs[msgs.length - 1] = (isUser: false, text: text, isStreaming: false);
    } else {
      msgs.add((isUser: false, text: text, isStreaming: false));
    }
    state = state.copyWith(messages: msgs);
  }

  void setYearFilter({int? yearFrom, int? yearTo}) {
    state = state.copyWith(
      yearFrom: yearFrom,
      yearTo: yearTo,
      clearYearFrom: yearFrom == null,
      clearYearTo: yearTo == null,
    );
  }

  void addStatusMessage(String text) {
    state = state.copyWith(
      messages: [
        ...state.messages,
        (isUser: false, text: text, isStreaming: false),
      ],
    );
  }

  /// Update the last non-user message (used for progress updates).
  void updateLastStatusMessage(String text) {
    final msgs = [...state.messages];
    // Find last non-user message and update it
    for (var i = msgs.length - 1; i >= 0; i--) {
      if (!msgs[i].isUser) {
        msgs[i] = (isUser: false, text: text, isStreaming: false);
        state = state.copyWith(messages: msgs);
        return;
      }
    }
  }

  void clearChat() {
    state = build(); // Reset to initial state
  }
}

final _copilotChatProvider =
    NotifierProvider<_CopilotChatNotifier, _CopilotChatState>(
        _CopilotChatNotifier.new);

// ── Year filter provider (shared with other screens) ──────────────────────────

class _CopilotYearFilterNotifier
    extends Notifier<({int? yearFrom, int? yearTo})> {
  @override
  ({int? yearFrom, int? yearTo}) build() => (yearFrom: null, yearTo: null);

  void update({required int? yearFrom, required int? yearTo}) {
    state = (yearFrom: yearFrom, yearTo: yearTo);
  }
}

final copilotYearFilterProvider = NotifierProvider<_CopilotYearFilterNotifier,
    ({int? yearFrom, int? yearTo})>(_CopilotYearFilterNotifier.new);

final _aiServiceProvider =
    Provider<AiCopilotService>((_) => AiCopilotService());
