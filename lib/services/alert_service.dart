// File: lib/services/alert_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert_model.dart';
import 'airspace_service.dart';
import 'connectivity_service.dart';
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

/// Represents a queued Firestore operation for offline support
class _PendingFirestoreOperation {
  final String type; // 'create', 'update', 'set_merge'
  final String collection;
  final String documentId;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final int retryCount;
  
  _PendingFirestoreOperation({
    required this.type,
    required this.collection,
    required this.documentId,
    required this.data,
    required this.timestamp,
    this.retryCount = 0,
  });
  
  Map<String, dynamic> toJson() => {
    'type': type,
    'collection': collection,
    'documentId': documentId,
    'data': data,
    'timestamp': timestamp.toIso8601String(),
    'retryCount': retryCount,
  };
  
  factory _PendingFirestoreOperation.fromJson(Map<String, dynamic> json) {
    return _PendingFirestoreOperation(
      type: json['type'] ?? 'set_merge',
      collection: json['collection'] ?? 'alerts',
      documentId: json['documentId'] ?? '',
      data: Map<String, dynamic>.from(json['data'] ?? {}),
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      retryCount: json['retryCount'] ?? 0,
    );
  }
  
  _PendingFirestoreOperation copyWithIncrementedRetry() {
    return _PendingFirestoreOperation(
      type: type,
      collection: collection,
      documentId: documentId,
      data: data,
      timestamp: timestamp,
      retryCount: retryCount + 1,
    );
  }
}

/// Service for detecting and logging flight safety alerts
///
/// Features:
/// - Detects airspace violations, altitude violations, and credential issues
/// - Creates alert records in Firestore during flight
/// - **OFFLINE-FIRST**: Queues ALL operations locally and syncs when online
/// - Automatic retry with exponential backoff on network failures
/// - Connectivity-aware: syncs immediately when connection is restored
/// - Prevents duplicate alerts within a cooldown period
/// - Tracks time spent in restricted airspaces
/// - Notifies listeners for UI updates
class AlertService extends ChangeNotifier {
  /// Expose current flight alert id for admin lookup
  String? get currentFlightAlertId => _currentFlightAlertId;
  static final AlertService _instance = AlertService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final AirspaceService _airspaceService = AirspaceService();
  final ConnectivityService _connectivityService = ConnectivityService();

  // Local queue for offline alerts (the primary source of truth)
  List<AlertRecord> _localAlerts = [];
  
  // Queue for pending Firestore operations (for offline support)
  List<_PendingFirestoreOperation> _pendingOperations = [];
  
  bool _syncing = false;
  bool _isInitialized = false;
  Timer? _periodicSyncTimer;
  VoidCallback? _connectivityCallbackUnsubscribe;

  // Duplicate prevention: track recent alerts by type
  final Map<String, DateTime> _recentAlerts = {};
  
  // Track active airspace violations (by zone ID) - supports overlapping zones
  final Map<String, AirspaceViolationTracker> _activeViolations = {};
  
  // Single alert per flight that tracks ALL violations
  String? _currentFlightAlertId;
  final List<Map<String, dynamic>> _currentFlightViolations = [];

  // Callbacks for UI notifications
  Function(AlertRecord)? onAlertCreated;

  // Constants for sync behavior
  static const int _maxRetryCount = 10;
  static const Duration _periodicSyncInterval = Duration(seconds: 30);
  // Note: _initialRetryDelay reserved for future exponential backoff implementation

  factory AlertService() {
    return _instance;
  }

  AlertService._internal();

  // Getters
  List<AlertRecord> get localAlerts => List.unmodifiable(_localAlerts);
  List<AlertRecord> get pendingAlerts => _localAlerts.where((a) => !_isAlertSynced(a.id)).toList();
  bool get isSyncing => _syncing;
  bool get isInitialized => _isInitialized;
  int get pendingCount => _pendingOperations.length;
  bool get isOnline => _connectivityService.isOnline;
  
  /// Get current active violations (pilot is still in these airspaces)
  Map<String, AirspaceViolationTracker> get activeViolations => 
      Map.unmodifiable(_activeViolations);
  
  /// Check if pilot is currently in any restricted airspace
  bool get isInRestrictedAirspace => _activeViolations.isNotEmpty;

