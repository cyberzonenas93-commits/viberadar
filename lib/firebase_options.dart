import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
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

  static const web = FirebaseOptions(
    apiKey: 'AIzaSyDdJAfyAg5cwbS5OejhMjjvYwHMvtMguio',
    appId: '1:927344201419:web:99f159a5652fbee153d54e',
    messagingSenderId: '927344201419',
    projectId: 'viberadar-462b8',
    authDomain: 'viberadar-462b8.firebaseapp.com',
    storageBucket: 'viberadar-462b8.firebasestorage.app',
    measurementId: 'G-J6WMSWJECW',
  );

  static const macos = FirebaseOptions(
    apiKey: 'AIzaSyCDZ2kVmhIQenh-YsI_sWXIYDPmWmMFmRE',
    appId: '1:927344201419:ios:4633e386e641834453d54e',
    messagingSenderId: '927344201419',
    projectId: 'viberadar-462b8',
    storageBucket: 'viberadar-462b8.firebasestorage.app',
    iosBundleId: 'com.viberadar.viberadar',
    iosClientId:
        '927344201419-7daqi4nk04m84f3de0677eti4lmo15ll.apps.googleusercontent.com',
  );

  // The iOS companion app reuses the same Firebase iOS app as the macOS build
  // (bundle id com.viberadar.viberadar).
  static const ios = FirebaseOptions(
    apiKey: 'AIzaSyCDZ2kVmhIQenh-YsI_sWXIYDPmWmMFmRE',
    appId: '1:927344201419:ios:4633e386e641834453d54e',
    messagingSenderId: '927344201419',
    projectId: 'viberadar-462b8',
    storageBucket: 'viberadar-462b8.firebasestorage.app',
    iosBundleId: 'com.viberadar.viberadar',
    iosClientId:
        '927344201419-7daqi4nk04m84f3de0677eti4lmo15ll.apps.googleusercontent.com',
  );

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyAC01nIiMGWU70D2UXy_GyInyIh3u5owkI',
    appId: '1:927344201419:android:e1e3dd1e988c583d53d54e',
    messagingSenderId: '927344201419',
    projectId: 'viberadar-462b8',
    storageBucket: 'viberadar-462b8.firebasestorage.app',
  );
}
