import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/ui/widgets/platform_play_actions.dart';

void main() {
  test('orderedPlatformLinks keeps playable services in product order', () {
    final links = orderedPlatformLinks({
      'youtube': 'https://youtube.test/watch',
      'apple_music': 'https://music.apple.test/song',
      'spotify': 'https://spotify.test/track',
      'empty': '',
      'duplicate': 'https://spotify.test/track',
    });

    expect(links.keys.toList(), ['spotify', 'apple', 'youtube']);
  });

  test('platform labels use customer-facing names', () {
    expect(platformActionLabel('spotify'), 'Play on Spotify');
    expect(platformActionLabel('apple'), 'Play on Apple Music');
    expect(platformActionLabel('youtube'), 'Play on YouTube');
    expect(platformActionLabel('soundcharts'), 'View on Soundcharts');
  });

  testWidgets('renders every provided platform as a visible action', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlatformPlayActions(
            links: {
              'spotify': 'https://spotify.test/track',
              'apple': 'https://music.apple.test/song',
              'youtube': 'https://youtube.test/watch',
            },
            labelStyle: PlatformPlayLabelStyle.platform,
          ),
        ),
      ),
    );

    expect(find.text('Spotify'), findsOneWidget);
    expect(find.text('Apple Music'), findsOneWidget);
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.byTooltip('Play on Spotify'), findsOneWidget);
    expect(find.byTooltip('Play on Apple Music'), findsOneWidget);
    expect(find.byTooltip('Play on YouTube'), findsOneWidget);
  });
}
