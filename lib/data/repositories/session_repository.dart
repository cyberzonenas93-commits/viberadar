import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/config/firebase_runtime_config.dart';
import '../../models/session_state.dart';

abstract class SessionRepository {
  Stream<SessionState> sessionChanges();

  Future<void> signInWithEmail({
    required String email,
    required String password,
  });

  Future<void> signInWithGoogle();

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
  Future<void> signOut() async {}
}

class FirebaseSessionRepository implements SessionRepository {
  FirebaseSessionRepository({
    required FirebaseAuth auth,
    required GoogleSignIn googleSignIn,
    required FirebaseRuntimeConfig config,
  })  : _auth = auth,
        _googleSignIn = googleSignIn;

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  @override
  Stream<SessionState> sessionChanges() {
    return _auth.authStateChanges().map((user) {
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
    });
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
  Future<void> signInWithGoogle() async {
    // Google Sign-In v7 API
    final googleUser = await _googleSignIn.authenticate();

    final authorization = await _googleSignIn.authorizationClient
        .authorizationForScopes(<String>['email']);
    if (authorization == null) return;

    final credential = GoogleAuthProvider.credential(
      accessToken: authorization.accessToken,
    );

    await _auth.signInWithCredential(credential);
  }

  @override
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
