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
        return ios;
      case TargetPlatform.android:
        return android;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
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

  // iOS shares the same Firebase app as macOS (same bundle ID)
  static const ios = FirebaseOptions(
    apiKey: 'AIzaSyCDZ2kVmhIQenh-YsI_sWXIYDPmWmMFmRE',
    appId: '1:927344201419:ios:4633e386e641834453d54e',
    messagingSenderId: '927344201419',
    projectId: 'viberadar-462b8',
    storageBucket: 'viberadar-462b8.firebasestorage.app',
    iosBundleId: 'com.viberadar.viberadar',
    iosClientId: '927344201419-7daqi4nk04m84f3de0677eti4lmo15ll.apps.googleusercontent.com',
  );

  // Android — uses same Firebase project. You must register the Android app
  // in Firebase Console with package name 'com.viberadar.viberadar' and
  // download google-services.json to android/app/
  static const android = FirebaseOptions(
    apiKey: 'AIzaSyCDZ2kVmhIQenh-YsI_sWXIYDPmWmMFmRE',
    appId: '1:927344201419:android:4633e386e641834453d54e',
    messagingSenderId: '927344201419',
    projectId: 'viberadar-462b8',
    storageBucket: 'viberadar-462b8.firebasestorage.app',
  );
}
