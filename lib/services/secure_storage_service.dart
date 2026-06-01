import "dart:developer" as developer;

import "package:flutter_secure_storage/flutter_secure_storage.dart";

// ── Named key constants ──────────────────────────────────────────────────────
//
// Other code should use these symbolic names rather than raw strings, so the
// list of secrets stored in the Keychain is discoverable in one place.

/// Keychain key for the user-supplied OpenAI API key.
const String kOpenAiApiKey = "openai_api_key";

/// Keychain key for the Spotify OAuth client secret.
const String kSpotifyClientSecret = "spotify_client_secret";

// ── Backend interface (for testability) ─────────────────────────────────────
//
// [FlutterSecureStorage] hits a platform channel and is awkward to mock
// directly in unit tests. We instead define a tiny backend interface that the
// service depends on; production wraps [FlutterSecureStorage], tests inject an
// in-memory [InMemorySecureStorageBackend].

abstract class SecureStorageBackend {
  Future<void> write({required String key, required String value});
  Future<String?> read({required String key});
  Future<void> delete({required String key});
  Future<bool> containsKey({required String key});
}

/// Production backend that delegates to [FlutterSecureStorage] → macOS
/// Keychain / iOS Keychain / Android EncryptedSharedPreferences.
class _FlutterSecureStorageBackend implements SecureStorageBackend {
  _FlutterSecureStorageBackend(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<String?> read({required String key}) =>
      _storage.read(key: key);

  @override
  Future<void> delete({required String key}) =>
      _storage.delete(key: key);

  @override
  Future<bool> containsKey({required String key}) =>
      _storage.containsKey(key: key);
}

/// Simple in-memory backend for tests.
class InMemorySecureStorageBackend implements SecureStorageBackend {
  final Map<String, String> _values = {};

  Map<String, String> get snapshot => Map.unmodifiable(_values);

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }

  @override
  Future<bool> containsKey({required String key}) async =>
      _values.containsKey(key);
}

// ── Service ──────────────────────────────────────────────────────────────────

/// Thin wrapper around a [SecureStorageBackend] that provides a small,
/// testable surface for reading and writing secrets.
///
/// On macOS this maps to the Keychain; on iOS the Keychain; on Android the
/// encrypted shared preferences backed by the platform KeyStore.
///
/// The constructor accepts an optional [FlutterSecureStorage] for production
/// tweaks, or an explicit [SecureStorageBackend] for tests.
class SecureStorageService {
  SecureStorageService({
    FlutterSecureStorage? storage,
    SecureStorageBackend? backend,
  }) : _backend = backend ??
            _FlutterSecureStorageBackend(
              storage ??
                  const FlutterSecureStorage(
                    aOptions: AndroidOptions(
                      encryptedSharedPreferences: true,
                    ),
                    iOptions: IOSOptions(
                      accessibility: KeychainAccessibility.first_unlock,
                    ),
                  ),
            );

  final SecureStorageBackend _backend;

  /// Write [value] under [key]. Overwrites any existing value.
  Future<void> writeSecret(String key, String value) async {
    try {
      await _backend.write(key: key, value: value);
    } catch (e, st) {
      developer.log(
        "Failed to write secret for key=$key",
        name: "SecureStorageService",
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Read the secret stored under [key], or null if none is stored.
  Future<String?> readSecret(String key) async {
    try {
      return await _backend.read(key: key);
    } catch (e, st) {
      developer.log(
        "Failed to read secret for key=$key",
        name: "SecureStorageService",
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  /// Remove any secret stored under [key]. No-op if the key is absent.
  Future<void> deleteSecret(String key) async {
    try {
      await _backend.delete(key: key);
    } catch (e, st) {
      developer.log(
        "Failed to delete secret for key=$key",
        name: "SecureStorageService",
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Returns true if a non-null secret is stored under [key].
  Future<bool> hasSecret(String key) async {
    try {
      return await _backend.containsKey(key: key);
    } catch (e, st) {
      developer.log(
        "Failed to check secret existence for key=$key",
        name: "SecureStorageService",
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }
}
