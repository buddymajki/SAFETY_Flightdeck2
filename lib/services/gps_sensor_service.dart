// File: lib/services/gps_sensor_service.dart

import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Service for handling GPS and sensor data
/// Provides platform-specific implementations for Android/iOS
/// Web platform is not supported
class GpsSensorService extends ChangeNotifier {
  // Stream subscriptions
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;

  // Current state
  bool _isTracking = false;
  bool _hasLocationPermission = false;
  bool _hasBackgroundPermission = false;
  bool _hasSensorPermission = false;
  Position? _lastPosition;
  AccelerometerEvent? _lastAccelerometer;
  GyroscopeEvent? _lastGyroscope;
  String? _errorMessage;

  // Callbacks
  Function(Position)? onPositionUpdate;
  Function(AccelerometerEvent)? onAccelerometerUpdate;
  Function(GyroscopeEvent)? onGyroscopeUpdate;
  Function(String)? onError;

  // Getters
  bool get isTracking => _isTracking;
  bool get hasLocationPermission => _hasLocationPermission;
  bool get hasBackgroundPermission => _hasBackgroundPermission;
  bool get hasSensorPermission => _hasSensorPermission;
  bool get isSupported => !kIsWeb;
  Position? get lastPosition => _lastPosition;
  AccelerometerEvent? get lastAccelerometer => _lastAccelerometer;
  GyroscopeEvent? get lastGyroscope => _lastGyroscope;
  String? get errorMessage => _errorMessage;

