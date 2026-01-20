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

/// Service for detecting and logging flight safety alerts
///
/// Features:
/// - Detects airspace violations, altitude violations, and credential issues
/// - Creates alert records in Firestore during flight
/// - Queues alerts locally if offline and syncs when connection returns
/// - Prevents duplicate alerts within a cooldown period
/// - Notifies listeners for UI updates
class AlertService extends ChangeNotifier {
  static final AlertService _instance = AlertService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final AirspaceService _airspaceService = AirspaceService();

  // Local queue for offline alerts
  List<AlertRecord> _pendingAlerts = [];
  bool _syncing = false;
  bool _isInitialized = false;

  // Duplicate prevention: track recent alerts by type
  final Map<String, DateTime> _recentAlerts = {};

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

    // Check airspace violation
    final restrictedZone =
        _airspaceService.getRestrictedZone(latitude, longitude, altitudeM);
    if (restrictedZone != null) {
      await _createAlertIfNotDuplicate(
        uid: uid,
        displayName: displayName,
        shvNumber: shvNumber,
        licenseType: licenseType,
        alertType: AlertType.airspaceViolation.value,
        reason: 'Entered ${restrictedZone.name} (${restrictedZone.type})',
        severity: AlertSeverity.critical.value,
        metadata: {
          'latitude': latitude,
          'longitude': longitude,
          'altitude': altitudeM,
          'restrictedZoneName': restrictedZone.name,
          'restrictedZoneType': restrictedZone.type,
        },
        dedupeKey: 'airspace_${restrictedZone.name}',
      );
    }

    // Check altitude violation
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
        },
        dedupeKey: 'altitude_violation',
      );
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
  Future<void> _createAlertIfNotDuplicate({
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
        return;
      }
    }

    // Record this alert time for deduplication
    _recentAlerts[dedupeKey] = now;

    // Create the alert
    await createAlert(
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
  Future<void> createAlert({
    required String uid,
    required String displayName,
    required String shvNumber,
    required String licenseType,
    required String alertType,
    required String reason,
    required String severity,
    Map<String, dynamic>? metadata,
  }) async {
    final alert = AlertRecord(
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
          await _db.collection('alerts').add(alert.toFirestore());

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
    log('[AlertService] Cleared recent alerts tracking');
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
