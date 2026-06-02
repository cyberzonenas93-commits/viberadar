import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../models/session_state.dart';

abstract class SessionRepository {
  Stream<SessionState> sessionChanges();

  Future<void> signInWithEmail({
    required String email,
    required String password,
  });

  Future<void> signInWithGoogle();

  Future<void> signInWithApple();

  Future<void> signInAnonymously();

  Future<void> createAccount({
    required String email,
    required String password,
    required String displayName,
  });

  Future<void> signOut();
}

class DemoSessionRepository implements SessionRepository {
  @override
  Stream<SessionState> sessionChanges() =>
      Stream<SessionState>.value(const SessionState.demo());

  @override
  Future<void> createAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {}

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signInWithApple() async {}

  @override
  Future<void> signInAnonymously() async {}

  @override
  Future<void> signOut() async {}
}

class FirebaseSessionRepository implements SessionRepository {
  FirebaseSessionRepository({
    required FirebaseAuth auth,
    required GoogleSignIn googleSignIn,
  }) : _auth = auth,
       _googleSignIn = googleSignIn;

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  @override
  Stream<SessionState> sessionChanges() async* {
    // Check "remember me" preference
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool('remember_me') ?? true;

    // ── Warm start: user already in memory ──
    final cached = _auth.currentUser;
    if (cached != null) {
      if (!rememberMe) {
        // User opted out of "keep me signed in" — sign out
        await _auth.signOut();
        yield _toState(null);
        yield* _auth.authStateChanges().map(_toState);
        return;
      }
      yield _toState(cached);
      yield* _auth.authStateChanges().map(_toState);
      return;
    }

    // ── Cold start: wait for Firebase to restore from Keychain ──
    if (!rememberMe) {
      // Not remembering — go straight to login
      yield _toState(null);
      yield* _auth.authStateChanges().map(_toState);
      return;
    }

    // Wait up to 3 seconds for a non-null user from the auth stream.
    User? firstUser;
    try {
      firstUser = await _auth.authStateChanges()
          .where((u) => u != null)
          .first
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      firstUser = _auth.currentUser;
    }

    if (firstUser != null) {
      yield _toState(firstUser);
    } else {
      yield _toState(null);
    }

    yield* _auth.authStateChanges().map(_toState);
  }

  SessionState _toState(User? user) {
    if (user == null) {
      return const SessionState(
        userId: '',
        displayName: '',
        email: '',
        providerLabel: '',
        isAuthenticated: false,
        isDemo: false,
      );
    }
    final isAnon = user.isAnonymous;
    return SessionState(
      userId: user.uid,
      displayName: isAnon ? 'Guest DJ' : (user.displayName ?? 'VibeRadar DJ'),
      email: isAnon ? '' : (user.email ?? 'unknown@viberadar.app'),
      providerLabel: isAnon
          ? 'Guest'
          : (user.providerData.isEmpty
                ? 'Email'
                : user.providerData.first.providerId),
      isAuthenticated: true,
      isDemo: false,
    );
  }

  @override
  Future<void> createAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    try {
      await credential.user?.updateDisplayName(displayName);
    } catch (e, st) {
      developer.log('Failed to set display name after registration', name: 'SessionRepository', error: e, stackTrace: st);
    }
  }

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  @override
  Future<void> signInAnonymously() async {
    debugPrint('VIBERADAR: Signing in anonymously...');
    await _auth.signInAnonymously();
    debugPrint('VIBERADAR: Anonymous sign-in complete.');
  }

  @override
  Future<void> signInWithGoogle() async {
    debugPrint('VIBERADAR: Starting Google Sign-In...');
    try {
      final googleUser = await _googleSignIn.authenticate();
      debugPrint('VIBERADAR: Got Google user, fetching ID token...');
      final idToken = googleUser.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        debugPrint('VIBERADAR: No ID token returned!');
        throw StateError(
          'Google Sign-In did not return an ID token. '
          'Check the Google client ID and Firebase Google provider setup.',
        );
      }

      debugPrint('VIBERADAR: Got ID token, signing into Firebase...');
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      await _auth.signInWithCredential(credential);
      debugPrint('VIBERADAR: Firebase sign-in complete!');
    } catch (e, stack) {
      debugPrint('VIBERADAR: Google Sign-In error: $e');
      debugPrint('VIBERADAR: Stack: $stack');
      rethrow;
    }
  }

  @override
  Future<void> signInWithApple() async {
    debugPrint('VIBERADAR: Starting Sign in with Apple...');
    try {
      if (kIsWeb) {
        // Web: Firebase drives Apple's OAuth popup flow, using the provider's
        // Services ID + code-flow config set in the Firebase console.
        final provider = OAuthProvider('apple.com')
          ..addScope('email')
          ..addScope('name');
        await _auth.signInWithPopup(provider);
      } else if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        // Apple platforms: native ASAuthorization sheet (best UX; identified by
        // the bundle id, so no Services ID needed).
        await _signInWithAppleNative();
      } else {
        // Android (and other non-Apple platforms): Firebase opens Apple's web
        // auth in a Custom Tab and returns through the Firebase handler. Needs
        // the Apple provider's Services ID + code-flow config set in Firebase.
        final provider = OAuthProvider('apple.com')
          ..addScope('email')
          ..addScope('name');
        await _auth.signInWithProvider(provider);
      }
      debugPrint('VIBERADAR: Apple sign-in complete!');
    } catch (e, stack) {
      debugPrint('VIBERADAR: Apple Sign-In error: $e');
      debugPrint('VIBERADAR: Stack: $stack');
      rethrow;
    }
  }

  /// Native Sign in with Apple (iOS/macOS): the on-device ASAuthorization sheet,
  /// exchanging Apple's ID token for a Firebase credential.
  Future<void> _signInWithAppleNative() async {
    // Apple requires a nonce: the SHA-256 hash goes to Apple, the raw value
    // goes to Firebase, which re-hashes and compares to bind the token.
    final rawNonce = _generateNonce();
    final hashedNonce = _sha256OfString(rawNonce);

    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );

    final idToken = appleCredential.identityToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError(
        'Apple Sign-In did not return an identity token. '
        'Check the Sign in with Apple capability and Firebase Apple provider.',
      );
    }

    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: idToken,
      rawNonce: rawNonce,
    );
    final userCredential = await _auth.signInWithCredential(oauthCredential);

    // Apple returns the name only on the FIRST sign-in; persist it so the
    // Firebase profile isn't left blank on subsequent logins.
    final user = userCredential.user;
    if (user != null &&
        (user.displayName == null || user.displayName!.isEmpty)) {
      final name = [appleCredential.givenName, appleCredential.familyName]
          .whereType<String>()
          .where((p) => p.isNotEmpty)
          .join(' ')
          .trim();
      if (name.isNotEmpty) {
        await user.updateDisplayName(name);
      }
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // intentional: best-effort Google session cleanup; Firebase sign-out
      // below will still run, so the user is effectively signed out regardless.
    }
    await _auth.signOut();
  }
}

/// Generates a cryptographically secure random nonce for Sign in with Apple.
String _generateNonce([int length = 32]) {
  const charset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
  final random = Random.secure();
  return List.generate(
    length,
    (_) => charset[random.nextInt(charset.length)],
  ).join();
}

/// SHA-256 of [input], hex-encoded — used to hash the Apple nonce.
String _sha256OfString(String input) =>
    sha256.convert(utf8.encode(input)).toString();
