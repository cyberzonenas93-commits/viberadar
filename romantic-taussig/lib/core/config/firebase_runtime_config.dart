import 'package:firebase_core/firebase_core.dart';

class FirebaseRuntimeConfig {
  const FirebaseRuntimeConfig({
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.projectId,
    required this.storageBucket,
    required this.authDomain,
    required this.measurementId,
    required this.iosClientId,
    required this.iosBundleId,
    required this.googleClientId,
    required this.googleServerClientId,
  });

  factory FirebaseRuntimeConfig.fromEnvironment() {
    return const FirebaseRuntimeConfig(
      apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
      appId: String.fromEnvironment('FIREBASE_APP_ID'),
      messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
      projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
      storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
      authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
      measurementId: String.fromEnvironment('FIREBASE_MEASUREMENT_ID'),
      iosClientId: String.fromEnvironment('FIREBASE_IOS_CLIENT_ID'),
      iosBundleId: String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
      googleClientId: String.fromEnvironment('GOOGLE_CLIENT_ID'),
      googleServerClientId: String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID'),
    );
  }

  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;
  final String storageBucket;
  final String authDomain;
  final String measurementId;
  final String iosClientId;
  final String iosBundleId;
  final String googleClientId;
  final String googleServerClientId;

  bool get isConfigured =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      messagingSenderId.isNotEmpty &&
      projectId.isNotEmpty;

  FirebaseOptions toOptions() {
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      storageBucket: storageBucket.isEmpty ? null : storageBucket,
      authDomain: authDomain.isEmpty ? null : authDomain,
      measurementId: measurementId.isEmpty ? null : measurementId,
      iosClientId: iosClientId.isEmpty ? null : iosClientId,
      iosBundleId: iosBundleId.isEmpty ? null : iosBundleId,
    );
  }
}
