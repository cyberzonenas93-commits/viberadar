import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Regression guard for the `.env` asset wiring.
///
/// The app reads every client-side API key (Spotify, Apple Music, YouTube,
/// OpenAI) from `.env` via `dotenv.load(fileName: '.env')` in `main.dart`.
/// `flutter_dotenv` loads that file through Flutter's asset bundle, so it ONLY
/// works while `.env` is declared under `flutter: assets:` in `pubspec.yaml`.
///
/// Dropping that declaration makes `dotenv.load()` throw at startup (silently
/// swallowed), leaving every key empty — which silently breaks in-app search,
/// artist pages, and the AI Copilot (it falls back to canned replies). This
/// test fails loudly if that wiring regresses.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('.env is bundled as a Flutter asset and exposes non-empty API keys',
      () async {
    await dotenv.load(fileName: '.env');

    const requiredKeys = [
      'SPOTIFY_CLIENT_ID',
      'SPOTIFY_CLIENT_SECRET',
      'APPLE_MUSIC_TOKEN',
      'OPENAI_API_KEY',
      'YOUTUBE_DATA_API_KEY',
    ];

    for (final key in requiredKeys) {
      final value = dotenv.env[key];
      expect(
        value != null && value.trim().isNotEmpty,
        isTrue,
        reason: '$key is missing or empty. Is `.env` still declared under '
            'flutter/assets in pubspec.yaml, and does the local `.env` have a '
            'value for $key?',
      );
    }
  });
}
