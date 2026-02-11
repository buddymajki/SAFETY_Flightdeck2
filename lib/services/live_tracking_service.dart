// File: lib/services/live_tracking_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tracked_flight.dart';
import '../models/alert_model.dart';
import 'alert_service.dart';
import 'connectivity_service.dart';
import 'profile_service.dart';

/// Represents a queued position update for offline support
class _PendingPositionUpdate {
  final TrackPoint position;
  final DateTime queuedAt;
  final Map<String, dynamic> additionalData;
  
  _PendingPositionUpdate({
    required this.position,
    required this.queuedAt,
    this.additionalData = const {},
  });
  
  Map<String, dynamic> toJson() => {
    'position': {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'altitude': position.altitude,
      'speed': position.speed,
      'heading': position.heading,
      'timestamp': position.timestamp.toIso8601String(),
    },
    'queuedAt': queuedAt.toIso8601String(),
    'additionalData': additionalData,
  };
  
  factory _PendingPositionUpdate.fromJson(Map<String, dynamic> json) {
    final posData = json['position'] as Map<String, dynamic>;
    return _PendingPositionUpdate(
      position: TrackPoint(
        latitude: posData['latitude'] ?? 0.0,
        longitude: posData['longitude'] ?? 0.0,
        altitude: posData['altitude'] ?? 0.0,
        speed: posData['speed'],
        heading: posData['heading'],
        timestamp: DateTime.tryParse(posData['timestamp'] ?? '') ?? DateTime.now(),
      ),
      queuedAt: DateTime.tryParse(json['queuedAt'] ?? '') ?? DateTime.now(),
      additionalData: Map<String, dynamic>.from(json['additionalData'] ?? {}),
    );
  }
}

/// Service for live tracking - sends pilot position to cloud for authorities
///
/// Features:
/// - GPS checks run at 1Hz (every 1 second) for real-time safety monitoring
/// - Safety checks (airspace/altitude violations) run on EVERY GPS update
/// - Position uploads to Firestore are THROTTLED (only every 12s or 50m movement)
/// - Only active when pilot is in flight
/// - Includes pilot identification and credential status
/// - Automatically removes pilot from tracking when flight ends
/// - **OFFLINE-FIRST**: Queues positions locally when offline
/// - Automatically syncs queued data when connectivity is restored
///
/// Configuration:
/// - GPS Check Frequency: Configured in GpsSensorService (default: 1 second)
/// - Upload Throttling: minUploadInterval (12s) and minDistanceMeters (50m)
/// - These settings balance real-time safety, cost efficiency, and battery life
class LiveTrackingService extends ChangeNotifier {
  static const String _enabledKey = 'live_tracking_enabled';
  static const String _pendingPositionsKey = 'pending_position_updates';
  static const String _lastFlightStateKey = 'last_flight_state';

  // ============================================
  // CONFIGURATION: Upload Throttling Settings
  // ============================================
  // Position updates are sent to Firestore only when EITHER condition is met:
  // 1. Time threshold: At least minUploadInterval has passed since last upload
  // 2. Distance threshold: Pilot has moved at least minDistanceMeters
  //
  // NOTE: Safety checks (airspace/altitude) run on EVERY position regardless of throttling
  // 
  // Adjust these to balance:
  // - Real-time tracking accuracy (lower = more frequent updates)
  // - Firestore costs (higher = fewer writes, lower cost)
  // - Battery consumption (higher = less network activity, better battery)
  static const Duration minUploadInterval = Duration(seconds: 12);
  static const double minDistanceMeters = 50.0;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ConnectivityService _connectivityService = ConnectivityService();

  // State
  bool _isEnabled = true;
  bool _isActive = false; // Currently tracking (in flight)
  DateTime? _lastUploadTime;
  TrackPoint? _lastUploadedPosition;
  DateTime? _flightStartTime;
  String? _takeoffSiteName;

  // Offline queue
  List<_PendingPositionUpdate> _pendingPositions = [];
  bool _syncing = false;
  Timer? _periodicSyncTimer;
  VoidCallback? _connectivityCallbackUnsubscribe;

  // Cached profile data
  String? _uid;
  String? _shvNumber;
  String? _displayName;
  String? _licenseType;
  String? _glider;
  bool _membershipValid = false;
  bool _insuranceValid = false;

