// File: lib/services/flight_detection_service.dart

import 'dart:collection';
import 'dart:math';

import '../models/tracked_flight.dart';

/// Service for detecting takeoff and landing based on sensor and GPS data
/// Implements algorithms inspired by OpenVario and XCTrack
class FlightDetectionService {
  // ============================================
  // DETECTION THRESHOLDS (Configurable)
  // ============================================

  /// Minimum vertical speed for takeoff detection (m/s)
  static const double takeoffVerticalSpeedThreshold = 0.5;

  /// Minimum horizontal speed for takeoff detection (m/s)
  static const double takeoffHorizontalSpeedThreshold = 2.0;

  /// Maximum horizontal speed for landing detection (m/s)
  static const double landingSpeedThreshold = 1.0;

  /// Maximum vertical speed for landing (descent) detection (m/s)
  static const double landingDescentThreshold = 2.0;

  /// Minimum time at low speed to confirm landing (seconds)
  static const int landingConfirmationSeconds = 5;

  /// Window size for moving average calculations
  static const int movingAverageWindowSize = 5;

  /// Minimum altitude gain to confirm takeoff (m)
  static const double minAltitudeGainForTakeoff = 2.0;

  /// Accelerometer threshold for movement detection (m/s²)
  static const double accelerometerMovementThreshold = 1.5;

  /// Gyroscope threshold for rotation detection (rad/s)
  static const double gyroscopeRotationThreshold = 0.5;

  // ============================================
  // INTERNAL STATE
  // ============================================

  final Queue<TrackPoint> _recentTrackPoints = Queue();
  final Queue<SensorData> _recentSensorData = Queue();
  DateTime? _potentialTakeoffTime;
  double? _groundAltitude;
  DateTime? _lowSpeedStartTime;
  bool _isInFlight = false;

  /// Reset the detection state
  void reset() {
    _recentTrackPoints.clear();
    _recentSensorData.clear();
    _potentialTakeoffTime = null;
    _groundAltitude = null;
    _lowSpeedStartTime = null;
    _isInFlight = false;
  }

  /// Get current flight status
  bool get isInFlight => _isInFlight;

  /// Add a track point and check for flight events
  FlightEvent? processTrackPoint(TrackPoint point) {
    _recentTrackPoints.add(point);

    // Keep only recent points for analysis
    while (_recentTrackPoints.length > movingAverageWindowSize * 3) {
      _recentTrackPoints.removeFirst();
    }

    if (!_isInFlight) {
      return _checkForTakeoff(point);
    } else {
      return _checkForLanding(point);
    }
  }

  /// Add sensor data for enhanced detection
  void processSensorData(SensorData data) {
    _recentSensorData.add(data);

    // Keep only recent sensor data
    while (_recentSensorData.length > movingAverageWindowSize * 3) {
      _recentSensorData.removeFirst();
    }
  }

  /// Check for takeoff conditions
  FlightEvent? _checkForTakeoff(TrackPoint currentPoint) {
    if (_recentTrackPoints.length < movingAverageWindowSize) {
      return null;
    }

    // Calculate current speeds
    final horizontalSpeed = _calculateHorizontalSpeed();

    // Check if horizontal speed exceeds takeoff threshold (only check horizontal speed)
    final speedIndicatesTakeoff = horizontalSpeed >= takeoffHorizontalSpeedThreshold;

    // Determine ground altitude if not set
    _groundAltitude ??= currentPoint.altitude;

    // Takeoff detected when horizontal speed threshold is met
    if (speedIndicatesTakeoff) {
      _isInFlight = true;
      _potentialTakeoffTime = null;

      // Find the actual takeoff point
      final takeoffPoint = _findTakeoffPoint() ?? currentPoint;
      final verticalSpeed = _calculateVerticalSpeed();

      return FlightEvent(
        type: FlightEventType.takeoff,
        timestamp: takeoffPoint.timestamp,
        latitude: takeoffPoint.latitude,
        longitude: takeoffPoint.longitude,
        altitude: takeoffPoint.altitude,
        speed: horizontalSpeed,
        verticalSpeed: verticalSpeed,
      );
    }

    // Mark potential takeoff time for later reference
    if (speedIndicatesTakeoff && _potentialTakeoffTime == null) {
      _potentialTakeoffTime = currentPoint.timestamp;
    }

    return null;
  }

