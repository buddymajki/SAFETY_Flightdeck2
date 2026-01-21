// File: lib/services/alert_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert_model.dart';
import 'airspace_service.dart';
import '../config/flight_constants.dart';

/// Tracks time spent in a specific airspace zone
class AirspaceViolationTracker {
  final String zoneId;
  final String zoneName;
  final String zoneType;
  final DateTime entryTime;
  DateTime lastUpdateTime;
  double entryLatitude;
  double entryLongitude;
  double entryAltitude;
  double maxAltitude;
  double minAltitude;
  int positionCount;
  
  AirspaceViolationTracker({
    required this.zoneId,
    required this.zoneName,
    required this.zoneType,
    required this.entryTime,
    required this.entryLatitude,
    required this.entryLongitude,
    required this.entryAltitude,
  }) : lastUpdateTime = entryTime,
       maxAltitude = entryAltitude,
       minAltitude = entryAltitude,
       positionCount = 1;
  
  /// Duration spent in the airspace so far
  Duration get duration => lastUpdateTime.difference(entryTime);
  
  /// Update tracking with new position
  void updatePosition(double lat, double lng, double altitude) {
    lastUpdateTime = DateTime.now();
    if (altitude > maxAltitude) maxAltitude = altitude;
    if (altitude < minAltitude) minAltitude = altitude;
    positionCount++;
  }
  
  /// Convert to metadata map for alert
  Map<String, dynamic> toMetadata() => {
    'zoneId': zoneId,
    'zoneName': zoneName,
    'zoneType': zoneType,
    'entryTime': entryTime.toIso8601String(),
    'exitTime': lastUpdateTime.toIso8601String(),
    'totalDurationSeconds': duration.inSeconds,
    'totalDurationFormatted': _formatDuration(duration),
    'entryLatitude': entryLatitude,
    'entryLongitude': entryLongitude,
    'entryAltitude': entryAltitude,
    'maxAltitude': maxAltitude,
    'minAltitude': minAltitude,
    'positionCount': positionCount,
    'airspaceViolation': true,
  };
  
  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
}

/// Service for detecting and logging flight safety alerts
///
/// Features:
/// - Detects airspace violations, altitude violations, and credential issues
/// - Creates alert records in Firestore during flight
/// - Queues alerts locally if offline and syncs when connection returns
/// - Prevents duplicate alerts within a cooldown period
/// - Tracks time spent in restricted airspaces
/// - Notifies listeners for UI updates
class AlertService extends ChangeNotifier {
    /// Expose current flight alert id for admin lookup
    String? get currentFlightAlertId => _currentFlightAlertId;
  static final AlertService _instance = AlertService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final AirspaceService _airspaceService = AirspaceService();

  // Local queue for offline alerts
  List<AlertRecord> _pendingAlerts = [];
  bool _syncing = false;
  bool _isInitialized = false;

  // Duplicate prevention: track recent alerts by type
  final Map<String, DateTime> _recentAlerts = {};
  
  // Track active airspace violations (by zone ID) - supports overlapping zones
  final Map<String, AirspaceViolationTracker> _activeViolations = {};
  
  // Single alert per flight that tracks ALL violations
  String? _currentFlightAlertId;
  final List<Map<String, dynamic>> _currentFlightViolations = [];

  // Callbacks for UI notifications
  Function(AlertRecord)? onAlertCreated;

  factory AlertService() {
    return _instance;
  }

  AlertService._internal();

  // Getters
  List<AlertRecord> get pendingAlerts => List.unmodifiable(_pendingAlerts);
  bool get isSyncing => _syncing;
  bool get isInitialized => _isInitialized;
  int get pendingCount => _pendingAlerts.length;
  
  /// Get current active violations (pilot is still in these airspaces)
  Map<String, AirspaceViolationTracker> get activeViolations => 
      Map.unmodifiable(_activeViolations);
  
  /// Check if pilot is currently in any restricted airspace
  bool get isInRestrictedAirspace => _activeViolations.isNotEmpty;

  /// Initialize the alert service
  /// Call this at app startup
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize airspace service
      await _airspaceService.initialize();

      // Load pending alerts from local storage
      await _loadPendingAlerts();

      // Try to sync any pending alerts
      if (_pendingAlerts.isNotEmpty) {
        _syncAlertsToFirestore();
      }

