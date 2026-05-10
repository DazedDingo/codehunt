import 'package:shared_preferences/shared_preferences.dart';

class Settings {
  static const _kBaseUrl = 'baseUrl';
  static const _kToken = 'token';
  static const _kProvider = 'provider';

  String baseUrl;
  String token;
  String provider;

  Settings({required this.baseUrl, required this.token, required this.provider});

  static Future<Settings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return Settings(
      baseUrl: prefs.getString(_kBaseUrl) ?? '',
      token: prefs.getString(_kToken) ?? '',
      provider: prefs.getString(_kProvider) ?? 'gemini',
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, baseUrl);
    await prefs.setString(_kToken, token);
    await prefs.setString(_kProvider, provider);
  }

  bool get configured => baseUrl.isNotEmpty && token.isNotEmpty;
}