  /// Check for landing conditions
  FlightEvent? _checkForLanding(TrackPoint currentPoint) {
    if (_recentTrackPoints.length < movingAverageWindowSize) {
      return null;
    }

    final verticalSpeed = _calculateVerticalSpeed();
    final horizontalSpeed = _calculateHorizontalSpeed();

    // Landing detection: low horizontal speed AND moderate descent or very low vertical speed
    // More lenient: allow for slow gliding descent with some forward speed
    final speedsIndicateLanding = 
        horizontalSpeed < landingSpeedThreshold && 
        verticalSpeed.abs() < landingDescentThreshold;

    if (speedsIndicateLanding) {
      // Start or continue landing confirmation timer
      _lowSpeedStartTime ??= currentPoint.timestamp;

      final lowSpeedDuration =
          currentPoint.timestamp.difference(_lowSpeedStartTime!).inSeconds;

      // Confirm landing after sustained low speed
      if (lowSpeedDuration >= landingConfirmationSeconds) {
        _isInFlight = false;
        _groundAltitude = currentPoint.altitude;
        _lowSpeedStartTime = null;

        return FlightEvent(
          type: FlightEventType.landing,
          timestamp: _lowSpeedStartTime ?? currentPoint.timestamp,
          latitude: currentPoint.latitude,
          longitude: currentPoint.longitude,
          altitude: currentPoint.altitude,
          speed: horizontalSpeed,
          verticalSpeed: verticalSpeed,
        );
      }
    } else {
      // Reset landing confirmation if speeds increase
      _lowSpeedStartTime = null;
    }

    return null;
  }

  /// Calculate vertical speed from recent track points (m/s)
  double _calculateVerticalSpeed() {
    if (_recentTrackPoints.length < 2) return 0;

    final points = _recentTrackPoints.toList();
    final recentPoints = points.sublist(
      max(0, points.length - movingAverageWindowSize),
    );

    if (recentPoints.length < 2) return 0;

    // Use linear regression for smoother vertical speed
    double sumTime = 0;
    double sumAlt = 0;
    double sumTimeAlt = 0;
    double sumTimeSq = 0;

    final baseTime = recentPoints.first.timestamp;

    for (int i = 0; i < recentPoints.length; i++) {
      final t = recentPoints[i].timestamp.difference(baseTime).inMilliseconds / 1000.0;
      final alt = recentPoints[i].altitude;

      sumTime += t;
      sumAlt += alt;
      sumTimeAlt += t * alt;
      sumTimeSq += t * t;
    }

    final n = recentPoints.length;
    final denominator = n * sumTimeSq - sumTime * sumTime;

    if (denominator.abs() < 0.0001) return 0;

    return (n * sumTimeAlt - sumTime * sumAlt) / denominator;
  }

  /// Calculate horizontal speed from recent track points (m/s)
  double _calculateHorizontalSpeed() {
    if (_recentTrackPoints.length < 2) return 0;

    final points = _recentTrackPoints.toList();
    final recentPoints = points.sublist(
      max(0, points.length - movingAverageWindowSize),
    );

    if (recentPoints.length < 2) return 0;

    double totalDistance = 0;
    Duration totalTime = Duration.zero;

    for (int i = 1; i < recentPoints.length; i++) {
      final prev = recentPoints[i - 1];
      final curr = recentPoints[i];

      totalDistance += _haversineDistance(
        prev.latitude,
        prev.longitude,
        curr.latitude,
        curr.longitude,
      );

      totalTime += curr.timestamp.difference(prev.timestamp);
    }

    if (totalTime.inMilliseconds == 0) return 0;

    return totalDistance / (totalTime.inMilliseconds / 1000.0);
  }