  // Alert service for safety monitoring
  final AlertService _alertService = AlertService();

  // Callback for UI alert notifications
  Function(AlertRecord)? onAlertCreated;

  // Getters
  bool get isEnabled => _isEnabled;
  bool get isActive => _isActive;
  DateTime? get lastUploadTime => _lastUploadTime;
  AlertService get alertService => _alertService;
  bool get isOnline => _connectivityService.isOnline;
  int get pendingPositionsCount => _pendingPositions.length;

  LiveTrackingService() {
    _initializeService();
  }

  /// Initialize the service
  Future<void> _initializeService() async {
    await _loadSettings();
    await _loadPendingPositions();
    await _loadLastFlightState();
    
    // Initialize connectivity and register for callbacks
    await _connectivityService.initialize();
    _connectivityCallbackUnsubscribe = _connectivityService.addOnConnectivityChangedCallback(
      (isOnline) {
        if (isOnline) {
          // Only sync landing markers (positions are real-time only, not queued)
          debugPrint('📡 [LiveTracking] Connectivity restored - syncing landing markers only');
          _syncPendingPositions();
        }
      },
    );
    
    // Start periodic sync timer
    _startPeriodicSync();
    
    // Try to sync any pending positions if online
    if (_connectivityService.isOnline && _pendingPositions.isNotEmpty) {
      _syncPendingPositions();
    }
  }

