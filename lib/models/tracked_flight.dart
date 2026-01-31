// File: lib/models/tracked_flight.dart

/// Model for GPS-tracked flights detected automatically
/// 
/// Each flight is associated with a specific user via [userId] to ensure
/// data isolation when switching accounts on the same device.
class TrackedFlight {
  final String id;
  final String? userId; // User who recorded this flight
  final DateTime takeoffTime;
  final DateTime? landingTime;
  final String? takeoffSiteId;
  final String takeoffSiteName;
  final double takeoffLatitude;
  final double takeoffLongitude;
  final double takeoffAltitude;
  final String? landingSiteId;
  final String? landingSiteName;
  final double? landingLatitude;
  final double? landingLongitude;
  final double? landingAltitude;
  final FlightTrackingStatus status;
  final List<TrackPoint> trackPoints;
  final bool isSyncedToFirebase;
  final DateTime? syncedAt;

  TrackedFlight({
    required this.id,
    this.userId,
    required this.takeoffTime,
    this.landingTime,
    this.takeoffSiteId,
    required this.takeoffSiteName,
    required this.takeoffLatitude,
    required this.takeoffLongitude,
    required this.takeoffAltitude,
    this.landingSiteId,
    this.landingSiteName,
    this.landingLatitude,
    this.landingLongitude,
    this.landingAltitude,
    required this.status,
    this.trackPoints = const [],
    this.isSyncedToFirebase = false,
    this.syncedAt,
  });

  /// Duration of the flight in minutes
  int get flightTimeMinutes {
    if (landingTime == null) {
      return DateTime.now().difference(takeoffTime).inMinutes;
    }
    return landingTime!.difference(takeoffTime).inMinutes;
  }

  /// Altitude difference between takeoff and landing
  double get altitudeDifference {
    if (landingAltitude == null) return 0;
    return takeoffAltitude - landingAltitude!;
  }

  /// Create a copy with updated fields
  TrackedFlight copyWith({
    String? id,
    String? userId,
    DateTime? takeoffTime,
    DateTime? landingTime,
    String? takeoffSiteId,
    String? takeoffSiteName,
    double? takeoffLatitude,
    double? takeoffLongitude,
    double? takeoffAltitude,
    String? landingSiteId,
    String? landingSiteName,
    double? landingLatitude,
    double? landingLongitude,
    double? landingAltitude,
    FlightTrackingStatus? status,
    List<TrackPoint>? trackPoints,
    bool? isSyncedToFirebase,
    DateTime? syncedAt,
  }) {
    return TrackedFlight(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      takeoffTime: takeoffTime ?? this.takeoffTime,
      landingTime: landingTime ?? this.landingTime,
      takeoffSiteId: takeoffSiteId ?? this.takeoffSiteId,
      takeoffSiteName: takeoffSiteName ?? this.takeoffSiteName,
      takeoffLatitude: takeoffLatitude ?? this.takeoffLatitude,
      takeoffLongitude: takeoffLongitude ?? this.takeoffLongitude,
      takeoffAltitude: takeoffAltitude ?? this.takeoffAltitude,
      landingSiteId: landingSiteId ?? this.landingSiteId,
      landingSiteName: landingSiteName ?? this.landingSiteName,
      landingLatitude: landingLatitude ?? this.landingLatitude,
      landingLongitude: landingLongitude ?? this.landingLongitude,
      landingAltitude: landingAltitude ?? this.landingAltitude,
      status: status ?? this.status,
      trackPoints: trackPoints ?? this.trackPoints,
      isSyncedToFirebase: isSyncedToFirebase ?? this.isSyncedToFirebase,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  /// Convert to JSON for caching
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'takeoffTime': takeoffTime.toIso8601String(),
      'landingTime': landingTime?.toIso8601String(),
      'takeoffSiteId': takeoffSiteId,
      'takeoffSiteName': takeoffSiteName,
      'takeoffLatitude': takeoffLatitude,
      'takeoffLongitude': takeoffLongitude,
      'takeoffAltitude': takeoffAltitude,
      'landingSiteId': landingSiteId,
      'landingSiteName': landingSiteName,
      'landingLatitude': landingLatitude,
      'landingLongitude': landingLongitude,
      'landingAltitude': landingAltitude,
      'status': status.name,
      'trackPoints': trackPoints.map((p) => p.toJson()).toList(),
      'isSyncedToFirebase': isSyncedToFirebase,
      'syncedAt': syncedAt?.toIso8601String(),
    };
  }

