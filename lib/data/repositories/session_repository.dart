import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../models/session_state.dart';

abstract class SessionRepository {
  Stream<SessionState> sessionChanges();

  Future<void> signInWithEmail({
    required String email,
    required String password,
  });

  Future<void> signInWithGoogle();

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
    // Only seed from currentUser if it is already available (non-null).
    // If null we must NOT yield yet — Riverpod stays in AsyncLoading and
    // the auth_gate shows a spinner while Firebase restores the persisted
    // token from the Keychain.  Yielding an unauthenticated state here
    // would immediately flip the UI to the login screen before Firebase
    // has had a chance to restore the session, causing every cold-start
    // to require a fresh sign-in.
    final cached = _auth.currentUser;
    if (cached != null) {
      yield _toState(cached);
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
    } catch (_) {}
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
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    await _auth.signOut();
  }
}
