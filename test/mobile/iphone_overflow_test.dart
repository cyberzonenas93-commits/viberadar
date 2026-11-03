import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:viberadar/core/theme/app_theme.dart';
import 'package:viberadar/models/session_state.dart';
import 'package:viberadar/models/track.dart';
import 'package:viberadar/models/user_profile.dart';
import 'package:viberadar/providers/app_state.dart';
import 'package:viberadar/providers/setlist_provider.dart';
import 'package:viberadar/ui/mobile/mobile_shell.dart';

Track _track(int index) {
  final now = DateTime(2026, 1, 1);
  return Track(
    id: 'iphone-track-$index',
    title: 'Very Long Festival Edit Title Number $index With Remix Notes',
    artist: 'A Long Artist Collective Name $index',
    artworkUrl: '',
    bpm: 118 + index,
    keySignature: '${index % 12}A',
    genre: index.isEven ? 'Long Afrobeats Fusion Genre Label' : 'Dancehall',
    vibe: 'peak-time',
    trendScore: 1 - (index * 0.04),
    regionScores: const {'GH': 0.9, 'NG': 0.7, 'US': 0.4},
    platformLinks: const {},
    createdAt: now,
    updatedAt: now,
    energyLevel: 0.75,
    trendHistory: const [],
    sources: const ['spotify', 'apple', 'youtube'],
    releaseYear: 2026,
  );
}

Widget _wrap() {
  final tracks = List.generate(18, _track);
  return ProviderScope(
    overrides: [
      setlistsProvider.overrideWithValue(const []),
      sessionProvider.overrideWith(
        (ref) => Stream.value(const SessionState.demo()),
      ),
      userProfileProvider.overrideWith(
        (ref) => Stream.value(
          UserProfile.empty(
            id: 'iphone-user',
            displayName: 'iPhone DJ',
            preferredRegion: 'GH',
          ),
        ),
      ),
      trackStreamProvider.overrideWith((ref) => Stream.value(tracks)),
    ],
    child: MaterialApp(theme: AppTheme.darkTheme(), home: const MobileShell()),
  );
}

void _setIPhoneViewport(
  WidgetTester tester, {
  required double width,
  required double height,
  required double devicePixelRatio,
}) {
  tester.view.devicePixelRatio = devicePixelRatio;
  tester.view.physicalSize = Size(
    width * devicePixelRatio,
    height * devicePixelRatio,
  );
}

bool _isOverflow(FlutterErrorDetails details) {
  final text = details.exceptionAsString();
  return text.contains('RenderFlex overflowed') ||
      text.contains('overflowed by') ||
      text.contains('outside its parent');
}

void main() {
  for (final viewport in const [
    (name: 'iPhone SE', width: 320.0, height: 568.0, dpr: 2.0),
    (name: 'iPhone 15', width: 393.0, height: 852.0, dpr: 3.0),
  ]) {
    testWidgets('MobileShell has no pixel overflow on ${viewport.name}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      _setIPhoneViewport(
        tester,
        width: viewport.width,
        height: viewport.height,
        devicePixelRatio: viewport.dpr,
      );

      final errors = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() {
        FlutterError.onError = previousOnError;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        debugDefaultTargetPlatformOverride = null;
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();

      for (final label in ['Trending', 'Search', 'AI', 'More']) {
        await tester.tap(find.text(label).last);
        await tester.pump();
      }

      await tester.drag(find.byType(ListView).last, const Offset(0, -360));
      await tester.pump();

      FlutterError.onError = previousOnError;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;

      final unexpectedErrors = errors.where((e) => !_isOverflow(e)).toList();
      final overflowErrors = errors.where(_isOverflow).toList();
      expect(
        unexpectedErrors,
        isEmpty,
        reason: unexpectedErrors.map((e) => e.exceptionAsString()).join('\n'),
      );
      expect(
        overflowErrors,
        isEmpty,
        reason: overflowErrors.map((e) => e.exceptionAsString()).join('\n'),
      );
    });
  }
}
