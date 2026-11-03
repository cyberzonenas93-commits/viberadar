import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/services/ai_copilot_service.dart';

List<Map<String, String>> _tracks(int n) => List.generate(
  n,
  (i) => {
    'title': 'Song Title Number $i',
    'artist': 'Artist $i',
    'bpm': '120',
    'key': '8A',
    'genre': 'Afrobeats',
    'region': 'NG',
    'sources': 'Shazam, TikTok, Boomplay',
  },
);

List<Map<String, String>> _history(int n, {int padChars = 10}) => List.generate(
  n,
  (i) => {
    'role': i.isEven ? 'user' : 'assistant',
    'content': 'm$i${'x' * padChars}',
  },
);

void main() {
  group('renderTrackContext', () {
    test('null / empty returns the no-tracks placeholder', () {
      expect(
        AiCopilotService.renderTrackContext(null),
        contains('No tracks loaded'),
      );
      expect(
        AiCopilotService.renderTrackContext(const []),
        contains('No tracks loaded'),
      );
    });

    test('bounds the block to the char budget regardless of track count', () {
      final block = AiCopilotService.renderTrackContext(_tracks(500));
      // 500 tracks unbounded would be tens of thousands of chars.
      expect(
        block.length,
        lessThanOrEqualTo(AiCopilotService.maxTrackContextChars + 300),
      );
    });

    test('keeps the highest-priority (first) tracks, drops the tail', () {
      final block = AiCopilotService.renderTrackContext(_tracks(500));
      expect(block, contains('Song Title Number 0'));
      expect(block, isNot(contains('Song Title Number 499')));
    });

    test('includes evidence when sources/region are present', () {
      final block = AiCopilotService.renderTrackContext(_tracks(1));
      expect(block, contains('evidence:'));
      expect(block, contains('lead region NG'));
    });
  });

  group('boundedHistory', () {
    test('short history is returned unchanged', () {
      final h = _history(4);
      expect(AiCopilotService.boundedHistory(h), equals(h));
    });

    test('caps the message count, keeping the most recent turns', () {
      final h = _history(40);
      final bounded = AiCopilotService.boundedHistory(h);
      expect(
        bounded.length,
        lessThanOrEqualTo(AiCopilotService.maxHistoryMessages),
      );
      expect(bounded.last, equals(h.last));
    });

    test('caps total chars, keeping the most recent within budget', () {
      final h = _history(40, padChars: 2000); // ~80k total, far over budget
      final bounded = AiCopilotService.boundedHistory(h);
      final total = bounded.fold<int>(
        0,
        (sum, m) => sum + (m['content'] ?? '').length,
      );
      expect(total, lessThanOrEqualTo(AiCopilotService.maxHistoryChars));
      expect(bounded.last, equals(h.last));
    });
  });
}
