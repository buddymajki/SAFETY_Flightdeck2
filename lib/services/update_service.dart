import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'app_version_service.dart';

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String changelog;
  final bool isForceUpdate;

  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.changelog,
    required this.isForceUpdate,
  });

  factory UpdateInfo.fromFirestore(DocumentSnapshot doc) {
    return UpdateInfo(
      version: doc['version'] ?? '',
      downloadUrl: doc['downloadUrl'] ?? '',
      changelog: doc['changelog'] ?? '',
      isForceUpdate: doc['isForceUpdate'] ?? false,
    );
  }

  /// Create UpdateInfo from JSON (from metadata.json)
  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'] ?? '',
      downloadUrl: json['downloadUrl'] ?? '',
      changelog: json['changelog'] ?? '',
      isForceUpdate: json['isForce'] ?? json['isForceUpdate'] ?? false,
    );
  }
}

class UpdateService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Dio _dio = Dio();
  
  // Android platform channel
  static const platform = MethodChannel('com.example.flightdeck/update');
  
  UpdateInfo? _updateInfo;
  bool _isChecking = false;
  double _downloadProgress = 0.0;
  String _lastError = '';
  
  UpdateInfo? get updateInfo => _updateInfo;
  bool get isChecking => _isChecking;
  double get downloadProgress => _downloadProgress;
  String get lastError => _lastError;

  /// Get current app version from AppVersionService
  String get appVersion => AppVersionService.getVersionSync();

  /// Ellenőriz az új verzióra Firestore-ban
  Future<bool> checkForUpdates() async {
    try {
      _isChecking = true;
      notifyListeners();

      final doc = await _firestore
          .collection('app_updates')
          .doc('latest')
          .get();

      if (!doc.exists) {
        _isChecking = false;
        notifyListeners();
        return false;
      }

      _updateInfo = UpdateInfo.fromFirestore(doc);

      // Verzió összehasonlítás
      bool hasUpdate = _compareVersions(_updateInfo!.version, appVersion) > 0;
      
      _isChecking = false;
      notifyListeners();

      return hasUpdate;
    } catch (e) {
      debugPrint('Error checking for updates: $e');
      _isChecking = false;
      notifyListeners();
      return false;
    }
  }

  /// Check for updates from Google Drive metadata.json (NO FIRESTORE NEEDED!)
  /// How to use:
  /// 1. Upload APK to Google Drive folder
  /// 2. Create metadata.json in same folder:
  ///    {
  ///      "version": "1.0.4",
  ///      "downloadUrl": "https://drive.google.com/uc?id=FILE_ID&export=download",
  ///      "changelog": "Bug fixes",
  ///      "isForce": false
  ///    }
  /// 3. Share folder with "Anyone with link"
  /// 4. Get metadata URL like: https://drive.google.com/uc?id=METADATA_FILE_ID&export=download
  /// 5. Call this method: checkForUpdatesFromGoogleDrive(metadataUrl)
  /// 
  /// Advantage: No need to update Firestore manually!
  Future<bool> checkForUpdatesFromGoogleDrive(String metadataUrl) async {
    try {
      _isChecking = true;
      notifyListeners();

      debugPrint('[Update] Checking for updates from Google Drive metadata...');
      debugPrint('[Update] Metadata URL: $metadataUrl');

      // Download metadata.json from Google Drive
      final response = await _dio.get(metadataUrl);
      
      if (response.statusCode != 200) {
        _lastError = 'METADATA_HTTP_ERROR_${response.statusCode}';
        debugPrint('[Update] HTTP error: ${response.statusCode}');
        _isChecking = false;
        notifyListeners();
        return false;
      }

      // Parse JSON
      final jsonData = jsonDecode(response.data);
      _updateInfo = UpdateInfo.fromJson(jsonData);

      debugPrint('[Update] Metadata loaded: version=${_updateInfo!.version}');

      // Version comparison
      bool hasUpdate = _compareVersions(_updateInfo!.version, appVersion) > 0;
      
      if (hasUpdate) {
        debugPrint('[Update] Update available: ${_updateInfo!.version} > $appVersion');
      } else {
        debugPrint('[Update] No update needed: ${_updateInfo!.version} <= $appVersion');
      }

      _lastError = '';
      _isChecking = false;
      notifyListeners();

      return hasUpdate;
    } on DioException catch (e) {
      _lastError = 'DIO_ERROR_${e.type}';
      debugPrint('[Update] DioException: ${e.type} - ${e.message}');
      _isChecking = false;
      notifyListeners();
      return false;
    } catch (e) {
      _lastError = 'PARSE_ERROR_${e.toString()}';
      debugPrint('[Update] Error checking for updates from Google Drive: $e');
      _isChecking = false;
      notifyListeners();
      return false;
    }
  }

  /// Download az APK fájlt
  Future<bool> downloadUpdate(Function(double progress) onProgress) async {
    if (_updateInfo == null) {
      _lastError = 'UPDATE_INFO_NULL';
      return false;
    }

    try {
      final appDir = await getApplicationCacheDirectory();
      final apkFile = File('${appDir.path}/flightdeck_${_updateInfo!.version}.apk');

      debugPrint('[Update] Cache dir: ${appDir.path}');

      // Ha már létezik az APK, ellenőrizze az integritást
      if (await apkFile.exists()) {
        final size = await apkFile.length();
        debugPrint('[Update] APK already exists, size: $size bytes');
        if (size > 1000000) {
          _lastError = '';
          return true;
        } else {
          debugPrint('[Update] Deleting corrupted APK');
          await apkFile.delete();
        }
      }

      debugPrint('[Update] Starting download from: ${_updateInfo!.downloadUrl}');

      await _dio.download(
        _updateInfo!.downloadUrl,
        apkFile.path,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            _downloadProgress = received / total;
            onProgress(_downloadProgress);
            notifyListeners();
            debugPrint('[Update] Downloaded: ${(received / 1024 / 1024).toStringAsFixed(2)} MB / ${(total / 1024 / 1024).toStringAsFixed(2)} MB');
          }
        },
      );

      // Ellenőrizze a letöltött fájlt
      final size = await apkFile.length();
      debugPrint('[Update] Download complete, APK size: ${(size / 1024 / 1024).toStringAsFixed(2)} MB');
      
      if (size < 1000000) {
        _lastError = 'APK_FILE_TOO_SMALL_${size}_bytes';
        debugPrint('[Update] ERROR: APK file is too small ($size bytes), probably corrupted or incomplete');
        await apkFile.delete();
        return false;
      }

      _lastError = '';
      return true;
    } on DioException catch (e) {
      _lastError = 'DIO_ERROR_${e.type}_${e.response?.statusCode}';
      debugPrint('[Update] DioException: ${e.type} - ${e.response?.statusCode} - ${e.message}');
      return false;
    } catch (e) {
      _lastError = 'ERROR_${e.toString()}';
      debugPrint('[Update] Error downloading update: $e');
      return false;
    }
  }

  /// Android platform channel segítségével telepíti az APK-t
  Future<bool> installUpdate() async {
    if (_updateInfo == null) {
      _lastError = 'UPDATE_INFO_NULL_FOR_INSTALL';
      return false;
    }

    try {
      final appDir = await getApplicationCacheDirectory();
      final apkFile = File('${appDir.path}/flightdeck_${_updateInfo!.version}.apk');

      if (!await apkFile.exists()) {
        _lastError = 'APK_FILE_NOT_FOUND_${appDir.path}';
        debugPrint('[Update] APK file not found: ${apkFile.path}');
        return false;
      }

      final size = await apkFile.length();
      debugPrint('[Update] APK file found, size: ${(size / 1024 / 1024).toStringAsFixed(2)} MB');

      // Platform channel hívás
      debugPrint('[Update] Calling platform channel to install APK');
      final result = await platform.invokeMethod<bool>('installAPK', {
        'apkPath': apkFile.path,
      });

      debugPrint('[Update] Platform channel result: $result');
      _lastError = '';
      return result ?? false;
    } on PlatformException catch (e) {
      _lastError = 'PLATFORM_ERROR_${e.code}_${e.message}';
      debugPrint('[Update] PlatformException: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      _lastError = 'INSTALL_ERROR_${e.toString()}';
      debugPrint('[Update] Error installing update: $e');
      return false;
    }
  }

  /// Verzió összehasonlítás (1.0.0 formátum)
  int _compareVersions(String newVersion, String currentVersion) {
    final newParts = newVersion.split('.');
    final currentParts = currentVersion.split('.');

    for (int i = 0; i < 3; i++) {
      final newPart = int.tryParse(newParts[i]) ?? 0;
      final currentPart = int.tryParse(currentParts[i]) ?? 0;

      if (newPart > currentPart) return 1;
      if (newPart < currentPart) return -1;
    }

    return 0; // Equal versions
  }

  /// Force az ASP cache-t
  void clear() {
    _updateInfo = null;
    _downloadProgress = 0.0;
  }
}
