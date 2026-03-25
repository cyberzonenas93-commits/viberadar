import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static const _keyOpenAiKey = 'openai_api_key';
  static const _keyOpenAiModel = 'openai_model';
  static const defaultModel = 'gpt-4.1';

  static Future<String?> getOpenAiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyOpenAiKey);
  }

  static Future<void> setOpenAiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyOpenAiKey, key);
  }

  static Future<String> getOpenAiModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyOpenAiModel) ?? defaultModel;
  }

  static Future<void> setOpenAiModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyOpenAiModel, model);
  }
}