  /// Create from JSON cache
  factory TrackedFlight.fromJson(Map<String, dynamic> json) {
    return TrackedFlight(
      id: json['id'] as String,
      userId: json['userId'] as String?,
      takeoffTime: DateTime.parse(json['takeoffTime'] as String),
      landingTime: json['landingTime'] != null
          ? DateTime.parse(json['landingTime'] as String)
          : null,
      takeoffSiteId: json['takeoffSiteId'] as String?,
      takeoffSiteName: json['takeoffSiteName'] as String,
      takeoffLatitude: (json['takeoffLatitude'] as num).toDouble(),
      takeoffLongitude: (json['takeoffLongitude'] as num).toDouble(),
      takeoffAltitude: (json['takeoffAltitude'] as num).toDouble(),
      landingSiteId: json['landingSiteId'] as String?,
      landingSiteName: json['landingSiteName'] as String?,
      landingLatitude: json['landingLatitude'] != null
          ? (json['landingLatitude'] as num).toDouble()
          : null,
      landingLongitude: json['landingLongitude'] != null
          ? (json['landingLongitude'] as num).toDouble()
          : null,
      landingAltitude: json['landingAltitude'] != null
          ? (json['landingAltitude'] as num).toDouble()
          : null,
      status: FlightTrackingStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => FlightTrackingStatus.completed,
      ),
      trackPoints: (json['trackPoints'] as List<dynamic>?)
              ?.map((p) => TrackPoint.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      isSyncedToFirebase: json['isSyncedToFirebase'] as bool? ?? false,
      syncedAt: json['syncedAt'] != null
          ? DateTime.parse(json['syncedAt'] as String)
          : null,
    );
  }
}

/// Status of a tracked flight
enum FlightTrackingStatus {
  inFlight,
  completed,
  cancelled,
}

/// A single GPS track point during a flight
class TrackPoint {
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double altitude;
  final double? speed; // m/s
  final double? verticalSpeed; // m/s
  final double? heading; // degrees

  TrackPoint({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    this.speed,
    this.verticalSpeed,
    this.heading,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'speed': speed,
      'verticalSpeed': verticalSpeed,
      'heading': heading,
    };
  }

  factory TrackPoint.fromJson(Map<String, dynamic> json) {
    return TrackPoint(
      timestamp: DateTime.parse(json['timestamp'] as String),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      altitude: (json['altitude'] as num).toDouble(),
      speed: json['speed'] != null ? (json['speed'] as num).toDouble() : null,
      verticalSpeed: json['verticalSpeed'] != null
          ? (json['verticalSpeed'] as num).toDouble()
          : null,
      heading:
          json['heading'] != null ? (json['heading'] as num).toDouble() : null,
    );
  }
}

/// Sensor data for flight detection
class SensorData {
  final DateTime timestamp;
  final double? accelerometerX;
  final double? accelerometerY;
  final double? accelerometerZ;
  final double? gyroscopeX;
  final double? gyroscopeY;
  final double? gyroscopeZ;

  SensorData({
    required this.timestamp,
    this.accelerometerX,
    this.accelerometerY,
    this.accelerometerZ,
    this.gyroscopeX,
    this.gyroscopeY,
    this.gyroscopeZ,
  });

  /// Calculate total acceleration magnitude
  double get accelerationMagnitude {
    final x = accelerometerX ?? 0;
    final y = accelerometerY ?? 0;
    final z = accelerometerZ ?? 0;
    return (x * x + y * y + z * z);
  }

  /// Calculate gyroscope rotation magnitude
  double get rotationMagnitude {
    final x = gyroscopeX ?? 0;
    final y = gyroscopeY ?? 0;
    final z = gyroscopeZ ?? 0;
    return (x * x + y * y + z * z);
  }
}
