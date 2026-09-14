// File: lib/services/app_config_service.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Create a new service for application configuration, primarily for localization.
class AppConfigService extends ChangeNotifier {
  static const String _languageKey = 'app_language_code';
  static const List<String> supportedLanguages = ['en', 'de', 'it', 'fr'];

  // Default language is English
  String _currentLanguageCode = 'en';

  String get currentLanguageCode => _currentLanguageCode;

  AppConfigService() {
    _restoreLanguage();
  }

  Future<void> _restoreLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_languageKey);
      if (saved != null && supportedLanguages.contains(saved) && saved != _currentLanguageCode) {
        _currentLanguageCode = saved;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[AppConfigService] Could not restore language: $e');
    }
  }

  // The primary method to change the language. Persisted so it survives restarts.
  void setLanguage(String code) {
    if (_currentLanguageCode != code) {
      _currentLanguageCode = code;
      notifyListeners();
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setString(_languageKey, code))
          .catchError((e) {
        debugPrint('[AppConfigService] Could not save language: $e');
        return false;
      });
    }
  }

  // Get the display language code (e.g., 'en', 'de')
  String get displayLanguageCode {
      // Logic to return 'en' or 'de'
      return _currentLanguageCode;
  }
}