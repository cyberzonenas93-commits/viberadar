import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
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
      await _activateAppCheck();

      // Desktop no longer auto-creates a backend session. The auth gate shows
      // onboarding + sign-in / account creation first; "Continue as Guest"
      // activates local demo mode without live service calls.

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
        statusMessage: '',
        providerOverrides: [
          trackRepositoryProvider.overrideWithValue(trackRepository),
          userRepositoryProvider.overrideWithValue(userRepository),
          sessionRepositoryProvider.overrideWithValue(sessionRepository),
        ],
      );
    } catch (error) {
      return AppBootstrapResult.mock(
        statusMessage: kIsWeb
            ? 'Live services failed to initialize, so live tracks are unavailable. Error: $error'
            : 'Live services failed to initialize, so VibeRadar switched to demo mode. Error: $error',
        includeMockTracks: !kIsWeb,
      );
    }
  }
}

Future<void> _activateAppCheck() async {
  const enabled = bool.fromEnvironment(
    'FIREBASE_APP_CHECK_ENABLED',
    defaultValue: true,
  );
  if (!enabled) return;

  const webSiteKey = String.fromEnvironment(
    'FIREBASE_APPCHECK_RECAPTCHA_SITE_KEY',
  );
  const debugToken = String.fromEnvironment('FIREBASE_APPCHECK_DEBUG_TOKEN');

  try {
    await FirebaseAppCheck.instance.activate(
      providerWeb: kReleaseMode
          ? webSiteKey.isEmpty
                ? null
                : ReCaptchaV3Provider(webSiteKey)
          : WebDebugProvider(
              debugToken: debugToken.isEmpty ? null : debugToken,
            ),
      providerAndroid: kReleaseMode
          ? const AndroidPlayIntegrityProvider()
          : AndroidDebugProvider(
              debugToken: debugToken.isEmpty ? null : debugToken,
            ),
      providerApple: kReleaseMode
          ? const AppleAppAttestWithDeviceCheckFallbackProvider()
          : AppleDebugProvider(
              debugToken: debugToken.isEmpty ? null : debugToken,
            ),
    );
  } catch (error, stackTrace) {
    developer.log(
      'Firebase App Check activation failed; protected backend calls may be rejected if App Check enforcement is enabled.',
      name: 'Bootstrap',
      error: error,
      stackTrace: stackTrace,
    );
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
  final List<Object?> providerOverrides;

  /// True when live service init failed and the app fell back to demo/mock data,
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
