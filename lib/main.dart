import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'core/platform.dart';
import 'services/secure_storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Remove the default 'flutter.' key prefix so that keys written via
  // `defaults write com.viberadar.viberadar openai_api_key "..."` are
  // found directly by SharedPreferences without a prefix mismatch.
  SharedPreferences.setPrefix('');

  // Local development convenience only. Web builds should not depend on a
  // bundled .env asset because any bundled asset is publicly downloadable.
  if (!kIsWeb) {
    try {
      await dotenv.load(fileName: '.env');
    } catch (error) {
      developer.log(
        'No .env asset loaded; continuing with dart-defines/user settings.',
        name: 'Bootstrap',
        error: error,
      );
    }
  }

  // One-time migration: move any OpenAI API key from SharedPreferences to
  // Keychain. Non-fatal — failures log and the app continues using the env var.
  await _migrateOpenAiKeyToKeychain();

  // Desktop window setup only. Mobile (iOS/Android) and web have no
  // window_manager plugin, so calling it there would crash at launch.
  if (!kIsWeb && !isMobileForm) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1280, 820),
      minimumSize: Size(1100, 700),
      center: true,
      title: 'VibeRadar',
      titleBarStyle: TitleBarStyle.hidden,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  final bootstrap = await AppBootstrap.initialize();
  runApp(
    ProviderScope(
      overrides: bootstrap.providerOverrides.cast(),
      child: VibeRadarApp(bootstrap: bootstrap),
    ),
  );
}

/// Copies the OpenAI API key from SharedPreferences into Keychain if present
/// and not already migrated. Non-fatal: any failure is logged and the app
/// continues using the env-var fallback.
Future<void> _migrateOpenAiKeyToKeychain() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final legacyKey = prefs.getString('openai_api_key');
    if (legacyKey == null || legacyKey.trim().isEmpty) return;

    final secure = SecureStorageService();
    if (await secure.hasSecret(kOpenAiApiKey)) {
      await prefs.remove('openai_api_key');
      developer.log(
        'Legacy openai_api_key present but Keychain already populated — removed plaintext copy',
        name: 'KeyMigration',
      );
      return;
    }

    await secure.writeSecret(kOpenAiApiKey, legacyKey);
    await prefs.remove('openai_api_key');
    developer.log('Migrated openai_api_key from SharedPreferences to Keychain',
        name: 'KeyMigration');
  } catch (e, st) {
    developer.log('OpenAI key migration failed (non-fatal)',
        name: 'KeyMigration', error: e, stackTrace: st);
  }
}
