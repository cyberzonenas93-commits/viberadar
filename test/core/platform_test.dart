import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/core/platform.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('isMobileForm is true on iOS/Android, false on desktop', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(isMobileForm, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(isMobileForm, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(isMobileForm, isFalse);
  });
}
