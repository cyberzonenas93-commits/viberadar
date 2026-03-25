class AiCopilotMessage {
  const AiCopilotMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.timestamp,
  });
  final String id;
  final String role; // 'user' | 'assistant'
  final String text;
  final DateTime timestamp;
}

class AiCopilotService {
  final List<AiCopilotMessage> _history = [];
  List<AiCopilotMessage> get history => List.unmodifiable(_history);

  void addMessage(AiCopilotMessage msg) => _history.add(msg);
  void clearHistory() => _history.clear();

  AiCopilotMessage simulateResponse(String userMessage) {
    const responses = [
      'Based on current Afrobeats trends, I\'d suggest starting with tracks in the 95–108 BPM range. Burna Boy\'s "Last Last" (93 BPM, 10A) pairs well with Rema\'s "Calm Down" (107 BPM, 10A) — same Camelot key, smooth transition.',
      'For a 2am crowd, energy should peak between 60–90 min in. Consider: Wizkid "Essence" → Tems "Free Mind" → Burna Boy "Ye". All within 88–104 BPM and adjacent Camelot keys.',
      'Amapiano is strongest in ZA (0.93), KE (0.81), and GH (0.74) right now. Kabza De Small and DJ Maphorisa are leading with Sponono at trend score 0.89.',
      'For harmonic mixing, "Last Last" is in 10A. Compatible keys: 9A, 11A, 10B. Tracks in that range: Davido "Fall" (9A), Omah Lay "Soso" (11A).',
      'Connect your OpenAI API key in Settings → API Keys to unlock live GPT-5 responses with real-time trend data.',
    ];
    final text = responses[DateTime.now().millisecond % responses.length];
    return AiCopilotMessage(
      id: DateTime.now().toIso8601String(),
      role: 'assistant',
      text: text,
      timestamp: DateTime.now(),
    );
  }
}