  /// Start periodic sync timer
  /// NOTE: This now only syncs landing markers (positions are not queued anymore)
  void _startPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_pendingPositions.isNotEmpty && _connectivityService.isOnline) {
        debugPrint('⏰ [LiveTracking] Periodic sync triggered - ${_pendingPositions.length} pending items (landing markers)');
        _syncPendingPositions();
      }
    });
  }

  /// Load settings from SharedPreferences
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool(_enabledKey) ?? true;
      notifyListeners();
    } catch (e) {
      log('[LiveTrackingService] Error loading settings: $e');
    }
  }

  /// Save settings to SharedPreferences
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, _isEnabled);
    } catch (e) {
      log('[LiveTrackingService] Error saving settings: $e');
    }
  }
  
  /// Load pending positions from local storage
  Future<void> _loadPendingPositions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final positionsJson = prefs.getStringList(_pendingPositionsKey) ?? [];
      
      _pendingPositions = positionsJson
          .map((json) => _PendingPositionUpdate.fromJson(jsonDecode(json)))
          .toList();
      
      log('[LiveTrackingService] Loaded ${_pendingPositions.length} pending positions');
    } catch (e) {
      log('[LiveTrackingService] Error loading pending positions: $e');
      _pendingPositions = [];
    }
  }
  
  /// Save pending positions to local storage
  Future<void> _savePendingPositions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final positionsJson = _pendingPositions.map((p) => jsonEncode(p.toJson())).toList();
      await prefs.setStringList(_pendingPositionsKey, positionsJson);
    } catch (e) {
      log('[LiveTrackingService] Error saving pending positions: $e');
    }
  }
  
  /// Load last flight state (for recovery after app restart)
  Future<void> _loadLastFlightState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stateJson = prefs.getString(_lastFlightStateKey);
      
      if (stateJson != null) {
        final state = jsonDecode(stateJson) as Map<String, dynamic>;
        
        // Check if we have an unfinished flight
        if (state['isActive'] == true && state['uid'] != null) {
          debugPrint('🔄 [LiveTracking] Found unfinished flight state - may need recovery');
          // We'll let the FlightTrackingService handle recovery
          // Just log for debugging purposes
        }
      }
    } catch (e) {
      log('[LiveTrackingService] Error loading last flight state: $e');
    }
  }
  
  /// Save current flight state (for recovery after app restart)
  Future<void> _saveFlightState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final state = {
        'isActive': _isActive,
        'uid': _uid,
        'flightStartTime': _flightStartTime?.toIso8601String(),
        'takeoffSiteName': _takeoffSiteName,
        'savedAt': DateTime.now().toIso8601String(),
      };
      
      await prefs.setString(_lastFlightStateKey, jsonEncode(state));
    } catch (e) {
      log('[LiveTrackingService] Error saving flight state: $e');
    }
  }
  
  /// Clear saved flight state
  Future<void> _clearFlightState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastFlightStateKey);
    } catch (e) {
      log('[LiveTrackingService] Error clearing flight state: $e');
    }
  }

  /// Enable/disable live tracking
  Future<void> setEnabled(bool enabled) async {
    if (_isEnabled == enabled) return;
    _isEnabled = enabled;
    await _saveSettings();

    // If disabling while active, stop tracking
    if (!enabled && _isActive) {
      await stopTracking();
    }

    notifyListeners();
    log('[LiveTrackingService] Live tracking ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Toggle live tracking
  Future<void> toggleEnabled() async {
    await setEnabled(!_isEnabled);
  }

  /// Initialize with user profile data
  /// Call this when user logs in or profile changes
  void updateProfile(UserProfile? profile) {
    if (profile == null) {
      log('[LiveTrackingService] Profile update: NULL profile received');
      _uid = null;
      _shvNumber = null;
      _displayName = null;
      _licenseType = null;
      _glider = null;
      return;
    }

    _uid = profile.uid;
    _shvNumber = profile.shvnumber;
    _displayName = '${profile.forename} ${profile.familyname}'.trim();
    _licenseType = profile.license;
    _glider = profile.glider;

    // Fetch membership and insurance status from Firestore (async, non-blocking)
    _loadMembershipAndInsuranceStatus();

    log('[LiveTrackingService] ✓ Profile updated:');
    log('    UID: $_uid');
    log('    Name: $_displayName');
    log('    SHV: $_shvNumber');
    log('    License: $_licenseType');
    log('    Membership: $_membershipValid, Insurance: $_insuranceValid');
  }

  /// Fetch membership and insurance validity from Firestore
  /// OFFLINE-SAFE: Uses cached values if offline, defaults to false if unavailable
  Future<void> _loadMembershipAndInsuranceStatus() async {
    if (_uid == null) {
      debugPrint(
          '📋 [LiveTracking] UID is null, cannot fetch membership/insurance status');
      _membershipValid = false;
      _insuranceValid = false;
      return;
    }

    // Check connectivity first - skip Firestore call if offline
    if (!_connectivityService.isOnline) {
      debugPrint('📋 [LiveTracking] Offline - using default membership/insurance status (false)');
      _membershipValid = false;
      _insuranceValid = false;
      return;
    }

    try {
      debugPrint(
          '📋 [LiveTracking] Fetching membership/insurance status from users/$_uid/');
      final doc = await _firestore.collection('users').doc(_uid).get();

      if (!doc.exists) {
        debugPrint('⚠️ [LiveTracking] User document not found in Firestore');
        _membershipValid = false;
        _insuranceValid = false;
        return;
      }

      final data = doc.data();
      _membershipValid = data?['membershipValid'] ?? false;
      _insuranceValid = data?['insuranceValid'] ?? false;

      debugPrint('✅ [LiveTracking] Membership/Insurance loaded:');
      debugPrint('   Membership: $_membershipValid');
      debugPrint('   Insurance: $_insuranceValid');
      log('[LiveTrackingService] Membership: $_membershipValid, Insurance: $_insuranceValid');
    } catch (e) {
      debugPrint('❌ [LiveTracking] Error fetching membership/insurance: $e');
      log('[LiveTrackingService] Error loading membership/insurance: $e');
      _membershipValid = false;
      _insuranceValid = false;
    }
  }

  /// Start live tracking (called when flight starts)
  /// Also checks credentials at takeoff and creates alerts if invalid
  Future<void> startTracking({
    String? takeoffSiteName,
    double? latitude,
    double? longitude,
    double? altitude,
  }) async {
    debugPrint('🛫 [LiveTracking] ========================================');
    debugPrint('🛫 [LiveTracking] startTracking called');
    debugPrint('🛫 [LiveTracking] Enabled: $_isEnabled');
    debugPrint('🛫 [LiveTracking] Currently active: $_isActive');
    debugPrint('🛫 [LiveTracking] Online: ${_connectivityService.isOnline}');

    if (!_isEnabled) {
      debugPrint('❌ [LiveTracking] Live tracking is DISABLED in settings');
      log('[LiveTrackingService] Live tracking disabled, not starting');
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('❌ [LiveTracking] No authenticated user');
      log('[LiveTrackingService] ✗ No authenticated user, cannot start tracking');
      return;
    }

    _uid = user.uid;
    _isActive = true;
    _flightStartTime = DateTime.now();
    _takeoffSiteName = takeoffSiteName;
    _lastUploadTime = null;
    _lastUploadedPosition = null;

    // Save flight state for recovery
    await _saveFlightState();

    debugPrint('✅ [LiveTracking] LIVE TRACKING STARTED!');
    debugPrint('✅ [LiveTracking] UID: $_uid');
    debugPrint('✅ [LiveTracking] Name: $_displayName');
    debugPrint('✅ [LiveTracking] Takeoff: $takeoffSiteName');
    debugPrint('🛫 [LiveTracking] ========================================');

    // Initialize alert service and check credentials at takeoff
    await _alertService.initialize();

    // Set up alert callback to notify UI
    _alertService.onAlertCreated = (alert) {
      onAlertCreated?.call(alert);
    };

    // Check membership and insurance validity at takeoff
    if (_uid != null && _displayName != null) {
      await _alertService.checkCredentialsAtTakeoff(
        uid: _uid!,
        displayName: _displayName ?? 'Unknown',
        shvNumber: _shvNumber ?? '',
        licenseType: _licenseType ?? '',
        membershipValid: _membershipValid,
        insuranceValid: _insuranceValid,
        latitude: latitude ?? 0.0,
        longitude: longitude ?? 0.0,
        altitudeM: altitude ?? 0.0,
      );
    }

    notifyListeners();
    log('[LiveTrackingService] ✓ Started live tracking from $takeoffSiteName (UID: $_uid, Profile: $_displayName)');
  }

  /// Stop live tracking (called when flight ends)
  Future<void> stopTracking() async {
    debugPrint('🛬 [LiveTracking] stopTracking called - active: $_isActive');

    if (!_isActive) {
      debugPrint('🛬 [LiveTracking] Not active, skipping');
      return;
    }

    _isActive = false;

    // Mark as not in flight (instead of deleting)
    debugPrint('🛬 [LiveTracking] Calling _markAsLanded...');
    await _markAsLanded();

    // Finalize any active violations (pilot landed, possibly inside airspace)
    await _alertService.finalizeActiveViolationsOnLanding(
      latitude: _lastUploadedPosition?.latitude ?? 0.0,
      longitude: _lastUploadedPosition?.longitude ?? 0.0,
      altitudeM: 0.0, // On ground
    );

    // Clear alert tracking for next flight
    _alertService.clearRecentAlerts();

    // Force sync any pending ALERTS (important for offline flights)
    await _alertService.forceSyncPendingAlerts();
    
    // Clear ONLY position updates (type != 'landing'), keep landing markers for sync
    // Positions are real-time only, but landing marker needs to be synced
    final oldPositionCount = _pendingPositions.length;
    _pendingPositions.removeWhere((update) => update.additionalData['type'] != 'landing');
    if (oldPositionCount != _pendingPositions.length) {
      debugPrint('🗑️ [LiveTracking] Cleared ${oldPositionCount - _pendingPositions.length} position updates, kept ${_pendingPositions.length} landing markers');
      await _savePendingPositions();
    }
    
    // Try to sync landing marker if online
    if (_connectivityService.isOnline && _pendingPositions.isNotEmpty) {
      await _syncPendingPositions();
    }

    // Clear flight state
    await _clearFlightState();

    _flightStartTime = null;
    _takeoffSiteName = null;
    _lastUploadTime = null;
    _lastUploadedPosition = null;

    notifyListeners();
    debugPrint('🛬 [LiveTracking] Stopped live tracking - marked as landed');
    log('[LiveTrackingService] Stopped live tracking');
  }

  /// Mark pilot as landed (set inFlight = false)
  /// This keeps the document for history/statistics
  /// Uses offline queue if not connected
  Future<void> _markAsLanded() async {
    debugPrint('🛬 [LiveTracking] _markAsLanded called, UID: $_uid');

    if (_uid == null) {
      debugPrint('🛬 [LiveTracking] UID is null, cannot mark as landed');
      return;
    }

    if (_connectivityService.isOnline) {
      try {
        debugPrint('🛬 [LiveTracking] Updating Firestore document...');
        await _firestore.collection('live_tracking').doc(_uid).update({
          'inFlight': false,
          'landingTime': FieldValue.serverTimestamp(),
        });
        debugPrint('✅ [LiveTracking] ✓ Successfully marked as landed in Firestore');
        log('[LiveTrackingService] Marked as landed');
      } catch (e) {
        debugPrint('❌ [LiveTracking] ✗ Error marking as landed: $e');
        // Queue for later sync
        _queueLandingUpdate();
      }
    } else {
      debugPrint('📡 [LiveTracking] Offline - queueing landing update');
      _queueLandingUpdate();
    }
  }
  
  /// Queue a landing update for later sync
  void _queueLandingUpdate() {
    // Create a special position update that indicates landing
    final landingUpdate = _PendingPositionUpdate(
      position: _lastUploadedPosition ?? TrackPoint(
        latitude: 0,
        longitude: 0,
        altitude: 0,
        timestamp: DateTime.now(),
      ),
      queuedAt: DateTime.now(),
      additionalData: {
        'type': 'landing',
        'inFlight': false,
        'uid': _uid,
      },
    );
    
    _pendingPositions.add(landingUpdate);
    _savePendingPositions();
  }

  /// Process a position update
  /// Call this from FlightTrackingService.processPosition()
  /// Also checks for airspace and altitude violations
  /// 
  /// IMPORTANT: This is called on EVERY GPS update (typically 1Hz = every second)
  /// - Safety checks (airspace/altitude violations) run on EVERY position
  /// - Position uploads to Firestore are THROTTLED (only every 12s or 50m movement)
  Future<void> processPosition(TrackPoint position) async {
    // Debug: Always log when this is called
    debugPrint(
        '🔵 [LiveTracking] processPosition called - enabled: $_isEnabled, active: $_isActive');

    if (!_isEnabled || !_isActive) {
      if (!_isActive) {
        // Silently skip if not active (expected behavior)
        return;
      }
      debugPrint(
          '🔴 [LiveTracking] Skipping - enabled: $_isEnabled, active: $_isActive');
      return;
    }

    // ============================================
    // STEP 1: ALWAYS check for flight safety violations (airspace, altitude)
    // This runs on EVERY position update for real-time safety monitoring
    // ============================================
    if (_uid != null) {
      await _alertService.checkFlightSafety(
        latitude: position.latitude,
        longitude: position.longitude,
        altitudeM: position.altitude,
        uid: _uid!,
        displayName: _displayName ?? 'Unknown',
        shvNumber: _shvNumber ?? '',
        licenseType: _licenseType ?? '',
      );
    }

    // ============================================
    // STEP 2: THROTTLE position uploads to Firestore
    // Only upload if:
    // - Enough time has passed (minUploadInterval = 12 seconds), OR
    // - Moved significant distance (minDistanceMeters = 50 meters)
    // This prevents excessive Firestore writes and battery drain
    // ============================================
    final shouldUpload = _shouldUploadPosition(position);
    
    if (shouldUpload) {
      debugPrint('🟢 [LiveTracking] Uploading position - Online: ${_connectivityService.isOnline}');
      await _uploadPosition(position);
    } else {
      debugPrint('⏸️ [LiveTracking] Throttled - skipping upload (checked safety already)');
    }
  }
  
  /// Check if position should be uploaded based on throttling rules
  /// Returns true if:
  /// - This is the first upload, OR
  /// - Enough time has passed since last upload (minUploadInterval), OR
  /// - Moved significant distance since last upload (minDistanceMeters)
  bool _shouldUploadPosition(TrackPoint position) {
    // First upload - always send
    if (_lastUploadTime == null || _lastUploadedPosition == null) {
      return true;
    }
    
    // Check time threshold
    final timeSinceLastUpload = DateTime.now().difference(_lastUploadTime!);
    if (timeSinceLastUpload >= minUploadInterval) {
      debugPrint('⏰ [LiveTracking] Time threshold met (${timeSinceLastUpload.inSeconds}s >= ${minUploadInterval.inSeconds}s)');
      return true;
    }
    
    // Check distance threshold
    final distanceMeters = _calculateDistance(
      _lastUploadedPosition!.latitude,
      _lastUploadedPosition!.longitude,
      position.latitude,
      position.longitude,
    );
    
    if (distanceMeters >= minDistanceMeters) {
      debugPrint('📏 [LiveTracking] Distance threshold met (${distanceMeters.toStringAsFixed(0)}m >= ${minDistanceMeters.toStringAsFixed(0)}m)');
      return true;
    }
    
    // Neither threshold met - don't upload yet
    return false;
  }
  
  /// Calculate distance between two coordinates using Haversine formula
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadiusMeters = 6371000;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }
  
  double _toRadians(double degrees) => degrees * math.pi / 180;

  /// Upload position to Firestore (ONLY if online)
  /// NOTE: Positions are NOT queued when offline - they're only for real-time tracking
  /// Admins want to see live positions, not historical data hours later
  Future<void> _uploadPosition(TrackPoint position) async {
    debugPrint('📍 [LiveTracking] _uploadPosition called');

    if (_uid == null) {
      debugPrint('❌ [LiveTracking] No UID, cannot upload position');
      log('[LiveTrackingService] No UID, cannot upload position');
      return;
    }

    debugPrint('📍 [LiveTracking] UID: $_uid');
    debugPrint(
        '📍 [LiveTracking] Position: lat=${position.latitude}, lon=${position.longitude}, alt=${position.altitude}');

    // Check if currently in restricted airspace
    final isInRestrictedAirspace = _alertService.isInRestrictedAirspace;
    
    debugPrint('🚨 [LiveTracking] airspaceViolation check:');
    debugPrint('   isInRestrictedAirspace: $isInRestrictedAirspace');
    debugPrint('   Active violations count: ${_alertService.activeViolations.length}');
    if (_alertService.activeViolations.isNotEmpty) {
      debugPrint('   Active zones: ${_alertService.activeViolations.keys.join(", ")}');
    }

    // Only upload if ONLINE - don't queue positions for later
    // Real-time tracking means current position only, not historical data
    if (!_connectivityService.isOnline) {
      debugPrint('📡 [LiveTracking] Offline - skipping position upload (positions are not queued)');
      return;
    }

    final data = {
      'uid': _uid,
      'shvNumber': _shvNumber ?? '',
      'displayName': _displayName ?? 'Unknown',
      'membershipValid': _membershipValid,
      'insuranceValid': _insuranceValid,
      'licenseType': _licenseType ?? 'unknown',
      'latitude': position.latitude,
      'longitude': position.longitude,
      'altitude': position.altitude,
      'heading': position.heading,
      'speed': position.speed,
      'airspaceViolation': isInRestrictedAirspace, // TRUE if in restricted airspace
      'lastUpdate': FieldValue.serverTimestamp(),
      'flightStartTime': _flightStartTime != null
          ? Timestamp.fromDate(_flightStartTime!)
          : FieldValue.serverTimestamp(),
      'glider': _glider,
      'takeoffSite': _takeoffSiteName,
      'inFlight': true, // IMPORTANT: Used to filter active flights in admin app
      // NEW: expose current alertId for admin app
      'alertId': _alertService.currentFlightAlertId,
    };

    try {
      final docRef = _firestore.collection('live_tracking').doc(_uid);
      
      debugPrint('📤 [LiveTracking] Attempting to write to Firestore...');
      debugPrint('📤 [LiveTracking] Collection: live_tracking, Doc ID: $_uid');

      await docRef.set(data, SetOptions(merge: false));

      _lastUploadTime = DateTime.now();
      _lastUploadedPosition = position;

      debugPrint('✅ [LiveTracking] SUCCESS! Position uploaded to Firestore');
      log('[LiveTrackingService] ✓ Position uploaded: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}, ${position.altitude.toStringAsFixed(0)}m');
    } catch (e, st) {
      debugPrint('❌ [LiveTracking] ERROR uploading position: $e');
      debugPrint('❌ [LiveTracking] Stack trace: $st');
      log('[LiveTrackingService] ✗ Error uploading position: $e');
      // Don't queue - positions are real-time only
    }
  }
  
  /// Sync pending landing markers to Firestore
  /// NOTE: Regular positions are not queued - only landing markers are synced
  Future<void> _syncPendingPositions() async {
    if (_syncing || _pendingPositions.isEmpty) return;
    if (!_connectivityService.isOnline) {
      debugPrint('📡 [LiveTracking] Offline - skipping landing marker sync');
      return;
    }
    
    _syncing = true;
    debugPrint('🔄 [LiveTracking] Syncing ${_pendingPositions.length} pending landing markers');
    
    try {
      final toSync = List<_PendingPositionUpdate>.from(_pendingPositions);
      final synced = <_PendingPositionUpdate>[];
      
      for (final update in toSync) {
        try {
          final uid = update.additionalData['uid'] as String?;
          if (uid == null) continue;
          
          final type = update.additionalData['type'] as String? ?? 'position';
          
          if (type == 'landing') {
            // Handle landing update
            await _firestore.collection('live_tracking').doc(uid).update({
              'inFlight': false,
              'landingTime': FieldValue.serverTimestamp(),
            });
          } else {
            // Handle position update - use the LATEST position only
            // (older positions are less relevant for live tracking)
            final data = {
              'uid': uid,
              'shvNumber': update.additionalData['shvNumber'] ?? '',
              'displayName': update.additionalData['displayName'] ?? 'Unknown',
              'membershipValid': update.additionalData['membershipValid'] ?? false,
              'insuranceValid': update.additionalData['insuranceValid'] ?? false,
              'licenseType': update.additionalData['licenseType'] ?? 'unknown',
              'latitude': update.position.latitude,
              'longitude': update.position.longitude,
              'altitude': update.position.altitude,
              'heading': update.position.heading,
              'speed': update.position.speed,
              'airspaceViolation': update.additionalData['airspaceViolation'] ?? false,
              'lastUpdate': FieldValue.serverTimestamp(),
              'flightStartTime': update.additionalData['flightStartTime'] != null
                  ? Timestamp.fromDate(DateTime.parse(update.additionalData['flightStartTime']))
                  : FieldValue.serverTimestamp(),
              'glider': update.additionalData['glider'],
              'takeoffSite': update.additionalData['takeoffSite'],
              'inFlight': true,
              'alertId': update.additionalData['alertId'],
              // Mark that this was synced from offline queue
              'syncedFromOffline': true,
              'originalTimestamp': Timestamp.fromDate(update.position.timestamp),
            };
            
            await _firestore.collection('live_tracking').doc(uid).set(data, SetOptions(merge: false));
          }
          
          synced.add(update);
          debugPrint('✅ [LiveTracking] Synced ${type == 'landing' ? 'landing' : 'position'} update');
        } catch (e) {
          debugPrint('❌ [LiveTracking] Failed to sync position: $e');
          // Stop on network error
          if (e.toString().contains('network') || e.toString().contains('offline')) {
            break;
          }
        }
      }
      
      // Remove synced positions
      for (final update in synced) {
        _pendingPositions.remove(update);
      }
      
      await _savePendingPositions();
      debugPrint('🔄 [LiveTracking] Sync complete - ${synced.length} synced, ${_pendingPositions.length} remaining');
      
    } finally {
      _syncing = false;
    }
  }

  /// Remove pilot from live tracking collection
  Future<void> _removeFromTracking() async {
    if (_uid == null) return;

    try {
      await _firestore.collection('live_tracking').doc(_uid).delete();
      log('[LiveTrackingService] Removed from live tracking');
    } catch (e) {
      log('[LiveTrackingService] Error removing from tracking: $e');
    }
  }

  /// Get current tracking status for UI display
  Map<String, dynamic> getStatus() {
    return {
      'enabled': _isEnabled,
      'active': _isActive,
      'online': _connectivityService.isOnline,
      'pendingPositions': _pendingPositions.length,
      'lastUpload': _lastUploadTime?.toIso8601String(),
      'flightStart': _flightStartTime?.toIso8601String(),
      'takeoffSite': _takeoffSiteName,
    };
  }
  
  /// Force sync all pending data
  /// Syncs landing markers and alerts (regular positions are not queued)
  Future<void> forceSyncAll() async {
    debugPrint('🔄 [LiveTracking] Force sync all triggered');
    await _syncPendingPositions(); // Landing markers only
    await _alertService.forceSyncPendingAlerts(); // All pending alerts
  }

  @override
  void dispose() {
    _periodicSyncTimer?.cancel();
    _connectivityCallbackUnsubscribe?.call();
    
    // Clean up: remove from tracking if still active
    if (_isActive) {
      _removeFromTracking();
    }
    
    // Save any pending positions
    _savePendingPositions();
    
    super.dispose();
  }
}
