import 'app_config.dart';

class SettingsInitializer {
  /// On first launch, pre-populate OpenAI key from .env if not already set.
  /// The API key is injected via --dart-define=OPENAI_API_KEY at build time.
  static Future<void> initialize() async {
    final existing = await AppConfig.getOpenAiKey();
    if (existing == null || existing.isEmpty) {
      const apiKey = String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');
      if (apiKey.isNotEmpty) {
        await AppConfig.setOpenAiKey(apiKey);
      }
      const model = String.fromEnvironment('OPENAI_MODEL', defaultValue: '');
      if (model.isNotEmpty) {
        await AppConfig.setOpenAiModel(model);
      }
    }
  }
}
