import 'package:shared_preferences/shared_preferences.dart';

/// Handles caching of login credentials and preferences for seamless authentication.
class AppAuthCache {
  static const _keyCaregiverEmail = 'artspeak_cached_caregiver_email';
  static const _keyTherapistUsername = 'artspeak_cached_therapist_username';
  static const _keyRememberMe = 'artspeak_remember_me';

  /// Caches the last caregiver email entered or logged in.
  static Future<void> saveCaregiverEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCaregiverEmail, email.trim());
  }

  /// Retrieves the last cached caregiver email.
  static Future<String?> getCaregiverEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyCaregiverEmail);
  }

  /// Caches the last therapist username entered or logged in.
  static Future<void> saveTherapistUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTherapistUsername, username.trim());
  }

  /// Retrieves the last cached therapist username.
  static Future<String?> getTherapistUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyTherapistUsername);
  }

  /// Sets the "Remember Me" preference.
  static Future<void> setRememberMe(bool remember) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRememberMe, remember);
  }

  /// Checks if "Remember Me" is enabled (defaults to true).
  static Future<bool> isRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyRememberMe) ?? true;
  }

  /// Clears stored login credentials.
  static Future<void> clearAuthCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCaregiverEmail);
    await prefs.remove(_keyTherapistUsername);
  }
}
