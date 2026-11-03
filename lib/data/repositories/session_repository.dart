import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  static const _localGuestModeKey = 'local_guest_mode_active';

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  // Repository lives for the app container lifetime.
  // ignore: close_sinks
  final StreamController<SessionState> _manualSessionEvents =
      StreamController<SessionState>.broadcast();

  @override
  Stream<SessionState> sessionChanges() async* {
    // Check "remember me" preference
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool('remember_me') ?? true;
    final localGuestMode = prefs.getBool(_localGuestModeKey) ?? false;

    if (localGuestMode) {
      yield const SessionState.demo();
      yield* _sessionEvents();
      return;
    }

    // ── Warm start: user already in memory ──
    final cached = _auth.currentUser;
    if (cached != null) {
      if (!rememberMe) {
        // User opted out of "keep me signed in" — sign out
        await _auth.signOut();
        yield _toState(null);
        yield* _sessionEvents();
        return;
      }
      yield _toState(cached);
      yield* _sessionEvents();
      return;
    }

    // ── Cold start: wait for Firebase to restore from Keychain ──
    if (!rememberMe) {
      // Not remembering — go straight to login
      yield _toState(null);
      yield* _sessionEvents();
      return;
    }

    // Wait up to 3 seconds for a non-null user from the auth stream.
    User? firstUser;
    try {
      firstUser = await _auth
          .authStateChanges()
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

    yield* _sessionEvents();
  }

  Stream<SessionState> _sessionEvents() {
    // Closed by the consumer when the returned stream subscription is canceled.
    // ignore: close_sinks
    final controller = StreamController<SessionState>();
    StreamSubscription<SessionState>? authSub;
    StreamSubscription<SessionState>? manualSub;

    controller.onListen = () {
      authSub = _auth
          .authStateChanges()
          .asyncMap(_stateForUser)
          .listen(controller.add, onError: controller.addError);
      manualSub = _manualSessionEvents.stream.listen(
        controller.add,
        onError: controller.addError,
      );
    };
    controller.onCancel = () async {
      await authSub?.cancel();
      await manualSub?.cancel();
    };

    return controller.stream;
  }

  Future<SessionState> _stateForUser(User? user) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_localGuestModeKey) ?? false) {
      return const SessionState.demo();
    }
    return _toState(user);
  }

  Future<void> _setLocalGuestMode(bool active) async {
    final prefs = await SharedPreferences.getInstance();
    if (active) {
      await prefs.setBool(_localGuestModeKey, true);
    } else {
      await prefs.remove(_localGuestModeKey);
    }
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
    if (isAnon) {
      return const SessionState.demo();
    }
    return SessionState(
      userId: user.uid,
      displayName: user.displayName ?? 'VibeRadar DJ',
      email: user.email ?? 'unknown@viberadar.app',
      providerLabel: user.providerData.isEmpty
          ? 'Email'
          : user.providerData.first.providerId,
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
    await _setLocalGuestMode(false);
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    try {
      await credential.user?.updateDisplayName(displayName);
    } catch (e, st) {
      developer.log(
        'Failed to set display name after registration',
        name: 'SessionRepository',
        error: e,
        stackTrace: st,
      );
    }
    _syncPostSignInProfile(credential.user, displayName: displayName);
  }

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _setLocalGuestMode(false);
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    _syncPostSignInProfile(credential.user);
  }

  @override
  Future<void> signInAnonymously() async {
    debugPrint('VIBERADAR: Starting local guest mode with mock data.');
    await _setLocalGuestMode(true);
    await _auth.signOut();
    _manualSessionEvents.add(const SessionState.demo());
    debugPrint('VIBERADAR: Local guest mode active.');
  }

  @override
  Future<void> signInWithGoogle() async {
    await _setLocalGuestMode(false);
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
      final userCredential = await _auth.signInWithCredential(credential);
      _syncPostSignInProfile(userCredential.user);
      debugPrint('VIBERADAR: Firebase sign-in complete!');
    } catch (e, stack) {
      debugPrint('VIBERADAR: Google Sign-In error: $e');
      debugPrint('VIBERADAR: Stack: $stack');
      rethrow;
    }
  }

  @override
  Future<void> signInWithApple() async {
    await _setLocalGuestMode(false);
    debugPrint('VIBERADAR: Starting Sign in with Apple...');
    try {
      if (kIsWeb) {
        // Web: Firebase drives Apple's OAuth popup flow, using the provider's
        // Services ID + code-flow config set in the Firebase console.
        final provider = OAuthProvider('apple.com')
          ..addScope('email')
          ..addScope('name');
        final credential = await _auth.signInWithPopup(provider);
        _syncPostSignInProfile(credential.user);
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
        final credential = await _auth.signInWithProvider(provider);
        _syncPostSignInProfile(credential.user);
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
    final provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    final userCredential = await _auth.signInWithProvider(provider);

    // Apple returns the name only on the FIRST sign-in; persist it so the
    // Firebase profile isn't left blank on subsequent logins.
    final user = userCredential.user;
    final name = _appleDisplayName(userCredential.additionalUserInfo?.profile);
    if (user != null &&
        name != null &&
        (user.displayName == null || user.displayName!.isEmpty)) {
      // The user is already signed in. A display-name update failure (network
      // blip, internal error) must NOT surface as a sign-in error.
      try {
        await user.updateDisplayName(name);
      } catch (e) {
        developer.log(
          'Apple display-name update failed (non-fatal)',
          name: 'SessionRepository',
          error: e,
        );
      }
      _syncPostSignInProfile(user, displayName: name);
    } else {
      _syncPostSignInProfile(user);
    }
  }

  void _syncPostSignInProfile(User? user, {String? displayName}) {
    if (user == null || user.isAnonymous) return;
    unawaited(_ensurePostSignInProfile(user, displayName: displayName));
  }

  Future<void> _ensurePostSignInProfile(
    User user, {
    String? displayName,
  }) async {
    final requestedName = displayName?.trim();
    final authName = user.displayName?.trim();
    final resolvedName = requestedName?.isNotEmpty == true
        ? requestedName!
        : authName?.isNotEmpty == true
        ? authName!
        : 'VibeRadar DJ';
    try {
      final db = FirebaseFirestore.instance;
      await Future.wait([
        db.collection('users').doc(user.uid).set({
          'display_name': resolvedName,
          'preferences': {'region': 'Global'},
        }, SetOptions(merge: true)),
        db.collection('social_profiles').doc(user.uid).set({
          'userId': user.uid,
          'displayName': resolvedName,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)),
      ]);
    } catch (e, st) {
      developer.log(
        'Failed to initialize signed-in user profile',
        name: 'SessionRepository',
        error: e,
        stackTrace: st,
      );
    }
  }

  @override
  Future<void> signOut() async {
    await _setLocalGuestMode(false);
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // intentional: best-effort Google session cleanup; Firebase sign-out
      // below will still run, so the user is effectively signed out regardless.
    }
    await _auth.signOut();
    _manualSessionEvents.add(_toState(null));
  }
}

String? _appleDisplayName(Map<String, dynamic>? profile) {
  if (profile == null) return null;
  final directName = profile['name'];
  if (directName is String && directName.trim().isNotEmpty) {
    return directName.trim();
  }
  final parts = <String>[
    if (profile['given_name'] case final String given when given.isNotEmpty)
      given,
    if (profile['family_name'] case final String family when family.isNotEmpty)
      family,
  ];
  final joined = parts.join(' ').trim();
  return joined.isEmpty ? null : joined;
}
