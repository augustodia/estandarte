import 'package:shared_preferences/shared_preferences.dart';

class AppStorage {
  AppStorage._(this._prefs);

  static late AppStorage instance;
  final SharedPreferences _prefs;

  static Future<AppStorage> init() async {
    final prefs = await SharedPreferences.getInstance();
    instance = AppStorage._(prefs);
    return instance;
  }

  String? getString(String key) => _prefs.getString(key);
  Future<void> setString(String key, String value) => _prefs.setString(key, value);
  Future<void> remove(String key) => _prefs.remove(key);
}
