import 'package:flutter/foundation.dart';

/// True when running on a phone/tablet form factor (iOS or Android).
/// Desktop (macOS/Windows/Linux) and web return false.
bool get isMobileForm =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);
