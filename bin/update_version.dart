import 'dart:io';

void main() async {
  print('🔄 Syncing version from pubspec.yaml to AppVersionService...');

  try {
    // Read pubspec.yaml
    final pubspecFile = File('pubspec.yaml');
    if (!pubspecFile.existsSync()) {
      print('❌ Error: pubspec.yaml not found!');
      exit(1);
    }

    final pubspecContent = pubspecFile.readAsStringSync();
    
    // Parse version using regex: version: X.Y.Z+N
    final versionRegex = RegExp(r'version:\s*([\d.]+)\+(\d+)');
    final match = versionRegex.firstMatch(pubspecContent);

    if (match == null) {
      print('❌ Error: Could not parse version from pubspec.yaml');
      print('   Expected format: version: X.Y.Z+N');
      print('   Example: version: 1.0.3+4');
      exit(1);
    }

    final appVersion = match.group(1)!;
    final buildNumber = match.group(2)!;

    print('📦 Found version: $appVersion (build $buildNumber)');

    // Generate AppVersionService content
    final appVersionServiceContent = '''/// AppVersionService - AUTO-GENERATED
/// 
/// This service manages the app version.
/// Version is automatically synced from pubspec.yaml.
/// 
/// To update version:
/// 1. Edit pubspec.yaml: version: X.Y.Z+N
/// 2. Run: dart bin/update_version.dart
/// 3. Build: flutter build apk --release
/// 
/// Current version: $appVersion (build $buildNumber)

class AppVersionService {
  // ===== AUTO-GENERATED FROM pubspec.yaml =====
  static const String _appVersion = '$appVersion';
  static const String _buildNumber = '$buildNumber';
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
    return '\$_appVersion (build \$_buildNumber)';
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
''';

    // Write to AppVersionService
    final appVersionServiceFile = File('lib/services/app_version_service.dart');
    appVersionServiceFile.writeAsStringSync(appVersionServiceContent);

    print('✅ AppVersionService updated successfully!');

    // Also update metadata.json
    final metadataFile = File('metadata.json');
    if (metadataFile.existsSync()) {
      final metadataContent = '''
{
  "version": "$appVersion",
  "buildNumber": "$buildNumber",
  "downloadUrl": "https://github.com/buddymajki/SAFETY_Flightdeck2/releases/download/v$appVersion/app-release.apk",
  "changelog": "FlightDeck v$appVersion (build $buildNumber)",
  "isForce": false
}
''';
      metadataFile.writeAsStringSync(metadataContent);
      print('✅ metadata.json updated successfully!');
    }

    print('');
    print('Version: $appVersion (build $buildNumber)');
    print('Files: ${appVersionServiceFile.path}');
    print('       ${metadataFile.path}');
    print('');
    print('✨ Ready to build!');
    print('Run: flutter build apk --release');
    print('Then: git add . && git commit -m "Release v$appVersion" && git push');
  } catch (e) {
    print('❌ Error: \$e');
    exit(1);
  }
}

