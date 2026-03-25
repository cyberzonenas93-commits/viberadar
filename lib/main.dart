import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Remove the default 'flutter.' key prefix so that keys written via
  // `defaults write com.viberadar.viberadar openai_api_key "..."` are
  // found directly by SharedPreferences without a prefix mismatch.
  SharedPreferences.setPrefix('');

  // Load environment variables
  await dotenv.load(fileName: '.env');

  // macOS window setup
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1280, 820),
    minimumSize: Size(1100, 700),
    center: true,
    title: 'Vibe Radar',
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final bootstrap = await AppBootstrap.initialize();
  runApp(
    ProviderScope(
      overrides: bootstrap.providerOverrides.cast(),
      child: VibeRadarApp(bootstrap: bootstrap),
    ),
  );
}
