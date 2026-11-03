import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// Injectable backend interface
//
// Account deletion is performed by the trusted backend (`deleteMyAccount`).
// The callable purges user-owned data and deletes the Firebase Auth account via
// Admin SDK, avoiding partial client-side deletion when local auth is stale.
// ---------------------------------------------------------------------------

/// Thin interface over the actual backend call. Swap in a fake for tests
/// without touching Firebase SDK internals.
abstract class AccountDeletionBackend {
  Future<void> deleteAccount();
}

// ---------------------------------------------------------------------------
// Default (production) backend — uses real Firebase instances.
// ---------------------------------------------------------------------------

class _FirebaseAccountDeletionBackend implements AccountDeletionBackend {
  _FirebaseAccountDeletionBackend({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _functions;

  @override
  Future<void> deleteAccount() async {
    final callable = _functions.httpsCallable(
      'deleteMyAccount',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
    );
    await callable.call<void>();
  }
}

// ---------------------------------------------------------------------------
// AccountDeletionService
// ---------------------------------------------------------------------------

class AccountDeletionService {
  AccountDeletionService({FirebaseFunctions? functions})
    : _backend = _FirebaseAccountDeletionBackend(functions: functions);

  /// Named constructor for testing — accepts any [AccountDeletionBackend].
  AccountDeletionService.withBackend(AccountDeletionBackend backend)
    : _backend = backend;

  final AccountDeletionBackend _backend;

  /// Deletes the current account and user-owned data via the backend callable.
  Future<void> deleteAccount() => _backend.deleteAccount();
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final accountDeletionServiceProvider = Provider<AccountDeletionService>(
  (ref) => AccountDeletionService(),
);