  /// Haversine distance calculation (meters)
  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;

    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * pi / 180;

  /// Check sensor data for takeoff indicators
  /// Find the approximate takeoff point by analyzing altitude history
  TrackPoint? _findTakeoffPoint() {
    if (_recentTrackPoints.length < movingAverageWindowSize) {
      return _recentTrackPoints.firstOrNull;
    }

    final points = _recentTrackPoints.toList();
    double minAltitude = double.infinity;
    int minIndex = 0;

    // Find the lowest point in recent history (likely ground level)
    for (int i = 0; i < points.length - movingAverageWindowSize; i++) {
      if (points[i].altitude < minAltitude) {
        minAltitude = points[i].altitude;
        minIndex = i;
      }
    }

    return points[minIndex];
  }

  /// Analyze historical tracklog for flight detection (for testing)
  List<FlightEvent> analyzeTracklog(List<TrackPoint> tracklog) {
    reset();
    final events = <FlightEvent>[];

    for (final point in tracklog) {
      final event = processTrackPoint(point);
      if (event != null) {
        events.add(event);
      }
    }

    return events;
  }

  /// Calculate statistics for a track segment
  TrackStatistics calculateStatistics(List<TrackPoint> points) {
    if (points.isEmpty) {
      return TrackStatistics.empty();
    }

    double minAlt = double.infinity;
    double maxAlt = double.negativeInfinity;
    double totalDistance = 0;
    double maxSpeed = 0;

    for (int i = 0; i < points.length; i++) {
      final point = points[i];

      if (point.altitude < minAlt) minAlt = point.altitude;
      if (point.altitude > maxAlt) maxAlt = point.altitude;

      if (i > 0) {
        totalDistance += _haversineDistance(
          points[i - 1].latitude,
          points[i - 1].longitude,
          point.latitude,
          point.longitude,
        );
      }

      if (point.speed != null && point.speed! > maxSpeed) {
        maxSpeed = point.speed!;
      }
    }

    final duration = points.last.timestamp.difference(points.first.timestamp);

    return TrackStatistics(
      minAltitude: minAlt == double.infinity ? 0 : minAlt,
      maxAltitude: maxAlt == double.negativeInfinity ? 0 : maxAlt,
      totalDistance: totalDistance,
      maxSpeed: maxSpeed,
      duration: duration,
    );
  }
}

/// Types of flight events
enum FlightEventType {
  takeoff,
  landing,
}

/// A flight event (takeoff or landing)
class FlightEvent {
  final FlightEventType type;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double altitude;
  final double speed;
  final double verticalSpeed;

  FlightEvent({
    required this.type,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.speed,
    required this.verticalSpeed,
  });

  @override
  String toString() {
    return 'FlightEvent($type at $timestamp, alt: ${altitude.toStringAsFixed(0)}m)';
  }
}

/// Statistics for a track segment
class TrackStatistics {
  final double minAltitude;
  final double maxAltitude;
  final double totalDistance;
  final double maxSpeed;
  final Duration duration;

  TrackStatistics({
    required this.minAltitude,
    required this.maxAltitude,
    required this.totalDistance,
    required this.maxSpeed,
    required this.duration,
  });

  factory TrackStatistics.empty() {
    return TrackStatistics(
      minAltitude: 0,
      maxAltitude: 0,
      totalDistance: 0,
      maxSpeed: 0,
      duration: Duration.zero,
    );
  }

  double get altitudeGain => maxAltitude - minAltitude;

  double get averageSpeed {
    if (duration.inSeconds == 0) return 0;
    return totalDistance / duration.inSeconds;
  }
}
