import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions are not configured for web in this workspace.',
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.iOS:
      case TargetPlatform.android:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'DefaultFirebaseOptions are only configured for macOS right now.',
        );
    }
  }

  static const macos = FirebaseOptions(
    apiKey: 'AIzaSyCDZ2kVmhIQenh-YsI_sWXIYDPmWmMFmRE',
    appId: '1:927344201419:ios:4633e386e641834453d54e',
    messagingSenderId: '927344201419',
    projectId: 'viberadar-462b8',
    storageBucket: 'viberadar-462b8.firebasestorage.app',
    iosBundleId: 'com.viberadar.viberadar',
    iosClientId: '927344201419-7daqi4nk04m84f3de0677eti4lmo15ll.apps.googleusercontent.com',
  );
}
