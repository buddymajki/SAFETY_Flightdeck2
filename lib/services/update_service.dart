import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
// ============================================================
// RÉGI IMPORT-OK – KOMMENTÁLVA (GitHub / Google Drive letöltés)
// Visszaállításhoz töröld a komment jeleket:
// ============================================================
// import 'package:dio/dio.dart';
// import 'package:path_provider/path_provider.dart';
// import 'dart:io';
// import 'dart:convert';
// import 'package:flutter/services.dart';
// ============================================================
import 'app_version_service.dart';

/// Frissítési infó – Firestore-ból töltve
class UpdateInfo {
  final String version;
  final String changelog;
  final bool isForceUpdate;
  // final String downloadUrl;  // <-- kommentálva: régebben GitHub/Google Drive APK URL volt

  UpdateInfo({
    required this.version,
    required this.changelog,
    required this.isForceUpdate,
    // required this.downloadUrl,
  });

  factory UpdateInfo.fromFirestore(DocumentSnapshot doc) {
    return UpdateInfo(
      version: doc['version'] ?? '',
      changelog: doc['changelog'] ?? '',
      isForceUpdate: doc['isForceUpdate'] ?? false,
      // downloadUrl: doc['downloadUrl'] ?? '',
    );
  }

  // ============================================================
  // RÉGI FACTORY – KOMMENTÁLVA (Google Drive / GitHub metadata.json)
  // Visszaállításhoz töröld a komment jeleket:
  // ============================================================
  // factory UpdateInfo.fromJson(Map<String, dynamic> json) {
  //   return UpdateInfo(
  //     version: json['version'] ?? '',
  //     downloadUrl: json['downloadUrl'] ?? '',
  //     changelog: json['changelog'] ?? '',
  //     isForceUpdate: json['isForce'] ?? json['isForceUpdate'] ?? false,
  //   );
  // }
}

