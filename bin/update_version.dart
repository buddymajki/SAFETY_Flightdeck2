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
    
    // Parse version - supports both formats:
    // version: X.Y.Z+N (with build number)
    // version: X.Y.Z    (without build number)
    final versionWithBuildRegex = RegExp(r'version:\s*([\d.]+)\+(\d+)');
    final versionOnlyRegex = RegExp(r'version:\s*([\d.]+)');
    
    String appVersion;
    String buildNumber;
    
    final matchWithBuild = versionWithBuildRegex.firstMatch(pubspecContent);
    if (matchWithBuild != null) {
      appVersion = matchWithBuild.group(1)!;
      buildNumber = matchWithBuild.group(2)!;
    } else {
      final matchOnly = versionOnlyRegex.firstMatch(pubspecContent);
      if (matchOnly == null) {
        print('❌ Error: Could not parse version from pubspec.yaml');
        print('   Expected format: version: X.Y.Z or version: X.Y.Z+N');
        print('   Example: version: 1.0.13');
        exit(1);
      }
      appVersion = matchOnly.group(1)!;
      // Auto-generate build number from version parts
      final parts = appVersion.split('.');
      final major = int.tryParse(parts[0]) ?? 0;
      final minor = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
      final patch = int.tryParse(parts.length > 2 ? parts[2] : '0') ?? 0;
      buildNumber = '${major * 10000 + minor * 100 + patch}';
    }

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
    print('Then:');
    print('  git add . && git commit -m "Release v$appVersion" && git push');
    print('  git tag v$appVersion && git push origin --tags');
    print('  gh release upload v$appVersion build/app/outputs/flutter-apk/app-release.apk --clobber');
  } catch (e) {
    print('❌ Error: \$e');
    exit(1);
  }
}

