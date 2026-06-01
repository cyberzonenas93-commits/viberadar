import "package:flutter_test/flutter_test.dart";
import "package:viberadar/services/secure_storage_service.dart";

void main() {
  late InMemorySecureStorageBackend backend;
  late SecureStorageService service;

  setUp(() {
    backend = InMemorySecureStorageBackend();
    service = SecureStorageService(backend: backend);
  });

  group("SecureStorageService — round-trip", () {
    test("writeSecret then readSecret returns the written value", () async {
      await service.writeSecret(kOpenAiApiKey, "sk-test-123");
      final read = await service.readSecret(kOpenAiApiKey);
      expect(read, equals("sk-test-123"));
    });

    test("writeSecret overwrites prior value for the same key", () async {
      await service.writeSecret(kOpenAiApiKey, "sk-first");
      await service.writeSecret(kOpenAiApiKey, "sk-second");
      expect(await service.readSecret(kOpenAiApiKey), equals("sk-second"));
    });

    test("values are isolated per key", () async {
      await service.writeSecret(kOpenAiApiKey, "openai-value");
      await service.writeSecret(kSpotifyClientSecret, "spotify-value");

      expect(await service.readSecret(kOpenAiApiKey), equals("openai-value"));
      expect(
        await service.readSecret(kSpotifyClientSecret),
        equals("spotify-value"),
      );
    });
  });

  group("SecureStorageService — missing keys", () {
    test("readSecret returns null when key is absent", () async {
      expect(await service.readSecret("does-not-exist"), isNull);
    });

    test("hasSecret returns false when key is absent", () async {
      expect(await service.hasSecret(kOpenAiApiKey), isFalse);
    });
  });

  group("SecureStorageService — hasSecret", () {
    test("hasSecret returns true after writeSecret", () async {
      await service.writeSecret(kOpenAiApiKey, "sk-abc");
      expect(await service.hasSecret(kOpenAiApiKey), isTrue);
    });

    test("hasSecret returns false after deleteSecret", () async {
      await service.writeSecret(kOpenAiApiKey, "sk-abc");
      await service.deleteSecret(kOpenAiApiKey);
      expect(await service.hasSecret(kOpenAiApiKey), isFalse);
    });
  });

  group("SecureStorageService — delete", () {
    test("deleteSecret removes a stored secret", () async {
      await service.writeSecret(kOpenAiApiKey, "sk-delete-me");
      await service.deleteSecret(kOpenAiApiKey);
      expect(await service.readSecret(kOpenAiApiKey), isNull);
    });

    test("deleteSecret is a no-op for an unknown key", () async {
      await service.deleteSecret("never-written");
      expect(await service.readSecret("never-written"), isNull);
    });

    test("deleteSecret does not affect unrelated keys", () async {
      await service.writeSecret(kOpenAiApiKey, "openai");
      await service.writeSecret(kSpotifyClientSecret, "spotify");
      await service.deleteSecret(kOpenAiApiKey);

      expect(await service.readSecret(kOpenAiApiKey), isNull);
      expect(
        await service.readSecret(kSpotifyClientSecret),
        equals("spotify"),
      );
    });
  });

  group("SecureStorageService — named key constants", () {
    test("kOpenAiApiKey is the documented string", () {
      expect(kOpenAiApiKey, equals("openai_api_key"));
    });

    test("kSpotifyClientSecret is the documented string", () {
      expect(kSpotifyClientSecret, equals("spotify_client_secret"));
    });
  });
}
