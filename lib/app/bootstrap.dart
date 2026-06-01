import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
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
        googleSignIn: await _initializeGoogleSignIn(config),
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
        statusMessage: kIsWeb
            ? 'Firebase initialization failed, so live tracks are unavailable. Error: $error'
            : 'Firebase initialization failed, so VibeRadar switched to demo mode. Error: $error',
        includeMockTracks: !kIsWeb,
      );
    }
  }
}

class AppBootstrapResult {
  const AppBootstrapResult({
    required this.statusMessage,
    required this.providerOverrides,
    this.isDemoMode = false,
  });

  factory AppBootstrapResult.mock({
    required String statusMessage,
    bool includeMockTracks = true,
  }) {
    return AppBootstrapResult(
      statusMessage: statusMessage,
      isDemoMode: true,
      providerOverrides: [
        trackRepositoryProvider.overrideWithValue(
          includeMockTracks
              ? MockTrackRepository()
              : const EmptyTrackRepository(),
        ),
        userRepositoryProvider.overrideWithValue(MockUserRepository()),
        sessionRepositoryProvider.overrideWithValue(DemoSessionRepository()),
      ],
    );
  }

  final String statusMessage;
  final List providerOverrides;

  /// True when Firebase init failed and the app fell back to demo/mock data,
  /// so the UI can clearly signal that the data on screen is not live.
  final bool isDemoMode;
}

String? _googleClientId(FirebaseRuntimeConfig config) {
  if (config.googleClientId.isNotEmpty) {
    return config.googleClientId;
  }

  final fallbackClientId = DefaultFirebaseOptions.currentPlatform.iosClientId;
  return fallbackClientId?.isNotEmpty == true ? fallbackClientId : null;
}

Future<GoogleSignIn> _initializeGoogleSignIn(
  FirebaseRuntimeConfig config,
) async {
  final googleSignIn = GoogleSignIn.instance;
  try {
    await googleSignIn.initialize(
      clientId: _googleClientId(config),
      serverClientId: config.googleServerClientId.isEmpty
          ? null
          : config.googleServerClientId,
    );
    unawaited(googleSignIn.attemptLightweightAuthentication());
  } catch (error, stackTrace) {
    developer.log(
      'Google Sign-In initialization failed; continuing with Firebase Auth.',
      name: 'Bootstrap',
      error: error,
      stackTrace: stackTrace,
    );
  }
  return googleSignIn;
}
