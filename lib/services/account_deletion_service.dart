import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// Injectable backend interface
//
// Thorough cleanup of the user's sub-collections (e.g. pairing docs, crates)
// is best handled by a Firestore `onDelete` Cloud Function triggered when the
// primary `users/{uid}` document is removed (follow-up task). This client is
// responsible only for:
//   1. Deleting the primary `users/{uid}` Firestore document.
//   2. Deleting the Firebase Auth account.
// Together these satisfy App Store Guideline 5.1.1(v).
// ---------------------------------------------------------------------------

/// Thin interface over the actual Firebase calls. Swap in a fake for tests
/// without needing to mock FirebaseAuth / FirebaseFirestore directly.
abstract class AccountDeletionBackend {
  /// Returns the current signed-in user's UID, or null if unauthenticated.
  String? get currentUserId;

  /// Deletes the `users/{uid}` document from Firestore.
  Future<void> deleteFirestoreDoc(String uid);

  /// Deletes the Firebase Auth account.
  ///
  /// May throw a [FirebaseAuthException] with code `requires-recent-login`
  /// if the credential is stale — callers should surface a re-auth prompt.
  Future<void> deleteAuthUser();
}

// ---------------------------------------------------------------------------
// Default (production) backend — uses real Firebase instances.
// ---------------------------------------------------------------------------

class _FirebaseAccountDeletionBackend implements AccountDeletionBackend {
  _FirebaseAccountDeletionBackend({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  @override
  String? get currentUserId => _auth.currentUser?.uid;

  @override
  Future<void> deleteFirestoreDoc(String uid) =>
      _firestore.collection('users').doc(uid).delete();

  @override
  Future<void> deleteAuthUser() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.delete();
  }
}

// ---------------------------------------------------------------------------
// AccountDeletionService
// ---------------------------------------------------------------------------

class AccountDeletionService {
  AccountDeletionService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _backend = _FirebaseAccountDeletionBackend(
          firestore: firestore,
          auth: auth,
        );

  /// Named constructor for testing — accepts any [AccountDeletionBackend].
  AccountDeletionService.withBackend(AccountDeletionBackend backend)
      : _backend = backend;

  final AccountDeletionBackend _backend;

  /// Deletes the current user's Firestore document and Firebase Auth account.
  ///
  /// Throws [StateError] if no user is signed in.
  ///
  /// If Firebase Auth requires re-authentication, a [FirebaseAuthException]
  /// with code `requires-recent-login` is rethrown so the UI can prompt the
  /// user to sign in again before retrying.
  Future<void> deleteAccount() async {
    final uid = _backend.currentUserId;
    if (uid == null) {
      throw StateError('No signed-in user');
    }

    // Delete the primary Firestore user document first.
    await _backend.deleteFirestoreDoc(uid);

    // Delete the Firebase Auth account.
    // FirebaseAuthException(code: 'requires-recent-login') propagates as-is.
    await _backend.deleteAuthUser();
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final accountDeletionServiceProvider = Provider<AccountDeletionService>(
  (ref) => AccountDeletionService(),
);
