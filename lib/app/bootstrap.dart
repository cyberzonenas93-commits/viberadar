import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/config/firebase_runtime_config.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/track_repository.dart';
import '../data/repositories/user_repository.dart';
import '../firebase_options.dart';
import '../providers/repositories.dart';

class AppBootstrap {
  static Future<AppBootstrapResult> initialize() async {
    final config = FirebaseRuntimeConfig.fromEnvironment();

    try {
      await Firebase.initializeApp(
        options: config.isConfigured
            ? config.toOptions()
            : DefaultFirebaseOptions.currentPlatform,
      );

      final trackRepository = FirestoreTrackRepository(
        FirebaseFirestore.instance,
      );
      final userRepository = FirestoreUserRepository(
        FirebaseFirestore.instance,
      );
      final sessionRepository = FirebaseSessionRepository(
        auth: FirebaseAuth.instance,
        googleSignIn: GoogleSignIn.instance,
        config: config,
      );

      return AppBootstrapResult(
        statusMessage: config.isConfigured
            ? 'Connected to Firebase with runtime configuration.'
            : 'Connected to Firebase project viberadar-462b8. Firestore is live; Google sign-in still needs provider and client setup.',
        providerOverrides: [
          trackRepositoryProvider.overrideWithValue(trackRepository),
          userRepositoryProvider.overrideWithValue(userRepository),
          sessionRepositoryProvider.overrideWithValue(sessionRepository),
        ],
      );
    } catch (error) {
      return AppBootstrapResult.mock(
        statusMessage:
            'Firebase initialization failed, so VibeRadar switched to demo mode. Error: $error',
      );
    }
  }
}

class AppBootstrapResult {
  const AppBootstrapResult({
    required this.statusMessage,
    required this.providerOverrides,
  });

  factory AppBootstrapResult.mock({required String statusMessage}) {
    return AppBootstrapResult(
      statusMessage: statusMessage,
      providerOverrides: [
        trackRepositoryProvider.overrideWithValue(MockTrackRepository()),
        userRepositoryProvider.overrideWithValue(MockUserRepository()),
        sessionRepositoryProvider.overrideWithValue(DemoSessionRepository()),
      ],
    );
  }

  final String statusMessage;
  final List providerOverrides;
}
