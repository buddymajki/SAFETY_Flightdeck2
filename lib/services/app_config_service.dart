// File: lib/services/app_config_service.dart

import 'package:flutter/material.dart';

// Create a new service for application configuration, primarily for localization.
class AppConfigService extends ChangeNotifier {
  // Default language is English
  String _currentLanguageCode = 'en';

  String get currentLanguageCode => _currentLanguageCode;

  // The primary method to change the language.
  void setLanguage(String code) {
    if (_currentLanguageCode != code) {
      _currentLanguageCode = code;
      // In a real app, this is where you would save to SharedPrefs.
      notifyListeners();
    }
  }

  // Get the display language code (e.g., 'en', 'de')
  String get displayLanguageCode {
      // Logic to return 'en' or 'de'
      return _currentLanguageCode;
  }
}