// File: lib/models/flight.dart

import 'package:cloud_firestore/cloud_firestore.dart';

/// Flight model with offline-first support
class Flight {
  final String? id;
  final String studentUid;
  final String mainSchoolId; // user's home school
  final String thisFlightSchoolId; // school chosen for this specific flight (can differ for guest flights)
  String date; // ISO 8601 string for cache compatibility
  String takeoffName;
  String? takeoffId;
  double takeoffAltitude;
  String landingName;
  String? landingId;
  double landingAltitude;
  double altitudeDifference;
  int flightTimeMinutes;
  String? comment;
  String? startTypeId;
  String? flightTypeId;
  List<String> advancedManeuvers;
  List<String> schoolManeuvers;
  String licenseType; // 'student' or 'pilot'
  String status; // 'pending' or 'accepted'
  DateTime? createdAt;
  DateTime? updatedAt;
  bool gpsTracked; // true if tracked by GPS, false if manually added
  bool isPendingUpload; // Local flag: not synced yet

  Flight({
    this.id,
    required this.studentUid,
    required this.mainSchoolId,
    required this.thisFlightSchoolId,
    required this.date,
    required this.takeoffName,
    this.takeoffId,
    required this.takeoffAltitude,
    required this.landingName,
    this.landingId,
    required this.landingAltitude,
    required this.altitudeDifference,
    required this.flightTimeMinutes,
    this.comment,
    this.startTypeId,
    this.flightTypeId,
    this.advancedManeuvers = const [],
    this.schoolManeuvers = const [],
    required this.licenseType,
    this.status = 'pending',
    this.createdAt,
    this.updatedAt,
    this.gpsTracked = false,
    this.isPendingUpload = false,
  });

  /// Parse from Firestore data
  factory Flight.fromFirestore(Map<String, dynamic> data, String docId, String studentUid) {
    return Flight(
      id: docId,
      studentUid: studentUid,
      mainSchoolId: data['main_school_id'] ?? data['mainschool_id'] ?? data['school_id'] ?? '',
      thisFlightSchoolId: data['thisflight_school_id'] ?? data['school_id'] ?? data['main_school_id'] ?? data['mainschool_id'] ?? '',
      date: _parseDate(data['date']),
      takeoffName: data['takeoffName'] ?? '',
      takeoffId: data['takeoffId'],
      takeoffAltitude: _parseDouble(data['takeoffAltitude']),
      landingName: data['landingName'] ?? '',
      landingId: data['landingId'],
      landingAltitude: _parseDouble(data['landingAltitude']),
      altitudeDifference: _parseDouble(data['altitudeDifference']),
      flightTimeMinutes: data['flightTimeMinutes'] ?? 0,
      comment: data['comment'],
      startTypeId: data['startTypeId'],
      flightTypeId: data['flightTypeId'],
      advancedManeuvers: List<String>.from(data['advancedManeuvers'] ?? []),
      schoolManeuvers: List<String>.from(data['schoolManeuvers'] ?? []),
      licenseType: data['license_type'] ?? 'student',
      status: data['status'] ?? 'pending',
      createdAt: _parseTimestamp(data['created_at']),
      updatedAt: _parseTimestamp(data['updated_at']),
      gpsTracked: data['gps_tracked'] ?? false,
      isPendingUpload: false,
    );
  }

