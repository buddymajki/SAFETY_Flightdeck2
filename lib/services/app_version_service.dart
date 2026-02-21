/// AppVersionService - AUTO-GENERATED
/// 
/// This service manages the app version.
/// Version is automatically synced from pubspec.yaml.
/// 
/// To update version:
/// 1. Edit pubspec.yaml: version: X.Y.Z+N
/// 2. Run: dart bin/update_version.dart
/// 3. Build: flutter build apk --release
/// 
/// Current version: 1.0.31 (build 10031)

class AppVersionService {
  // ===== AUTO-GENERATED FROM pubspec.yaml =====
  static const String _appVersion = '1.0.31';
  static const String _buildNumber = '10031';
  // ============================================

  /// Get app version (e.g., "1.0.3")
  static Future<String> getAppVersion() async {
    return _appVersion;
  }

  /// Get build number (e.g., "4")
  static Future<String> getBuildNumber() async {
    return _buildNumber;
  }

  /// Get full version with build number (e.g., "1.0.3 (build 4)")
  static Future<String> getFullVersion() async {
    return '$_appVersion (build $_buildNumber)';
  }

  /// Get cached version synchronously
  static String getCachedVersion() {
    return _appVersion;
  }

  /// For UpdateService - need to get the version without async
  static String getVersionSync() {
    return _appVersion;
  }
}
