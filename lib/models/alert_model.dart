// File: lib/models/alert_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

/// Types of alerts that can be triggered during flight
enum AlertType {
  membershipExpired, // Membership not valid at takeoff
  insuranceExpired, // Insurance not valid at takeoff
  airspaceViolation, // Entered restricted airspace
  altitudeViolation, // Exceeded max altitude
  geofenceViolation, // Exited designated flight area
}

/// Extension to convert AlertType enum to/from string
extension AlertTypeExtension on AlertType {
  String get value {
    switch (this) {
      case AlertType.membershipExpired:
        return 'membership_expired';
      case AlertType.insuranceExpired:
        return 'insurance_expired';
      case AlertType.airspaceViolation:
        return 'airspace_violation';
      case AlertType.altitudeViolation:
        return 'altitude_violation';
      case AlertType.geofenceViolation:
        return 'geofence_violation';
    }
  }

  static AlertType fromString(String value) {
    switch (value) {
      case 'membership_expired':
        return AlertType.membershipExpired;
      case 'insurance_expired':
        return AlertType.insuranceExpired;
      case 'airspace_violation':
        return AlertType.airspaceViolation;
      case 'altitude_violation':
        return AlertType.altitudeViolation;
      case 'geofence_violation':
        return AlertType.geofenceViolation;
      default:
        return AlertType.airspaceViolation; // fallback
    }
  }
}

/// Alert severity levels
enum AlertSeverity {
  low,
  medium,
  high,
  critical,
}

extension AlertSeverityExtension on AlertSeverity {
  String get value {
    switch (this) {
      case AlertSeverity.low:
        return 'low';
      case AlertSeverity.medium:
        return 'medium';
      case AlertSeverity.high:
        return 'high';
      case AlertSeverity.critical:
        return 'critical';
    }
  }

  static AlertSeverity fromString(String value) {
    switch (value) {
      case 'low':
        return AlertSeverity.low;
      case 'medium':
        return AlertSeverity.medium;
      case 'high':
        return AlertSeverity.high;
      case 'critical':
        return AlertSeverity.critical;
      default:
        return AlertSeverity.medium;
    }
  }
}

/// Model for flight safety alerts
/// Tracks violations and safety issues during flight
class AlertRecord {
  final String? id;
  final String uid;
  final String displayName;
  final String shvNumber;
  final String licenseType;
  final String alertType; // AlertType.value string
  final String reason;
  final String severity; // 'low', 'medium', 'high', 'critical'
  final DateTime triggeredAt;
  final Map<String, dynamic>? metadata; // location, altitude, speed, etc.
  final bool resolved;
  final DateTime? resolvedAt;
  final String? resolvedBy; // Admin UID who resolved it
  final String? resolutionNotes;

  AlertRecord({
    this.id,
    required this.uid,
    required this.displayName,
    required this.shvNumber,
    required this.licenseType,
    required this.alertType,
    required this.reason,
    required this.severity,
    required this.triggeredAt,
    this.metadata,
    this.resolved = false,
    this.resolvedAt,
    this.resolvedBy,
    this.resolutionNotes,
  });

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() => {
        'uid': uid,
        'displayName': displayName,
        'shvNumber': shvNumber,
        'licenseType': licenseType,
        'alertType': alertType,
        'reason': reason,
        'severity': severity,
        'triggeredAt': Timestamp.fromDate(triggeredAt),
        'metadata': metadata,
        'resolved': resolved,
        'resolvedAt':
            resolvedAt != null ? Timestamp.fromDate(resolvedAt!) : null,
        'resolvedBy': resolvedBy,
        'resolutionNotes': resolutionNotes,
      };

  /// Create from Firestore document
  factory AlertRecord.fromFirestore(Map<String, dynamic> data, {String? id}) {
    return AlertRecord(
      id: id,
      uid: data['uid'] ?? '',
      displayName: data['displayName'] ?? '',
      shvNumber: data['shvNumber'] ?? '',
      licenseType: data['licenseType'] ?? '',
      alertType: data['alertType'] ?? '',
      reason: data['reason'] ?? '',
      severity: data['severity'] ?? 'medium',
      triggeredAt: data['triggeredAt'] is Timestamp
          ? (data['triggeredAt'] as Timestamp).toDate()
          : DateTime.tryParse(data['triggeredAt']?.toString() ?? '') ??
              DateTime.now(),
      metadata: data['metadata'] as Map<String, dynamic>?,
      resolved: data['resolved'] ?? false,
      resolvedAt: data['resolvedAt'] is Timestamp
          ? (data['resolvedAt'] as Timestamp).toDate()
          : (data['resolvedAt'] != null
              ? DateTime.tryParse(data['resolvedAt'].toString())
              : null),
      resolvedBy: data['resolvedBy'],
      resolutionNotes: data['resolutionNotes'],
    );
  }

  /// Convert to JSON for local storage (SharedPreferences)
  Map<String, dynamic> toJson() => {
        'id': id,
        'uid': uid,
        'displayName': displayName,
        'shvNumber': shvNumber,
        'licenseType': licenseType,
        'alertType': alertType,
        'reason': reason,
        'severity': severity,
        'triggeredAt': triggeredAt.toIso8601String(),
        'metadata': metadata,
        'resolved': resolved,
        'resolvedAt': resolvedAt?.toIso8601String(),
        'resolvedBy': resolvedBy,
        'resolutionNotes': resolutionNotes,
      };

  /// Create from JSON (local storage)
  factory AlertRecord.fromJson(Map<String, dynamic> json) {
    return AlertRecord(
      id: json['id'],
      uid: json['uid'] ?? '',
      displayName: json['displayName'] ?? '',
      shvNumber: json['shvNumber'] ?? '',
      licenseType: json['licenseType'] ?? '',
      alertType: json['alertType'] ?? '',
      reason: json['reason'] ?? '',
      severity: json['severity'] ?? 'medium',
      triggeredAt:
          DateTime.tryParse(json['triggeredAt'] ?? '') ?? DateTime.now(),
      metadata: json['metadata'] as Map<String, dynamic>?,
      resolved: json['resolved'] ?? false,
      resolvedAt: json['resolvedAt'] != null
          ? DateTime.tryParse(json['resolvedAt'])
          : null,
      resolvedBy: json['resolvedBy'],
      resolutionNotes: json['resolutionNotes'],
    );
  }

  /// Create a copy with updated fields
  AlertRecord copyWith({
    String? id,
    String? uid,
    String? displayName,
    String? shvNumber,
    String? licenseType,
    String? alertType,
    String? reason,
    String? severity,
    DateTime? triggeredAt,
    Map<String, dynamic>? metadata,
    bool? resolved,
    DateTime? resolvedAt,
    String? resolvedBy,
    String? resolutionNotes,
  }) {
    return AlertRecord(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      shvNumber: shvNumber ?? this.shvNumber,
      licenseType: licenseType ?? this.licenseType,
      alertType: alertType ?? this.alertType,
      reason: reason ?? this.reason,
      severity: severity ?? this.severity,
      triggeredAt: triggeredAt ?? this.triggeredAt,
      metadata: metadata ?? this.metadata,
      resolved: resolved ?? this.resolved,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      resolvedBy: resolvedBy ?? this.resolvedBy,
      resolutionNotes: resolutionNotes ?? this.resolutionNotes,
    );
  }

  @override
  String toString() {
    return 'AlertRecord(id: $id, alertType: $alertType, severity: $severity, reason: $reason)';
  }
}
