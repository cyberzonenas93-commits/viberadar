import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/ui/auth/onboarding_screen.dart';

void main() {
  testWidgets('popular artist choices load Spotify artist images', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final requestedBatches = <List<String>>[];

    Future<Map<String, String>> fakeArtistImageLookup(
      List<String> artists,
    ) async {
      requestedBatches.add(List<String>.from(artists));
      return {
        for (final artist in artists)
          artist: 'https://i.scdn.co/image/${Uri.encodeComponent(artist)}.jpg',
      };
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OnboardingArtistPicker(
            artistImageLookup: fakeArtistImageLookup,
            onComplete: (_) {},
            onSkip: () {},
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(requestedBatches, isNotEmpty);
    expect(requestedBatches.first, contains('Drake'));

    final drakeImageFinder = find.byKey(
      const ValueKey('onboarding-artist-image-Drake'),
    );
    expect(drakeImageFinder, findsOneWidget);

    final drakeImage = tester.widget<CachedNetworkImage>(drakeImageFinder);
    expect(drakeImage.imageUrl, 'https://i.scdn.co/image/Drake.jpg');
  });
}