  /// Check if platform supports GPS tracking
  static bool get platformSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Check and request all required permissions
  Future<PermissionStatus> checkAndRequestPermissions() async {
    if (!platformSupported) {
      _errorMessage = 'GPS tracking is not supported on this platform';
      notifyListeners();
      return PermissionStatus.denied;
    }

    try {
      // Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _errorMessage = 'Location services are disabled. Please enable them in settings.';
        notifyListeners();
        return PermissionStatus.denied;
      }

      // Request location permission
      var locationStatus = await Permission.location.status;
      if (locationStatus.isDenied) {
        locationStatus = await Permission.location.request();
      }
      _hasLocationPermission = locationStatus.isGranted;

      if (!_hasLocationPermission) {
        _errorMessage = 'Location permission is required for flight tracking';
        notifyListeners();
        return locationStatus;
      }

      // Request background location permission (Android only for API 29+)
      if (Platform.isAndroid) {
        var backgroundStatus = await Permission.locationAlways.status;
        if (backgroundStatus.isDenied) {
          backgroundStatus = await Permission.locationAlways.request();
        }
        _hasBackgroundPermission = backgroundStatus.isGranted;
      } else {
        // iOS handles this through the plist configuration
        _hasBackgroundPermission = true;
      }

      // Request sensor permission (iOS only)
      if (Platform.isIOS) {
        var sensorStatus = await Permission.sensors.status;
        if (sensorStatus.isDenied) {
          sensorStatus = await Permission.sensors.request();
        }
        _hasSensorPermission = sensorStatus.isGranted || sensorStatus.isLimited;
      } else {
        // Android doesn't require explicit sensor permission
        _hasSensorPermission = true;
      }

      // Request notification permission for background service (Android 13+)
      if (Platform.isAndroid) {
        final notificationStatus = await Permission.notification.request();
        log('[GpsSensorService] Notification permission: $notificationStatus');
      }

      _errorMessage = null;
      notifyListeners();
      return locationStatus;
    } catch (e) {
      _errorMessage = 'Error checking permissions: $e';
      log('[GpsSensorService] Permission error: $e');
      notifyListeners();
      return PermissionStatus.denied;
    }
  }

  /// Request battery optimization exemption (Android only)
  Future<bool> requestBatteryOptimizationExemption() async {
    if (!Platform.isAndroid) return true;

    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (status.isGranted) return true;

      final result = await Permission.ignoreBatteryOptimizations.request();
      return result.isGranted;
    } catch (e) {
      log('[GpsSensorService] Battery optimization error: $e');
      return false;
    }
  }

  /// Open app settings for manual permission configuration
  Future<bool> openAppSettings() async {
    return await Geolocator.openAppSettings();
  }

  /// Open location settings
  Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }

  /// Start GPS and sensor tracking
  /// 
  /// Parameters:
  /// - accuracy: GPS accuracy level (default: best)
  /// - distanceFilter: Minimum distance (meters) before generating a new update (default: 5m)
  /// - interval: Time interval between position updates (default: 1 second for flight tracking)
  /// 
  /// NOTE: The 1-second interval ensures real-time safety monitoring (airspace violations).
  /// Position uploads to Firestore are separately throttled in LiveTrackingService.
  Future<bool> startTracking({
    LocationAccuracy accuracy = LocationAccuracy.best,
    int distanceFilter = 5, // meters
    Duration? interval, // Defaults to 1 second if not specified
  }) async {
    if (!platformSupported) {
      _errorMessage = 'GPS tracking is not supported on this platform';
      notifyListeners();
      return false;
    }

    if (_isTracking) return true;

    // Check permissions first
    final permissionStatus = await checkAndRequestPermissions();
    if (!permissionStatus.isGranted) {
      return false;
    }

    try {
      // Configure location settings
      late LocationSettings locationSettings;

      if (Platform.isAndroid) {
        locationSettings = AndroidSettings(
          accuracy: accuracy,
          distanceFilter: distanceFilter,
          forceLocationManager: false,
          intervalDuration: interval ?? const Duration(seconds: 1),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'FlightDeck GPS Tracking',
            notificationText: 'Recording your flight...',
            notificationIcon: AndroidResource(
              name: 'ic_launcher',
              defType: 'mipmap',
            ),
            enableWakeLock: true,
          ),
        );
      } else if (Platform.isIOS) {
        locationSettings = AppleSettings(
          accuracy: accuracy,
          distanceFilter: distanceFilter,
          activityType: ActivityType.airborne,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
          allowBackgroundLocationUpdates: true,
        );
      } else {
        locationSettings = LocationSettings(
          accuracy: accuracy,
          distanceFilter: distanceFilter,
        );
      }

      // Start position stream
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) {
          _lastPosition = position;
          onPositionUpdate?.call(position);
          notifyListeners();
        },
        onError: (error) {
          _errorMessage = 'GPS error: $error';
          onError?.call(_errorMessage!);
          log('[GpsSensorService] Position stream error: $error');
        },
      );

      // Start accelerometer stream
      _accelerometerSubscription = accelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 100),
      ).listen(
        (AccelerometerEvent event) {
          _lastAccelerometer = event;
          onAccelerometerUpdate?.call(event);
        },
        onError: (error) {
          log('[GpsSensorService] Accelerometer error: $error');
        },
      );

      // Start gyroscope stream
      _gyroscopeSubscription = gyroscopeEventStream(
        samplingPeriod: const Duration(milliseconds: 100),
      ).listen(
        (GyroscopeEvent event) {
          _lastGyroscope = event;
          onGyroscopeUpdate?.call(event);
        },
        onError: (error) {
          log('[GpsSensorService] Gyroscope error: $error');
        },
      );

      _isTracking = true;
      _errorMessage = null;
      notifyListeners();

      log('[GpsSensorService] Tracking started');
      return true;
    } catch (e) {
      _errorMessage = 'Failed to start tracking: $e';
      onError?.call(_errorMessage!);
      log('[GpsSensorService] Start tracking error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Stop GPS and sensor tracking
  Future<void> stopTracking() async {
    await _positionSubscription?.cancel();
    await _accelerometerSubscription?.cancel();
    await _gyroscopeSubscription?.cancel();

    _positionSubscription = null;
    _accelerometerSubscription = null;
    _gyroscopeSubscription = null;

    _isTracking = false;
    notifyListeners();

    log('[GpsSensorService] Tracking stopped');
  }

  /// Get current position once
  Future<Position?> getCurrentPosition({
    LocationAccuracy accuracy = LocationAccuracy.best,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (!platformSupported) return null;

    try {
      final permissionStatus = await checkAndRequestPermissions();
      if (!permissionStatus.isGranted) return null;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: accuracy),
      ).timeout(timeout);

      _lastPosition = position;
      notifyListeners();
      return position;
    } catch (e) {
      _errorMessage = 'Failed to get position: $e';
      log('[GpsSensorService] Get position error: $e');
      notifyListeners();
      return null;
    }
  }

  /// Calculate distance between two positions in meters
  static double distanceBetween(
    double startLat,
    double startLon,
    double endLat,
    double endLon,
  ) {
    return Geolocator.distanceBetween(startLat, startLon, endLat, endLon);
  }

  /// Calculate bearing between two positions in degrees
  static double bearingBetween(
    double startLat,
    double startLon,
    double endLat,
    double endLon,
  ) {
    return Geolocator.bearingBetween(startLat, startLon, endLat, endLon);
  }

  /// Reset service state
  void reset() {
    stopTracking();
    _lastPosition = null;
    _lastAccelerometer = null;
    _lastGyroscope = null;
    _errorMessage = null;
    _hasLocationPermission = false;
    _hasBackgroundPermission = false;
    _hasSensorPermission = false;
    notifyListeners();
  }

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }
}
