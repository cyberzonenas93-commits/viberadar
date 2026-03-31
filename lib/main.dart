import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'services/youtube_search_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // macOS-only: remove the default 'flutter.' key prefix so that keys written
  // via `defaults write` are found directly by SharedPreferences.
  if (Platform.isMacOS) {
    SharedPreferences.setPrefix('');
  }

  // Load environment variables
  await dotenv.load(fileName: '.env');

  // macOS desktop window setup (skip on iOS/Android)
  if (Platform.isMacOS) {
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

  // Clear stale YouTube quota flags from previous sessions
  await YoutubeSearchService().resetQuota();

  final bootstrap = await AppBootstrap.initialize();
  runApp(
    ProviderScope(
      overrides: bootstrap.providerOverrides.cast(),
      child: VibeRadarApp(bootstrap: bootstrap),
    ),
  );
}