      _isInitialized = true;
      log('[AlertService] ✓ Initialized - ${_airspaceService.zoneCount} airspace zones, ${_pendingAlerts.length} pending alerts');
    } catch (e) {
      log('[AlertService] ✗ Error initializing: $e');
      _isInitialized = true; // Mark as initialized to prevent retry loops
    }
  }

  /// Check for violations on every position update
  /// Call this from FlightTrackingService.processPosition()
  Future<void> checkFlightSafety({
    required double latitude,
    required double longitude,
    required double altitudeM,
    required String uid,
    required String displayName,
    required String shvNumber,
    required String licenseType,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    final now = DateTime.now();
    
    // Get all restricted zones at current position
    final currentZones = _airspaceService.getAllRestrictedZones(
      latitude, longitude, altitudeM
    );
    final currentZoneIds = currentZones.map((z) => z.id).toSet();
    
    print('🔍 [AlertService] checkFlightSafety:');
    print('   Current zones at position: ${currentZones.length}');
    print('   Active violations: ${_activeViolations.length}');
    
    // Check for NEW airspace entries (zones we weren't in before)
    for (final zone in currentZones) {
      if (!_activeViolations.containsKey(zone.id)) {
        // New airspace entry - start tracking
        _activeViolations[zone.id] = AirspaceViolationTracker(
          zoneId: zone.id,
          zoneName: zone.name,
          zoneType: zone.type,
          entryTime: now,
          entryLatitude: latitude,
          entryLongitude: longitude,
          entryAltitude: altitudeM,
        );
        
        // Add entry record to this flight's violations FIRST (before creating alert)
        _currentFlightViolations.add({
          'zoneId': zone.id,
          'zoneName': zone.name,
          'zoneType': zone.type,
          'zoneClass': zone.asClass,
          'entryTime': now.toIso8601String(),
          'entryLatitude': latitude,
          'entryLongitude': longitude,
          'entryAltitude': altitudeM,
          'status': 'in_progress',
        });
        
        // Create flight-level alert on FIRST violation (now list has data)
        if (_currentFlightAlertId == null) {
          _currentFlightAlertId = await _createFlightSafetyAlert(
            uid: uid,
            displayName: displayName,
            shvNumber: shvNumber,
            licenseType: licenseType,
          );
          print('🚨 [AlertService] Created flight safety alert: $_currentFlightAlertId');
        } else {
          // Update existing alert with new entry
          await _updateFlightAlertWithEntry(
            zone: zone,
            latitude: latitude,
            longitude: longitude,
            altitudeM: altitudeM,
          );
        }
        
        print('⚠️ [AlertService] ENTERED AIRSPACE: ${zone.name} (${zone.type})');
        log('[AlertService] ⚠️ ENTERED RESTRICTED AIRSPACE: ${zone.name} (${zone.type})');
      } else {
        // Still in same airspace - update tracking
        _activeViolations[zone.id]!.updatePosition(latitude, longitude, altitudeM);
      }
    }
    
    // Check for airspace EXITS (zones we were in but are no longer)
    // This now works correctly with OVERLAPPING zones
    final exitedZoneIds = _activeViolations.keys
        .where((id) => !currentZoneIds.contains(id))
        .toList();
    
    print('   Exited zones: ${exitedZoneIds.length}');
    
    for (final zoneId in exitedZoneIds) {
      final tracker = _activeViolations.remove(zoneId);
      if (tracker != null) {
        print('✅ [AlertService] EXITING AIRSPACE: ${tracker.zoneName}');
        
        // Find the violation entry in our list and update with exit data
        final violationIndex = _currentFlightViolations.indexWhere(
          (v) => v['zoneId'] == zoneId && v['status'] == 'in_progress'
        );
        
        if (violationIndex != -1) {
          _currentFlightViolations[violationIndex]['exitTime'] = now.toIso8601String();
          _currentFlightViolations[violationIndex]['exitLatitude'] = latitude;
          _currentFlightViolations[violationIndex]['exitLongitude'] = longitude;
          _currentFlightViolations[violationIndex]['exitAltitude'] = altitudeM;
          _currentFlightViolations[violationIndex]['durationSeconds'] = tracker.duration.inSeconds;
          _currentFlightViolations[violationIndex]['status'] = 'completed';
          _currentFlightViolations[violationIndex]['maxAltitude'] = tracker.maxAltitude;
          _currentFlightViolations[violationIndex]['minAltitude'] = tracker.minAltitude;
          
          // Update the flight alert with exit info
          await _updateFlightAlertWithExit(
            tracker: tracker,
            exitLatitude: latitude,
            exitLongitude: longitude,
            exitAltitude: altitudeM,
          );
        }
        
        log('[AlertService] ✓ EXITED RESTRICTED AIRSPACE: ${tracker.zoneName} after ${tracker.duration.inSeconds}s');
      }
    }

    // Check altitude violation (independent of airspace)
    if (altitudeM > FlightConstants.maxAltitudeMeters) {
      await _createAlertIfNotDuplicate(
        uid: uid,
        displayName: displayName,
        shvNumber: shvNumber,
        licenseType: licenseType,
        alertType: AlertType.altitudeViolation.value,
        reason:
            'Altitude ${altitudeM.toStringAsFixed(0)}m exceeds limit ${FlightConstants.maxAltitudeMeters.toStringAsFixed(0)}m',
        severity: AlertSeverity.high.value,
        metadata: {
          'currentAltitude': altitudeM,
          'maxAltitude': FlightConstants.maxAltitudeMeters,
          'latitude': latitude,
          'longitude': longitude,
          'timestamp': now.toIso8601String(),
        },
        dedupeKey: 'altitude_violation',
      );
    }
  }
  
  /// Create a single flight-level safety alert that will track ALL violations for this flight
  Future<String?> _createFlightSafetyAlert({
    required String uid,
    required String displayName,
    required String shvNumber,
    required String licenseType,
  }) async {
    final now = DateTime.now();
    
    // Build initial reason with first violation info
    final reason = _buildFlightAlertReason();
    
    return await createAlert(
      uid: uid,
      displayName: displayName,
      shvNumber: shvNumber,
      licenseType: licenseType,
      alertType: AlertType.airspaceViolation.value,
      reason: reason,
      severity: AlertSeverity.high.value,
      metadata: {
        'airspaceViolation': true,
        'flightStartTime': now.toIso8601String(),
        'violations': _currentFlightViolations, // Already has the first violation
        'violationsCount': _currentFlightViolations.length,
        'status': 'in_progress',
      },
    );
  }
  
  /// Update flight alert when entering a new airspace
  Future<void> _updateFlightAlertWithEntry({
    required RestrictedZone zone,
    required double latitude,
    required double longitude,
    required double altitudeM,
  }) async {
    if (_currentFlightAlertId == null) return;
    
    final reason = _buildFlightAlertReason();
    
    try {
      // Update in local storage
      final index = _pendingAlerts.indexWhere((a) => a.id == _currentFlightAlertId);
      if (index != -1) {
        final oldAlert = _pendingAlerts[index];
        _pendingAlerts[index] = AlertRecord(
          id: oldAlert.id,
          uid: oldAlert.uid,
          displayName: oldAlert.displayName,
          shvNumber: oldAlert.shvNumber,
          licenseType: oldAlert.licenseType,
          alertType: oldAlert.alertType,
          reason: reason,
          severity: oldAlert.severity,
          triggeredAt: oldAlert.triggeredAt,
          metadata: {
            ...oldAlert.metadata ?? {},
            'violations': _currentFlightViolations,
          },
          resolved: oldAlert.resolved,
          resolvedAt: oldAlert.resolvedAt,
          resolvedBy: oldAlert.resolvedBy,
          resolutionNotes: oldAlert.resolutionNotes,
        );
        await _savePendingAlerts();
      }
      
      // Try Firestore update - use SET with merge to handle nested objects properly
      try {
        print('🔄 [AlertService] ENTRY - Updating Firestore alert: $_currentFlightAlertId');
        print('   Violations count: ${_currentFlightViolations.length}');
        print('   Active violations: ${_activeViolations.length}');
        
        // Use set with merge to properly update nested metadata
        await _db.collection('alerts').doc(_currentFlightAlertId).set({
          'reason': reason,
          'metadata': {
            'violations': _currentFlightViolations,
            'violationsCount': _currentFlightViolations.length,
            'airspaceViolation': _activeViolations.isNotEmpty,
            'status': 'in_progress',
          },
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        
        print('✅ [AlertService] ENTRY - Firestore alert updated successfully');
        log('[AlertService] ✓ Updated alert $_currentFlightAlertId in Firestore');
      } catch (e) {
        print('❌ [AlertService] ENTRY - Firestore update failed: $e');
        log('[AlertService] ⚠️ Could not update Firestore: $e');
      }
      
      notifyListeners();
    } catch (e) {
      log('[AlertService] ✗ Error updating flight alert: $e');
    }
  }
  
  /// Update flight alert when exiting an airspace
  Future<void> _updateFlightAlertWithExit({
    required AirspaceViolationTracker tracker,
    required double exitLatitude,
    required double exitLongitude,
    required double exitAltitude,
  }) async {
    if (_currentFlightAlertId == null) return;
    
    final reason = _buildFlightAlertReason();
    
    try {
      // Update in local storage
      final index = _pendingAlerts.indexWhere((a) => a.id == _currentFlightAlertId);
      if (index != -1) {
        final oldAlert = _pendingAlerts[index];
        _pendingAlerts[index] = AlertRecord(
          id: oldAlert.id,
          uid: oldAlert.uid,
          displayName: oldAlert.displayName,
          shvNumber: oldAlert.shvNumber,
          licenseType: oldAlert.licenseType,
          alertType: oldAlert.alertType,
          reason: reason,
          severity: oldAlert.severity,
          triggeredAt: oldAlert.triggeredAt,
          metadata: {
            ...oldAlert.metadata ?? {},
            'violations': _currentFlightViolations,
          },
          resolved: oldAlert.resolved,
          resolvedAt: oldAlert.resolvedAt,
          resolvedBy: oldAlert.resolvedBy,
          resolutionNotes: oldAlert.resolutionNotes,
        );
        await _savePendingAlerts();
      }
      
      // Try Firestore update - use SET with merge to handle nested objects properly
      try {
        print('🔄 [AlertService] EXIT update - Firestore alert: $_currentFlightAlertId');
        print('   Violations count: ${_currentFlightViolations.length}');
        print('   Active violations: ${_activeViolations.length}');
        print('   Exited zone: ${tracker.zoneName}');
        
        // Use set with merge to properly update nested metadata
        await _db.collection('alerts').doc(_currentFlightAlertId).set({
          'reason': reason,
          'metadata': {
            'violations': _currentFlightViolations,
            'violationsCount': _currentFlightViolations.length,
            'airspaceViolation': _activeViolations.isNotEmpty,
            'status': _activeViolations.isEmpty ? 'all_exited' : 'in_progress',
          },
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        
        print('✅ [AlertService] EXIT - Firestore alert updated successfully');
        log('[AlertService] ✓ Updated alert $_currentFlightAlertId with exit data');
      } catch (e) {
        print('❌ [AlertService] EXIT - Firestore update failed: $e');
        log('[AlertService] ⚠️ Could not update Firestore: $e');
      }
      
      notifyListeners();
    } catch (e) {
      log('[AlertService] ✗ Error updating flight alert: $e');
    }
  }
  
  /// Build comprehensive reason text showing all violations
  String _buildFlightAlertReason() {
    final buffer = StringBuffer();
    buffer.writeln('🚨 FLIGHT SAFETY ALERT');
    buffer.writeln();
    buffer.writeln('Total airspace violations: ${_currentFlightViolations.length}');
    buffer.writeln('Currently in restricted airspace: ${_activeViolations.isNotEmpty ? "YES" : "NO"}');
    
    if (_activeViolations.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('⚠️ CURRENTLY IN:');
      for (final tracker in _activeViolations.values) {
        final duration = tracker.duration.inSeconds;
        buffer.writeln('  • ${tracker.zoneName} (${tracker.zoneType}) - ${_formatSeconds(duration)}');
      }
    }
    
    buffer.writeln();
    buffer.writeln('VIOLATION HISTORY:');
    buffer.writeln('─' * 50);
    
    for (var i = 0; i < _currentFlightViolations.length; i++) {
      final v = _currentFlightViolations[i];
      buffer.writeln();
      buffer.writeln('${i + 1}. ${v['zoneName']} (${v['zoneType']})');
      buffer.writeln('   Class: ${v['zoneClass']}');
      buffer.writeln('   Entered: ${_formatIsoDateTime(v['entryTime'])}');
      buffer.writeln('   Entry: ${v['entryLatitude'].toStringAsFixed(6)}, ${v['entryLongitude'].toStringAsFixed(6)}');
      buffer.writeln('   Entry Alt: ${v['entryAltitude'].toStringAsFixed(0)}m');
      
      if (v['status'] == 'completed') {
        buffer.writeln('   Exited: ${_formatIsoDateTime(v['exitTime'])}');
        buffer.writeln('   Exit: ${v['exitLatitude'].toStringAsFixed(6)}, ${v['exitLongitude'].toStringAsFixed(6)}');
        buffer.writeln('   Exit Alt: ${v['exitAltitude'].toStringAsFixed(0)}m');
        buffer.writeln('   Duration: ${_formatSeconds(v['durationSeconds'])}');
        buffer.writeln('   Status: ✅ EXITED');
      } else if (v['status'] == 'landed_in_airspace') {
        buffer.writeln('   Landed: ${_formatIsoDateTime(v['exitTime'])}');
        buffer.writeln('   Landing: ${v['exitLatitude'].toStringAsFixed(6)}, ${v['exitLongitude'].toStringAsFixed(6)}');
        buffer.writeln('   Duration: ${_formatSeconds(v['durationSeconds'])}');
        buffer.writeln('   Status: 🛬 LANDED IN AIRSPACE');
      } else {
        buffer.writeln('   Status: ⚠️ IN PROGRESS (${_formatSeconds(DateTime.now().difference(DateTime.parse(v['entryTime'])).inSeconds)})');
      }
    }
    
    return buffer.toString();
  }
  
  /// Format ISO datetime string for display
  String _formatIsoDateTime(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return _formatDateTime(dt);
    } catch (e) {
      return iso;
    }
  }
  
  /// Format seconds to human-readable duration
  String _formatSeconds(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${secs}s';
    }
    return '${secs}s';
  }

  /// Format DateTime for display
  String _formatDateTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
  
  /// Finalize active violations when landing (treat landing as exit point)
  Future<void> finalizeActiveViolationsOnLanding({
    required double latitude,
    required double longitude,
    required double altitudeM,
  }) async {
    if (_activeViolations.isEmpty || _currentFlightAlertId == null) return;
    
    final now = DateTime.now();
    print('🛬 [AlertService] Finalizing ${_activeViolations.length} active violations on landing');
    
    // Mark all active violations as "landed in airspace"
    for (final tracker in _activeViolations.values) {
      final violationIndex = _currentFlightViolations.indexWhere(
        (v) => v['zoneId'] == tracker.zoneId && v['status'] == 'in_progress'
      );
      
      if (violationIndex != -1) {
        _currentFlightViolations[violationIndex]['exitTime'] = now.toIso8601String();
        _currentFlightViolations[violationIndex]['exitLatitude'] = latitude;
        _currentFlightViolations[violationIndex]['exitLongitude'] = longitude;
        _currentFlightViolations[violationIndex]['exitAltitude'] = altitudeM;
        _currentFlightViolations[violationIndex]['durationSeconds'] = tracker.duration.inSeconds;
        _currentFlightViolations[violationIndex]['status'] = 'landed_in_airspace';
        _currentFlightViolations[violationIndex]['maxAltitude'] = tracker.maxAltitude;
        _currentFlightViolations[violationIndex]['minAltitude'] = tracker.minAltitude;
        
        print('🛬 [AlertService] Finalized ${tracker.zoneName} as landed_in_airspace');
      }
    }
    
    // Update the flight alert with final status
    await _updateFlightAlertOnLanding();
  }
  
  /// Update flight alert when landing
  Future<void> _updateFlightAlertOnLanding() async {
    if (_currentFlightAlertId == null) return;
    
    final reason = _buildFlightAlertReason();
    
    try {
      // Update in local storage
      final index = _pendingAlerts.indexWhere((a) => a.id == _currentFlightAlertId);
      if (index != -1) {
        final oldAlert = _pendingAlerts[index];
        _pendingAlerts[index] = AlertRecord(
          id: oldAlert.id,
          uid: oldAlert.uid,
          displayName: oldAlert.displayName,
          shvNumber: oldAlert.shvNumber,
          licenseType: oldAlert.licenseType,
          alertType: oldAlert.alertType,
          reason: reason,
          severity: oldAlert.severity,
          triggeredAt: oldAlert.triggeredAt,
          metadata: {
            ...oldAlert.metadata ?? {},
            'violations': _currentFlightViolations,
            'status': 'flight_ended',
          },
          resolved: oldAlert.resolved,
          resolvedAt: oldAlert.resolvedAt,
          resolvedBy: oldAlert.resolvedBy,
          resolutionNotes: oldAlert.resolutionNotes,
        );
        await _savePendingAlerts();
      }
      
      // Try Firestore update - use SET with merge to handle nested objects properly
      try {
        print('🛬 [AlertService] LANDING - Updating Firestore alert: $_currentFlightAlertId');
        print('   Final violations count: ${_currentFlightViolations.length}');
        
        // Use set with merge to properly update nested metadata
        await _db.collection('alerts').doc(_currentFlightAlertId).set({
          'reason': reason,
          'metadata': {
            'violations': _currentFlightViolations,
            'violationsCount': _currentFlightViolations.length,
            'airspaceViolation': false,
            'status': 'flight_ended',
          },
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        
        print('✅ [AlertService] LANDING - Firestore alert updated successfully');
        log('[AlertService] ✓ Updated alert $_currentFlightAlertId with landing data');
      } catch (e) {
        print('❌ [AlertService] LANDING - Firestore update failed: $e');
        log('[AlertService] ⚠️ Could not update Firestore: $e');
      }
      
      notifyListeners();
    } catch (e) {
      log('[AlertService] ✗ Error updating flight alert on landing: $e');
    }
  }

  /// Check credentials at flight start (takeoff)
  /// Call this when flight starts
  Future<void> checkCredentialsAtTakeoff({
    required String uid,
    required String displayName,
    required String shvNumber,
    required String licenseType,
    required bool membershipValid,
    required bool insuranceValid,
    required double latitude,
    required double longitude,
    required double altitudeM,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    // Check membership validity
    if (!membershipValid) {
      await createAlert(
        uid: uid,
        displayName: displayName,
        shvNumber: shvNumber,
        licenseType: licenseType,
        alertType: AlertType.membershipExpired.value,
        reason: 'Membership not valid at takeoff time',
        severity: AlertSeverity.high.value,
        metadata: {
          'latitude': latitude,
          'longitude': longitude,
          'altitude': altitudeM,
        },
      );
    }

    // Check insurance validity
    if (!insuranceValid) {
      await createAlert(
        uid: uid,
        displayName: displayName,
        shvNumber: shvNumber,
        licenseType: licenseType,
        alertType: AlertType.insuranceExpired.value,
        reason: 'Insurance not valid at takeoff time',
        severity: AlertSeverity.high.value,
        metadata: {
          'latitude': latitude,
          'longitude': longitude,
          'altitude': altitudeM,
        },
      );
    }
  }

  /// Create an alert only if not a duplicate (within cooldown period)
  /// Returns the alert ID, or null if duplicate
  Future<String?> _createAlertIfNotDuplicate({
    required String uid,
    required String displayName,
    required String shvNumber,
    required String licenseType,
    required String alertType,
    required String reason,
    required String severity,
    Map<String, dynamic>? metadata,
    required String dedupeKey,
  }) async {
    final now = DateTime.now();
    final lastAlertTime = _recentAlerts[dedupeKey];

    // Check if we've already created this alert recently
    if (lastAlertTime != null) {
      final timeSinceLastAlert = now.difference(lastAlertTime);
      if (timeSinceLastAlert < FlightConstants.alertCooldownDuration) {
        // Skip duplicate alert
        return null;
      }
    }

    // Record this alert time for deduplication
    _recentAlerts[dedupeKey] = now;

    // Create the alert
    return await createAlert(
      uid: uid,
      displayName: displayName,
      shvNumber: shvNumber,
      licenseType: licenseType,
      alertType: alertType,
      reason: reason,
      severity: severity,
      metadata: metadata,
    );
  }

  /// Create an alert and queue for sync
  /// Returns the alert ID for later updates
  Future<String> createAlert({
    required String uid,
    required String displayName,
    required String shvNumber,
    required String licenseType,
    required String alertType,
    required String reason,
    required String severity,
    Map<String, dynamic>? metadata,
  }) async {
    // Generate a deterministic ID so we can update the SAME document later
    final alertId = DateTime.now().millisecondsSinceEpoch.toString();

    final alert = AlertRecord(
      id: alertId,
      uid: uid,
      displayName: displayName,
      shvNumber: shvNumber,
      licenseType: licenseType,
      alertType: alertType,
      reason: reason,
      severity: severity,
      triggeredAt: DateTime.now(),
      metadata: metadata,
    );

    // Add to pending queue
    _pendingAlerts.add(alert);

    // Save to local storage immediately
    await _savePendingAlerts();

    // Notify UI of new alert
    onAlertCreated?.call(alert);
    notifyListeners();

    log('[AlertService] ⚠️ Alert created: $alertType - $reason');
    print('⚠️ [AlertService] ALERT: $alertType - $reason');

    // Try to sync immediately (non-blocking)
    _syncAlertsToFirestore();
    
    // Return the alert ID we generated above
    return alertId;
  }

  /// Sync pending alerts to Firestore
  Future<void> _syncAlertsToFirestore() async {
    if (_syncing || _pendingAlerts.isEmpty) return;

    _syncing = true;
    notifyListeners();

    try {
      final alertsToSync = List<AlertRecord>.from(_pendingAlerts);

      for (final alert in alertsToSync) {
        try {
          final alertId = alert.id ?? DateTime.now().millisecondsSinceEpoch.toString();
          final alertToSync = alert.id == null
              ? alert.copyWith(id: alertId)
              : alert;

          // Use a fixed document ID so later updates hit the SAME doc
          await _db
              .collection('alerts')
              .doc(alertId)
              .set(alertToSync.toFirestore(), SetOptions(merge: true));

          // Remove from pending queue on success
          _pendingAlerts.remove(alert);
          log('[AlertService] ✓ Alert synced: ${alert.alertType}');
        } catch (e) {
          log('[AlertService] ✗ Error syncing alert ${alert.alertType}: $e');
          // Keep in queue for retry
          break; // Stop if one fails (likely network issue)
        }
      }

      // Save updated pending queue
      await _savePendingAlerts();
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Force sync pending alerts (call when connectivity restored)
  Future<void> forceSyncPendingAlerts() async {
    if (_pendingAlerts.isEmpty) return;
    await _syncAlertsToFirestore();
  }

  /// Save pending alerts to local storage
  Future<void> _savePendingAlerts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alertsJson =
          _pendingAlerts.map((a) => jsonEncode(a.toJson())).toList();
      await prefs.setStringList('pending_alerts', alertsJson);
    } catch (e) {
      log('[AlertService] Error saving pending alerts: $e');
    }
  }

  /// Load pending alerts from local storage
  Future<void> _loadPendingAlerts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alertsJson = prefs.getStringList('pending_alerts') ?? [];

      _pendingAlerts = alertsJson
          .map((json) => AlertRecord.fromJson(jsonDecode(json)))
          .toList();

      log('[AlertService] Loaded ${_pendingAlerts.length} pending alerts from storage');
    } catch (e) {
      log('[AlertService] Error loading pending alerts: $e');
      _pendingAlerts = [];
    }
  }

  /// Clear recent alerts tracking (call when flight ends)
  void clearRecentAlerts() {
    _recentAlerts.clear();
    _activeViolations.clear();
    _currentFlightAlertId = null;
    _currentFlightViolations.clear();
    log('[AlertService] Cleared recent alerts, active violations, and flight-level tracking');
  }

  /// Get the most recent alert (for UI display)
  AlertRecord? get mostRecentAlert {
    if (_pendingAlerts.isEmpty) return null;
    return _pendingAlerts.last;
  }

  /// Get alert statistics
  Map<String, int> getAlertStats() {
    final stats = <String, int>{};
    for (final alert in _pendingAlerts) {
      stats[alert.alertType] = (stats[alert.alertType] ?? 0) + 1;
    }
    return stats;
  }

  /// Check if there are critical alerts pending
  bool get hasCriticalAlerts {
    return _pendingAlerts
        .any((a) => a.severity == AlertSeverity.critical.value);
  }

  @override
  void dispose() {
    // Save any pending alerts before disposing
    _savePendingAlerts();
    super.dispose();
  }
}