  /// Check if a specific alert has been synced to Firestore
  bool _isAlertSynced(String? alertId) {
    if (alertId == null) return false;
    // An alert is considered synced if there are no pending operations for it
    return !_pendingOperations.any((op) => op.documentId == alertId);
  }

  /// Initialize the alert service
  /// Call this at app startup
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize connectivity service first
      await _connectivityService.initialize();
      
      // Register for connectivity restoration callbacks
      _connectivityCallbackUnsubscribe = _connectivityService.addOnConnectivityChangedCallback(
        (isOnline) {
          if (isOnline) {
            debugPrint('📡 [AlertService] Connectivity restored - triggering sync');
            _syncPendingOperations();
          }
        },
      );

      // Initialize airspace service
      await _airspaceService.initialize();

      // Load local alerts from storage
      await _loadLocalAlerts();
      
      // Load pending operations from storage
      await _loadPendingOperations();

      // Start periodic sync timer
      _startPeriodicSync();

      // Try to sync any pending operations if online
      if (_connectivityService.isOnline && _pendingOperations.isNotEmpty) {
        _syncPendingOperations();
      }

      _isInitialized = true;
      log('[AlertService] ✓ Initialized - ${_airspaceService.zoneCount} airspace zones, ${_localAlerts.length} local alerts, ${_pendingOperations.length} pending ops');
    } catch (e) {
      log('[AlertService] ✗ Error initializing: $e');
      _isInitialized = true; // Mark as initialized to prevent retry loops
    }
  }

  /// Start periodic sync timer
  void _startPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(_periodicSyncInterval, (_) {
      if (_pendingOperations.isNotEmpty && _connectivityService.isOnline) {
        debugPrint('⏰ [AlertService] Periodic sync triggered - ${_pendingOperations.length} pending ops');
        _syncPendingOperations();
      }
    });
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
    
    debugPrint('🔍 [AlertService] checkFlightSafety:');
    debugPrint('   Current zones at position: ${currentZones.length}');
    debugPrint('   Active violations: ${_activeViolations.length}');
    debugPrint('   Online: ${_connectivityService.isOnline}');
    
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
          debugPrint('🚨 [AlertService] Created flight safety alert: $_currentFlightAlertId');
        } else {
          // Update existing alert with new entry
          await _updateFlightAlertWithEntry(
            zone: zone,
            latitude: latitude,
            longitude: longitude,
            altitudeM: altitudeM,
          );
        }
        
        debugPrint('⚠️ [AlertService] ENTERED AIRSPACE: ${zone.name} (${zone.type})');
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
    
    debugPrint('   Exited zones: ${exitedZoneIds.length}');
    
    for (final zoneId in exitedZoneIds) {
      final tracker = _activeViolations.remove(zoneId);
      if (tracker != null) {
        debugPrint('✅ [AlertService] EXITING AIRSPACE: ${tracker.zoneName}');
        
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
      // Update in local storage FIRST (always succeeds)
      final index = _localAlerts.indexWhere((a) => a.id == _currentFlightAlertId);
      if (index != -1) {
        final oldAlert = _localAlerts[index];
        _localAlerts[index] = AlertRecord(
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
            'violationsCount': _currentFlightViolations.length,
            'airspaceViolation': _activeViolations.isNotEmpty,
            'status': 'in_progress',
          },
          resolved: oldAlert.resolved,
          resolvedAt: oldAlert.resolvedAt,
          resolvedBy: oldAlert.resolvedBy,
          resolutionNotes: oldAlert.resolutionNotes,
        );
        await _saveLocalAlerts();
      }
      
      // Queue Firestore operation (will sync when online)
      debugPrint('🔄 [AlertService] ENTRY - Queueing Firestore update: $_currentFlightAlertId');
      debugPrint('   Violations count: ${_currentFlightViolations.length}');
      debugPrint('   Active violations: ${_activeViolations.length}');
      
      await _queueFirestoreOperation(
        type: 'set_merge',
        collection: 'alerts',
        documentId: _currentFlightAlertId!,
        data: {
          'reason': reason,
          'metadata': {
            'violations': _currentFlightViolations,
            'violationsCount': _currentFlightViolations.length,
            'airspaceViolation': _activeViolations.isNotEmpty,
            'status': 'in_progress',
          },
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      
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
      // Update in local storage FIRST (always succeeds)
      final index = _localAlerts.indexWhere((a) => a.id == _currentFlightAlertId);
      if (index != -1) {
        final oldAlert = _localAlerts[index];
        _localAlerts[index] = AlertRecord(
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
            'violationsCount': _currentFlightViolations.length,
            'airspaceViolation': _activeViolations.isNotEmpty,
            'status': _activeViolations.isEmpty ? 'all_exited' : 'in_progress',
          },
          resolved: oldAlert.resolved,
          resolvedAt: oldAlert.resolvedAt,
          resolvedBy: oldAlert.resolvedBy,
          resolutionNotes: oldAlert.resolutionNotes,
        );
        await _saveLocalAlerts();
      }
      
      // Queue Firestore operation (will sync when online)
      debugPrint('🔄 [AlertService] EXIT update - Queueing Firestore update: $_currentFlightAlertId');
      debugPrint('   Violations count: ${_currentFlightViolations.length}');
      debugPrint('   Active violations: ${_activeViolations.length}');
      debugPrint('   Exited zone: ${tracker.zoneName}');
      
      await _queueFirestoreOperation(
        type: 'set_merge',
        collection: 'alerts',
        documentId: _currentFlightAlertId!,
        data: {
          'reason': reason,
          'metadata': {
            'violations': _currentFlightViolations,
            'violationsCount': _currentFlightViolations.length,
            'airspaceViolation': _activeViolations.isNotEmpty,
            'status': _activeViolations.isEmpty ? 'all_exited' : 'in_progress',
          },
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      
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
    debugPrint('🛬 [AlertService] Finalizing ${_activeViolations.length} active violations on landing');
    
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
        
        debugPrint('🛬 [AlertService] Finalized ${tracker.zoneName} as landed_in_airspace');
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
      // Update in local storage FIRST (always succeeds)
      final index = _localAlerts.indexWhere((a) => a.id == _currentFlightAlertId);
      if (index != -1) {
        final oldAlert = _localAlerts[index];
        _localAlerts[index] = AlertRecord(
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
            'violationsCount': _currentFlightViolations.length,
            'airspaceViolation': false,
            'status': 'flight_ended',
          },
          resolved: oldAlert.resolved,
          resolvedAt: oldAlert.resolvedAt,
          resolvedBy: oldAlert.resolvedBy,
          resolutionNotes: oldAlert.resolutionNotes,
        );
        await _saveLocalAlerts();
      }
      
      // Queue Firestore operation (will sync when online)
      debugPrint('🛬 [AlertService] LANDING - Queueing Firestore update: $_currentFlightAlertId');
      debugPrint('   Final violations count: ${_currentFlightViolations.length}');
      
      await _queueFirestoreOperation(
        type: 'set_merge',
        collection: 'alerts',
        documentId: _currentFlightAlertId!,
        data: {
          'reason': reason,
          'metadata': {
            'violations': _currentFlightViolations,
            'violationsCount': _currentFlightViolations.length,
            'airspaceViolation': false,
            'status': 'flight_ended',
          },
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      
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
  /// 
  /// This method is OFFLINE-FIRST:
  /// 1. Creates the alert locally with a generated ID
  /// 2. Saves to local storage immediately
  /// 3. Queues Firestore operation for later sync
  /// 4. Triggers sync if online
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

    // Add to local alerts (the source of truth)
    _localAlerts.add(alert);

    // Save to local storage immediately
    await _saveLocalAlerts();

    // Queue Firestore operation with type 'create' to ensure all fields are written
    await _queueFirestoreOperation(
      type: 'create',
      collection: 'alerts',
      documentId: alertId,
      data: alert.toFirestore(),
    );

    // Notify UI of new alert
    onAlertCreated?.call(alert);
    notifyListeners();

    log('[AlertService] ⚠️ Alert created: $alertType - $reason (queued for sync)');
    debugPrint('⚠️ [AlertService] ALERT: $alertType - $reason');
    debugPrint('   Online: ${_connectivityService.isOnline}, Pending ops: ${_pendingOperations.length}');

    // Try to sync immediately if online (non-blocking)
    if (_connectivityService.isOnline) {
      _syncPendingOperations();
    }
    
    return alertId;
  }

  /// Queue a Firestore operation for later execution
  Future<void> _queueFirestoreOperation({
    required String type,
    required String collection,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    // Convert FieldValue.serverTimestamp() to a placeholder for serialization
    final serializableData = _makeSerializable(data);
    
    final operation = _PendingFirestoreOperation(
      type: type,
      collection: collection,
      documentId: documentId,
      data: serializableData,
      timestamp: DateTime.now(),
    );
    
    // CRITICAL: Only remove existing operations of the SAME TYPE for the same document
    // DO NOT remove CREATE operations when queuing updates (set_merge)!
    // This ensures offline-created alerts keep all their fields when synced.
    _pendingOperations.removeWhere(
      (op) => op.collection == collection && 
              op.documentId == documentId && 
              op.type == type
    );
    
    _pendingOperations.add(operation);
    await _savePendingOperations();
    
    debugPrint('📥 [AlertService] Queued operation: $type on $collection/$documentId');
  }
  
  /// Make data serializable for local storage
  /// Converts FieldValue objects to placeholders
  Map<String, dynamic> _makeSerializable(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    for (final entry in data.entries) {
      if (entry.value is FieldValue) {
        // Mark server timestamp fields for later restoration
        result[entry.key] = {'__fieldValue': 'serverTimestamp'};
      } else if (entry.value is Map<String, dynamic>) {
        result[entry.key] = _makeSerializable(entry.value as Map<String, dynamic>);
      } else if (entry.value is List) {
        result[entry.key] = (entry.value as List).map((item) {
          if (item is Map<String, dynamic>) {
            return _makeSerializable(item);
          }
          return item;
        }).toList();
      } else {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }
  
  /// Restore FieldValue objects from serialized placeholders
  Map<String, dynamic> _restoreFieldValues(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    for (final entry in data.entries) {
      if (entry.value is Map<String, dynamic>) {
        final map = entry.value as Map<String, dynamic>;
        if (map['__fieldValue'] == 'serverTimestamp') {
          result[entry.key] = FieldValue.serverTimestamp();
        } else {
          result[entry.key] = _restoreFieldValues(map);
        }
      } else if (entry.value is List) {
        result[entry.key] = (entry.value as List).map((item) {
          if (item is Map<String, dynamic>) {
            return _restoreFieldValues(item);
          }
          return item;
        }).toList();
      } else {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  /// Sync pending operations to Firestore
  Future<void> _syncPendingOperations() async {
    if (_syncing || _pendingOperations.isEmpty) return;
    if (!_connectivityService.isOnline) {
      debugPrint('📡 [AlertService] Offline - skipping sync');
      return;
    }

    _syncing = true;
    notifyListeners();
    
    debugPrint('🔄 [AlertService] Starting sync of ${_pendingOperations.length} operations');

    try {
      final operationsToSync = List<_PendingFirestoreOperation>.from(_pendingOperations);
      final successfulOps = <_PendingFirestoreOperation>[];
      final failedOps = <_PendingFirestoreOperation>[];

      for (final operation in operationsToSync) {
        try {
          // Restore FieldValue objects
          final data = _restoreFieldValues(operation.data);
          
          // Execute the operation
          final docRef = _db.collection(operation.collection).doc(operation.documentId);
          
          switch (operation.type) {
            case 'create':
              // CREATE: Use merge: false to ensure ALL fields are written
              // This is critical for offline-created alerts to have all required fields
              await docRef.set(data, SetOptions(merge: false));
              break;
            case 'set_merge':
            case 'update':
              // UPDATE: Use merge: true to only update specific fields
              await docRef.set(data, SetOptions(merge: true));
              break;
          }
          
          successfulOps.add(operation);
          debugPrint('✅ [AlertService] Synced: ${operation.collection}/${operation.documentId}');
          log('[AlertService] ✓ Synced alert: ${operation.documentId}');
        } catch (e) {
          debugPrint('❌ [AlertService] Sync failed: ${operation.documentId} - $e');
          
          // Check if we should retry
          if (operation.retryCount < _maxRetryCount) {
            failedOps.add(operation.copyWithIncrementedRetry());
          } else {
            log('[AlertService] ✗ Max retries exceeded for ${operation.documentId}');
            // Keep in queue but don't increment retry count further
            failedOps.add(operation);
          }
          
          // If this is a network error, stop trying more operations
          if (e.toString().contains('network') || 
              e.toString().contains('offline') ||
              e.toString().contains('unavailable')) {
            debugPrint('📡 [AlertService] Network error detected - stopping sync');
            break;
          }
        }
      }

      // Remove successful operations from queue
      // IMPORTANT: Only remove the exact operation that succeeded, not all operations for that document
      for (final op in successfulOps) {
        final index = _pendingOperations.indexWhere(
          (p) => p.collection == op.collection && 
                 p.documentId == op.documentId && 
                 p.type == op.type &&
                 p.timestamp == op.timestamp
        );
        if (index != -1) {
          _pendingOperations.removeAt(index);
        }
      }
      
      // Update failed operations with incremented retry count
      for (final op in failedOps) {
        final index = _pendingOperations.indexWhere(
          (p) => p.collection == op.collection && 
                 p.documentId == op.documentId &&
                 p.type == op.type &&
                 p.timestamp == op.timestamp
        );
        if (index != -1) {
          _pendingOperations[index] = op;
        }
      }

      // Save updated pending queue
      await _savePendingOperations();
      
      debugPrint('🔄 [AlertService] Sync complete: ${successfulOps.length} synced, ${_pendingOperations.length} remaining');
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Force sync pending operations (call when connectivity restored)
  Future<void> forceSyncPendingAlerts() async {
    if (_pendingOperations.isEmpty) {
      debugPrint('📡 [AlertService] No pending operations to sync');
      return;
    }
    debugPrint('📡 [AlertService] Force sync triggered - ${_pendingOperations.length} pending ops');
    await _syncPendingOperations();
  }

  /// Save local alerts to local storage
  Future<void> _saveLocalAlerts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alertsJson = _localAlerts.map((a) => jsonEncode(a.toJson())).toList();
      await prefs.setStringList('local_alerts', alertsJson);
    } catch (e) {
      log('[AlertService] Error saving local alerts: $e');
    }
  }

  /// Load local alerts from local storage
  Future<void> _loadLocalAlerts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alertsJson = prefs.getStringList('local_alerts') ?? [];

      _localAlerts = alertsJson
          .map((json) => AlertRecord.fromJson(jsonDecode(json)))
          .toList();

      log('[AlertService] Loaded ${_localAlerts.length} local alerts from storage');
    } catch (e) {
      log('[AlertService] Error loading local alerts: $e');
      _localAlerts = [];
    }
  }
  
  /// Save pending operations to local storage
  Future<void> _savePendingOperations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final opsJson = _pendingOperations.map((op) => jsonEncode(op.toJson())).toList();
      await prefs.setStringList('pending_firestore_ops', opsJson);
    } catch (e) {
      log('[AlertService] Error saving pending operations: $e');
    }
  }
  
  /// Load pending operations from local storage
  Future<void> _loadPendingOperations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final opsJson = prefs.getStringList('pending_firestore_ops') ?? [];
      
      _pendingOperations = opsJson
          .map((json) => _PendingFirestoreOperation.fromJson(jsonDecode(json)))
          .toList();
      
      log('[AlertService] Loaded ${_pendingOperations.length} pending operations from storage');
    } catch (e) {
      log('[AlertService] Error loading pending operations: $e');
      _pendingOperations = [];
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
    if (_localAlerts.isEmpty) return null;
    return _localAlerts.last;
  }

  /// Get alert statistics
  Map<String, int> getAlertStats() {
    final stats = <String, int>{};
    for (final alert in _localAlerts) {
      stats[alert.alertType] = (stats[alert.alertType] ?? 0) + 1;
    }
    return stats;
  }

  /// Check if there are critical alerts pending
  bool get hasCriticalAlerts {
    return _localAlerts.any((a) => a.severity == AlertSeverity.critical.value);
  }

  @override
  void dispose() {
    _periodicSyncTimer?.cancel();
    _connectivityCallbackUnsubscribe?.call();
    // Save any pending data before disposing
    _saveLocalAlerts();
    _savePendingOperations();
    super.dispose();
  }
}
