// File: lib/services/gps_sensor_service.dart

import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' 
    hide ServiceStatus; // Hide permission_handler's ServiceStatus if imported via permission_handler
import 'package:geolocator/geolocator.dart' as geolocator
    show ServiceStatus; // Explicitly import geolocator's ServiceStatus
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
  StreamSubscription<geolocator.ServiceStatus>? _locationServiceSubscription;
  Timer? _positionTimeoutTimer;

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

      PermissionStatus locationStatus;
      if (Platform.isIOS) {
        // On iOS, use geolocator's requestPermission for best results
        final geolocatorPermission = await Geolocator.checkPermission();
        if (geolocatorPermission == LocationPermission.denied || geolocatorPermission == LocationPermission.deniedForever) {
          final newPermission = await Geolocator.requestPermission();
          if (newPermission == LocationPermission.denied || newPermission == LocationPermission.deniedForever) {
            _hasLocationPermission = false;
            _errorMessage = 'Location permission is required for flight tracking';
            notifyListeners();
            return PermissionStatus.denied;
          }
        }
        _hasLocationPermission = true;
        locationStatus = PermissionStatus.granted;
      } else {
        // Android: use permission_handler
        locationStatus = await Permission.location.status;
        if (locationStatus.isDenied) {
          locationStatus = await Permission.location.request();
        }
        _hasLocationPermission = locationStatus.isGranted;
        if (!_hasLocationPermission) {
          _errorMessage = 'Location permission is required for flight tracking';
          notifyListeners();
          return locationStatus;
        }
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
    if (Platform.isIOS) {
      // On iOS, open location settings directly
      return await Geolocator.openLocationSettings();
    } else {
      return await Geolocator.openAppSettings();
    }
  }

  /// Open location settings
  Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }

  /// Auto-start GPS tracking silently
  /// Returns: true if tracking started successfully, false otherwise
  /// Does NOT throw errors - just logs and continues
  Future<bool> autoStartTracking() async {
    if (!platformSupported) {
      log('[GpsSensorService] AutoStart: Platform not supported');
      return false;
    }

    // Always ensure the location service monitor is running
    // This watches for GPS being toggled on/off in system settings
    _ensureLocationServiceMonitor();

    if (_isTracking) {
      log('[GpsSensorService] AutoStart: Already tracking');
      return true;
    }

    try {
      // Silently check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        log('[GpsSensorService] AutoStart: Location services disabled');
        return false;
      }

      // Attempt to start tracking
      // If permissions are not granted, startTracking() will handle it gracefully
      final success = await startTracking();
      if (success) {
        log('[GpsSensorService] AutoStart: GPS tracking started successfully');
        return true;
      } else {
        log('[GpsSensorService] AutoStart: GPS tracking failed (permissions or other issue)');
        return false;
      }
    } catch (e) {
      log('[GpsSensorService] AutoStart error: $e');
      return false; // Silently fail - don't crash the app
    }
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
          
          // Reset timeout timer on each position update
          _positionTimeoutTimer?.cancel();
          _startPositionTimeout();
          
          notifyListeners();
        },
        onError: (error) {
          log('[GpsSensorService] Position stream error: $error');
          _errorMessage = 'GPS error: $error';
          onError?.call(_errorMessage!);
          
          // Don't kill tracking on transient errors - let the timeout handle it
          // The stream may recover on its own
          notifyListeners();
        },
        cancelOnError: false, // Keep stream alive through transient errors
      );
      
      // Ensure location service monitor is running
      // This handles the case where user disables GPS in system settings
      _ensureLocationServiceMonitor();

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
    await _locationServiceSubscription?.cancel();
    _positionTimeoutTimer?.cancel();

    _positionSubscription = null;
    _accelerometerSubscription = null;
    _gyroscopeSubscription = null;
    _locationServiceSubscription = null;
    _positionTimeoutTimer = null;

    _isTracking = false;
    _lastPosition = null; // Clear so status bar reflects reality
    notifyListeners();

    log('[GpsSensorService] Tracking stopped');
  }

  /// Internal method to stop tracking streams and notify UI
  /// Called when location service is disabled or unrecoverable error.
  /// IMPORTANT: Does NOT cancel _locationServiceSubscription — that monitor
  /// must stay alive so we can detect when GPS is re-enabled.
  void _stopTrackingInternal() {
    _positionTimeoutTimer?.cancel();
    _positionSubscription?.cancel();
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();

    _positionSubscription = null;
    _positionTimeoutTimer = null;
    _accelerometerSubscription = null;
    _gyroscopeSubscription = null;
    // NOTE: _locationServiceSubscription is intentionally kept alive

    if (_isTracking) {
      _isTracking = false;
      _lastPosition = null; // Clear so status bar shows red (no GPS)
      notifyListeners();
      log('[GpsSensorService] Tracking stopped due to error or service disabled');
    }
  }

  /// Monitor if we consistently receive position updates
  /// If no update for 30 seconds, assume GPS connection is lost
  /// (30s is generous - allows for tunnels, indoor brief moments, etc.)
  void _startPositionTimeout() {
    _positionTimeoutTimer?.cancel();
    _positionTimeoutTimer = Timer(const Duration(seconds: 30), () {
      log('[GpsSensorService] Position timeout - no update for 30 seconds');
      _lastPosition = null; // Signal that we lost GPS fix
      notifyListeners();
      // Don't stop tracking entirely - stream may recover
      // Just clear the position so UI shows "searching" state
    });
  }

  /// Ensure the location service monitor is running (idempotent).
  /// Watches for GPS being toggled on/off in Android system settings.
  /// When user disables GPS → stop tracking.
  /// When user re-enables GPS → auto-restart tracking.
  /// This monitor stays alive even when tracking is stopped.
  void _ensureLocationServiceMonitor() {
    // Already running? Don't start a duplicate.
    if (_locationServiceSubscription != null) return;

    log('[GpsSensorService] Starting location service monitor');
    _locationServiceSubscription = 
        Geolocator.getServiceStatusStream().listen(
      (geolocator.ServiceStatus status) {
        log('[GpsSensorService] Location service status changed: $status');
        
        if (status == geolocator.ServiceStatus.disabled) {
          // User disabled GPS in system settings
          log('[GpsSensorService] Location service disabled by user');
          _stopTrackingInternal();
        } else if (status == geolocator.ServiceStatus.enabled) {
          // User re-enabled GPS - auto-restart tracking
          log('[GpsSensorService] Location service re-enabled - auto-restarting');
          if (!_isTracking) {
            autoStartTracking();
          }
        }
      },
      onError: (error) {
        log('[GpsSensorService] Location service monitor error: $error');
      },
    );
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