  /// Parse from cached data
  factory Flight.fromCache(Map<String, dynamic> data, String studentUid) {
    return Flight(
      id: data['id'],
      studentUid: studentUid,
      mainSchoolId: data['main_school_id'] ?? data['mainschool_id'] ?? data['school_id'] ?? '',
      thisFlightSchoolId: data['thisflight_school_id'] ?? data['school_id'] ?? data['main_school_id'] ?? data['mainschool_id'] ?? '',
      date: data['date'] ?? DateTime.now().toIso8601String(),
      takeoffName: data['takeoffName'] ?? '',
      takeoffId: data['takeoffId'],
      takeoffAltitude: _parseDouble(data['takeoffAltitude']),
      landingName: data['landingName'] ?? '',
      landingId: data['landingId'],
      landingAltitude: _parseDouble(data['landingAltitude']),
      altitudeDifference: _parseDouble(data['altitudeDifference']),
      flightTimeMinutes: data['flightTimeMinutes'] ?? 0,
      comment: data['comment'],
      startTypeId: data['startTypeId'],
      flightTypeId: data['flightTypeId'],
      advancedManeuvers: List<String>.from(data['advancedManeuvers'] ?? []),
      schoolManeuvers: List<String>.from(data['schoolManeuvers'] ?? []),
      licenseType: data['license_type'] ?? 'student',
      status: data['status'] ?? 'pending',
      createdAt: data['created_at'] != null ? DateTime.parse(data['created_at']) : null,
      updatedAt: data['updated_at'] != null ? DateTime.parse(data['updated_at']) : null,
      gpsTracked: data['gps_tracked'] ?? false,
      isPendingUpload: data['isPendingUpload'] ?? false,
    );
  }

  /// Convert to Firestore map
  Map<String, dynamic> toFirestore() {
    return {
      'main_school_id': mainSchoolId,
      'thisflight_school_id': thisFlightSchoolId,
      'date': Timestamp.fromDate(DateTime.parse(date)),
      'takeoffName': takeoffName,
      'takeoffId': takeoffId,
      'takeoffAltitude': takeoffAltitude,
      'landingName': landingName,
      'landingId': landingId,
      'landingAltitude': landingAltitude,
      'altitudeDifference': altitudeDifference,
      'flightTimeMinutes': flightTimeMinutes,
      'comment': comment,
      'startTypeId': startTypeId,
      'flightTypeId': flightTypeId,
      'advancedManeuvers': advancedManeuvers,
      'schoolManeuvers': schoolManeuvers,
      'student_uid': studentUid,
      'license_type': licenseType,
      'status': status,
      'created_at': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'updated_at': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'gps_tracked': gpsTracked,
    };
  }

  /// Convert to cache map (JSON-serializable)
  Map<String, dynamic> toCache() {
    return {
      'id': id,
      'main_school_id': mainSchoolId,
      'thisflight_school_id': thisFlightSchoolId,
      'date': date,
      'takeoffName': takeoffName,
      'takeoffId': takeoffId,
      'takeoffAltitude': takeoffAltitude,
      'landingName': landingName,
      'landingId': landingId,
      'landingAltitude': landingAltitude,
      'altitudeDifference': altitudeDifference,
      'flightTimeMinutes': flightTimeMinutes,
      'comment': comment,
      'startTypeId': startTypeId,
      'flightTypeId': flightTypeId,
      'advancedManeuvers': advancedManeuvers,
      'schoolManeuvers': schoolManeuvers,
      'student_uid': studentUid,
      'license_type': licenseType,
      'status': status,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'gps_tracked': gpsTracked,
      'isPendingUpload': isPendingUpload,
    };
  }

  /// Generate a patch containing only fields that differ from oldFlight
  Map<String, dynamic> getPatch(Flight oldFlight) {
    final newMap = toFirestore();
    final oldMap = oldFlight.toFirestore();
    final patch = <String, dynamic>{};

    for (final key in newMap.keys) {
      final newValue = newMap[key];
      final oldValue = oldMap[key];

      if (key == 'date' && newValue is Timestamp && oldValue is Timestamp) {
        if (newValue.millisecondsSinceEpoch != oldValue.millisecondsSinceEpoch) {
          patch[key] = newValue;
        }
      } else if (newValue != oldValue) {
        patch[key] = newValue;
      }
    }

    return patch;
  }

  /// Check if flight can be edited (not accepted)
  bool canEdit() {
    return status == 'pending';
  }

  /// Check if flight can be deleted
  bool canDelete() {
    return status == 'pending';
  }

  static String _parseDate(dynamic raw) {
    if (raw == null) return DateTime.now().toIso8601String();
    if (raw is Timestamp) return raw.toDate().toIso8601String();
    if (raw is DateTime) return raw.toIso8601String();
    if (raw is String) return raw;
    return DateTime.now().toIso8601String();
  }

  static double _parseDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