class UpdateService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ============================================================
  // RÉGI MEZŐK – KOMMENTÁLVA (APK letöltéshez kelltek)
  // ============================================================
  // final Dio _dio = Dio();
  // static const platform = MethodChannel('com.example.flightdeck/update');
  // double _downloadProgress = 0.0;
  // ============================================================

  UpdateInfo? _updateInfo;
  bool _isChecking = false;
  String _lastError = '';

  UpdateInfo? get updateInfo => _updateInfo;
  bool get isChecking => _isChecking;
  String get lastError => _lastError;
  // double get downloadProgress => _downloadProgress;  // <-- kommentálva

  /// Aktuális app verzió
  String get appVersion => AppVersionService.getVersionSync();

  // ============================================================
  // AKTÍV: Firestore alapú verzió-ellenőrzés
  //
  // Hogyan kell karbantartani:
  //   Amikor új APK-t töltösz fel Firebase App Distribution-ba,
  //   a release.ps1 script automatikusan frissíti a Firestore-t:
  //
  //   Collection: app_updates
  //   Documents:  android, ios, latest
  //   Mezők:
  //     version:       "1.0.40"
  //     changelog:     "Bug fixes, new features..."
  //     isForceUpdate: false
  //
  //   Az app először a platform-specifikus dokumentumot olvassa
  //   (android/ios), majd fallback a 'latest' dokumentumra.
  // ============================================================

  /// Returns the platform-specific Firestore document ID ("android" or "ios")
  String get _platformDocId {
    if (kIsWeb) return 'latest';

    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      default:
        return 'latest';
    }
  }

  Future<bool> checkForUpdates() async {
    try {
      _isChecking = true;
      _lastError = '';
      notifyListeners();

      // Web: no in-app update prompts
      if (kIsWeb) {
        _isChecking = false;
        notifyListeners();
        return false;
      }

      // 1) Try platform-specific document first (android / ios)
      final platformId = _platformDocId;
      DocumentSnapshot doc = await _firestore
          .collection('app_updates')
          .doc(platformId)
          .get();

      // 2) Fallback to 'latest' if platform doc doesn't exist
      if (!doc.exists) {
        debugPrint('[Update] app_updates/$platformId not found, trying app_updates/latest...');
        doc = await _firestore
            .collection('app_updates')
            .doc('latest')
            .get();
      }

      if (!doc.exists) {
        debugPrint('[Update] Firestore app_updates document does not exist (tried: $platformId, latest).');
        _isChecking = false;
        notifyListeners();
        return false;
      }

      _updateInfo = UpdateInfo.fromFirestore(doc);
      debugPrint('[Update] Firestore version: ${_updateInfo!.version} (from ${doc.id}), current: $appVersion');

      final hasUpdate = _compareVersions(_updateInfo!.version, appVersion) > 0;

      _isChecking = false;
      notifyListeners();
      return hasUpdate;
    } catch (e) {
      debugPrint('[Update] Error checking for updates via Firestore: $e');
      _lastError = 'FIRESTORE_ERROR: $e';
      _isChecking = false;
      notifyListeners();
      return false;
    }
  }

  // ============================================================
  // AKTÍV: Firebase App Distribution teszter oldal megnyítása
  //
  // A teszterek emailben kapnak értesítést automatikusan,
  // amikor új APK kerül fel Firebase App Distribution-ba.
  // Ez a metódus csak akkor kell, ha kézzel szerelnéd megnyitni a linket.
  // ============================================================
  Future<void> openFirebaseAppDistribution() async {
    // Firebase App Tester app page — this is the tester portal where
    // invited testers can see and download available releases.
    // On Android: opens in browser → redirects to App Tester app if installed,
    //             or shows download page for the tester app.
    // On iOS: opens the tester portal in Safari.
    const testerAppsUrl = 'https://appdistribution.firebase.google.com/testerapps';
    final uri = Uri.parse(testerAppsUrl);

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        debugPrint('[Update] Could not launch Firebase App Distribution URL.');
      }
    } catch (e) {
      debugPrint('[Update] Error opening Firebase App Distribution: $e');
    }
  }

  /// Open the correct update destination depending on platform.
  ///
  /// - iOS: opens TestFlight
  /// - Android: opens Firebase App Distribution tester portal
  /// - Web: no-op
  Future<void> openAppUpdateLink() async {
    if (kIsWeb) return;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // Opens the TestFlight app (or prompts install if not available)
      final uri = Uri.parse('itms-beta://');
      try {
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!launched) {
          debugPrint('[Update] Could not launch TestFlight.');
        }
      } catch (e) {
        debugPrint('[Update] Error opening TestFlight: $e');
      }
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      await openFirebaseAppDistribution();
      return;
    }
  }

  // ============================================================
  // RÉGI KÓDOK – KOMMENTÁLVA
  // Visszaállításhoz (pl. ha vissza akarod térni GitHub release-re):
  //   Töröld a komment jeleket az alábbi metódusokból.
  // ============================================================

  // /// Check for updates from Google Drive / GitHub metadata.json
  // ///
  // /// URL példák:
  // ///   Google Drive: https://drive.google.com/uc?id=FILE_ID&export=download
  // ///   GitHub (public): https://raw.githubusercontent.com/USER/REPO/master/metadata.json
  // ///
  // Future<bool> checkForUpdatesFromGoogleDrive(String metadataUrl) async {
  //   try {
  //     _isChecking = true;
  //     notifyListeners();
  //
  //     debugPrint('[Update] Checking for updates from metadata URL: $metadataUrl');
  //
  //     final response = await _dio.get(metadataUrl);
  //
  //     if (response.statusCode != 200) {
  //       _lastError = 'METADATA_HTTP_ERROR_${response.statusCode}';
  //       _isChecking = false;
  //       notifyListeners();
  //       return false;
  //     }
  //
  //     final jsonData = jsonDecode(response.data);
  //     _updateInfo = UpdateInfo.fromJson(jsonData);
  //
  //     debugPrint('[Update] Metadata version: ${_updateInfo!.version}, current: $appVersion');
  //     bool hasUpdate = _compareVersions(_updateInfo!.version, appVersion) > 0;
  //
  //     _lastError = '';
  //     _isChecking = false;
  //     notifyListeners();
  //     return hasUpdate;
  //   } on DioException catch (e) {
  //     _lastError = 'DIO_ERROR_${e.type}';
  //     debugPrint('[Update] DioException: ${e.type} - ${e.message}');
  //     _isChecking = false;
  //     notifyListeners();
  //     return false;
  //   } catch (e) {
  //     _lastError = 'PARSE_ERROR_${e.toString()}';
  //     debugPrint('[Update] Error: $e');
  //     _isChecking = false;
  //     notifyListeners();
  //     return false;
  //   }
  // }

  // /// APK letöltés (GitHub / Google Drive URL-ről)
  // Future<bool> downloadUpdate(Function(double progress) onProgress) async {
  //   if (_updateInfo == null) {
  //     _lastError = 'UPDATE_INFO_NULL';
  //     return false;
  //   }
  //   try {
  //     final appDir = await getApplicationCacheDirectory();
  //     final apkFile = File('${appDir.path}/flightdeck_${_updateInfo!.version}.apk');
  //
  //     if (await apkFile.exists()) {
  //       final size = await apkFile.length();
  //       if (size > 1000000) {
  //         _lastError = '';
  //         return true;
  //       } else {
  //         await apkFile.delete();
  //       }
  //     }
  //
  //     await _dio.download(
  //       _updateInfo!.downloadUrl,
  //       apkFile.path,
  //       onReceiveProgress: (received, total) {
  //         if (total != -1) {
  //           _downloadProgress = received / total;
  //           onProgress(_downloadProgress);
  //           notifyListeners();
  //         }
  //       },
  //     );
  //
  //     final size = await apkFile.length();
  //     if (size < 1000000) {
  //       _lastError = 'APK_FILE_TOO_SMALL_${size}_bytes';
  //       await apkFile.delete();
  //       return false;
  //     }
  //     _lastError = '';
  //     return true;
  //   } on DioException catch (e) {
  //     if (e.response?.statusCode == 404) {
  //       _lastError = 'APK_NOT_READY_404';
  //     } else {
  //       _lastError = 'DIO_ERROR_${e.type}_${e.response?.statusCode}';
  //     }
  //     return false;
  //   } catch (e) {
  //     _lastError = 'ERROR_${e.toString()}';
  //     return false;
  //   }
  // }

  // /// APK telepítés platform channel-en keresztül
  // Future<bool> installUpdate() async {
  //   if (_updateInfo == null) {
  //     _lastError = 'UPDATE_INFO_NULL_FOR_INSTALL';
  //     return false;
  //   }
  //   try {
  //     final appDir = await getApplicationCacheDirectory();
  //     final apkFile = File('${appDir.path}/flightdeck_${_updateInfo!.version}.apk');
  //
  //     if (!await apkFile.exists()) {
  //       _lastError = 'APK_FILE_NOT_FOUND_${appDir.path}';
  //       return false;
  //     }
  //
  //     final result = await platform.invokeMethod<bool>('installAPK', {
  //       'apkPath': apkFile.path,
  //     });
  //
  //     _lastError = '';
  //     return result ?? false;
  //   } on PlatformException catch (e) {
  //     _lastError = 'PLATFORM_ERROR_${e.code}_${e.message}';
  //     return false;
  //   } catch (e) {
  //     _lastError = 'INSTALL_ERROR_${e.toString()}';
  //     return false;
  //   }
  // }

  // ============================================================

  /// Verzió összehasonlítás ("1.0.0" formátum)
  int _compareVersions(String newVersion, String currentVersion) {
    final newParts = newVersion.split('.');
    final currentParts = currentVersion.split('.');

    for (int i = 0; i < 3; i++) {
      final newPart = int.tryParse(i < newParts.length ? newParts[i] : '0') ?? 0;
      final currentPart = int.tryParse(i < currentParts.length ? currentParts[i] : '0') ?? 0;

      if (newPart > currentPart) return 1;
      if (newPart < currentPart) return -1;
    }
    return 0;
  }

  void clear() {
    _updateInfo = null;
    // _downloadProgress = 0.0;  // <-- kommentálva
  }
}
