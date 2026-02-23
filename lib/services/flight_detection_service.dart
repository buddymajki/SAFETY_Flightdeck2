// File: lib/services/flight_detection_service.dart
//
// FLIGHT DETECTION ALGORITHM
// ==========================
// This service implements variometer-style takeoff and landing detection.
// It uses GPS data (position, altitude, speed) and optionally IMU sensors
// (accelerometer, gyroscope) for enhanced accuracy.
//
// TUNING PARAMETERS are documented below and can be adjusted based on:
// - Aircraft type (paraglider, hang glider, sailplane)
// - Local conditions (thermic vs coastal)
// - User preferences
//
// The algorithm follows these principles from variometer manufacturers:
// 1. Takeoff requires SUSTAINED conditions (not just instantaneous)
// 2. Both altitude change AND movement must be detected
// 3. Landing requires PROLONGED stationary conditions
// 4. IMU data helps filter GPS noise and false positives

import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:math';

import '../models/tracked_flight.dart';

/// Service for detecting takeoff and landing based on sensor and GPS data
/// Implements algorithms inspired by variometer manufacturers (Skytraxx, XCTracer, Flytec)
class FlightDetectionService {
  // ============================================
  // TAKEOFF DETECTION THRESHOLDS
  // ============================================
  // TUNING: Adjust these for different aircraft types
  // Paragliders: use lower speeds, moderate altitude gain
  // Hang gliders: slightly higher speeds
  // Sailplanes: much higher speeds, winch/tow considerations
  // ============================================

  /// Minimum vertical speed to START considering takeoff (m/s)
  /// TUNING: 0.3 m/s = 1.08 km/h vertical - catches slow thermal climbs
  /// Typical paraglider sink rate is -1.0 to -1.5 m/s, climb +1 to +4 m/s
  /// Minimum vertical speed (absolute) to START considering takeoff (m/s)
  /// TUNING: 0.4 m/s catches both gentle thermal lift-offs and sled rides
  /// Paragliders: sink rate -1.0 to -1.5 m/s, climb +1 to +4 m/s
  /// Cable cars: vertical speed is typically < 3 m/s but SUSTAINED with no horizontal accel burst
  static const double takeoffVerticalSpeedThreshold = 0.4;

  /// Minimum horizontal speed for takeoff detection (m/s)
  /// TUNING: 3.5 m/s = 12.6 km/h - filters out walking (5 km/h) and jogging (10 km/h)
  /// Paraglider launch run: 10-20 km/h, in-flight: 25-50 km/h
  /// In strong headwind, ground speed can be as low as ~12-15 km/h right after launch
  /// Cable cars: typically 5-12 m/s (18-43 km/h) but move on a FIXED bearing with no
  ///   sudden stop-to-run acceleration pattern, so the IMU + pre-movement check filters them
  static const double takeoffHorizontalSpeedThreshold = 3.5;

  /// Minimum altitude CHANGE (up OR down) required to confirm takeoff (m)
  /// TUNING: 3m is above GPS altitude noise (±1-2m when stationary) while
  ///   catching real flight early. Slope launches descend 5-20m in the first seconds.
  static const double minAltitudeChangeForTakeoff = 3.0;

  /// Minimum duration of takeoff conditions before confirming (seconds)
  /// TUNING: 3 seconds filters brief GPS glitches / car speed bumps while
  ///   catching takeoffs ~2s earlier than before. Industry variometers (Skytraxx,
  ///   XCTracer) typically confirm within 2-4s.
  static const int takeoffConfirmationSeconds = 3;

  /// Maximum ground speed that's considered "on ground" for takeoff reference (m/s)
  /// TUNING: 1.5 m/s = 5.4 km/h - about fast walking speed
  /// Used to establish ground altitude reference before takeoff
  static const double groundSpeedThreshold = 1.5;

  /// Minimum acceleration spike (m/s²) from the IMU that helps confirm a launch run.
  /// TUNING: During the takeoff run the pilot accelerates hard from standstill;
  ///   a 1.2 m/s² sustained excess over gravity is enough to distinguish a run
  ///   from calm standing but not triggered by walking (~0.4 m/s² excess).
  static const double launchAccelerationThreshold = 1.2;

  // ============================================
  // LANDING DETECTION THRESHOLDS
  // ============================================
  // TUNING: Landing detection is conservative to avoid false landings
  // during low-altitude scratching or slow glides
  // ============================================

  /// Maximum horizontal speed for landing detection (m/s)
  /// TUNING: 2.0 m/s = 7.2 km/h - slower than walking pace
  /// Paragliders on final approach: 25-35 km/h, flare to ~10-15 km/h
  /// Post-landing: 0-5 km/h (gathering wing)
  static const double landingSpeedThreshold = 2.0;

  /// Maximum absolute vertical speed for landing detection (m/s)
  /// TUNING: 0.5 m/s filters out active flying (sink rate typically 1-2 m/s)
  /// On ground: ±0.3 m/s from GPS noise
  static const double landingVerticalThreshold = 0.5;

  /// Minimum time at low speed/vertical to confirm landing (seconds)
  /// TUNING: 10 seconds prevents false landings during slow scratching
  /// Real landing: pilot is on ground gathering wing for 30+ seconds
  static const int landingConfirmationSeconds = 10;

  // ============================================
  // MOVING AVERAGE & FILTERING
  // ============================================

  /// Window size for moving average calculations (number of GPS points)
  /// TUNING: 5 points at 1Hz = 5 second window for smoothing
  /// Larger windows = more stable but slower response
  static const int movingAverageWindowSize = 5;

  /// Minimum track points needed before detection can occur
  /// TUNING: Need enough history to calculate reliable averages
  static const int minTrackPointsForDetection = 3;

  // ============================================
  // IMU (ACCELEROMETER/GYROSCOPE) THRESHOLDS
  // ============================================
  // TUNING: IMU data helps distinguish flight from ground movement
  // In flight: smooth accelerations, gradual attitude changes
  // On ground: vibrations, sudden stops, irregular movements
  // ============================================

  /// Accelerometer threshold for detecting "smooth flight" conditions (m/s²)
  /// TUNING: Gravity is ~9.8 m/s². In smooth flight, total accel ≈ 9.8 ± 2
  /// Ground handling: jerky movements, spikes > 15 m/s²
  /// This measures deviation from gravity: sqrt(ax²+ay²+az²) - 9.8
  static const double accelerometerFlightThreshold = 3.0;

  /// Gyroscope threshold for flight rotation detection (rad/s)
  /// TUNING: In flight, turns are smooth (< 0.5 rad/s = 30°/s)
  /// Ground handling: rapid movements, spikes > 1.0 rad/s
  static const double gyroscopeFlightThreshold = 1.0;

  /// Accelerometer threshold indicating ground vibrations/handling (m/s²)
  /// TUNING: Walking/ground: high-frequency vibrations, total accel variance high
  static const double accelerometerGroundThreshold = 2.0;

  // ============================================
  // INTERNAL STATE
  // ============================================

  final Queue<TrackPoint> _recentTrackPoints = Queue();
  final Queue<SensorData> _recentSensorData = Queue();
  double? _groundAltitude;
  DateTime? _lowSpeedStartTime;
  bool _isInFlight = false;
  
  // Takeoff confirmation state
  DateTime? _takeoffConditionsStartTime;
  double? _takeoffConditionsStartAltitude;

  // --- Pre-takeoff ground position (industry-standard: remember the last
  //     stationary coordinate so we can use it as the true takeoff point) ---
  TrackPoint? _lastStationaryPoint;

  /// Reset the detection state
  void reset() {
    _recentTrackPoints.clear();
    _recentSensorData.clear();
    _groundAltitude = null;
    _lowSpeedStartTime = null;
    _isInFlight = false;
    _takeoffConditionsStartTime = null;
    _takeoffConditionsStartAltitude = null;
    _lastStationaryPoint = null;
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

    // Need minimum points before detection
    if (_recentTrackPoints.length < minTrackPointsForDetection) {
      return null;
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

  /// Check for takeoff conditions using variometer-style detection
  /// 
  /// Takeoff is confirmed when ALL of these conditions are met for [takeoffConfirmationSeconds]:
  /// 1. Horizontal speed > [takeoffHorizontalSpeedThreshold] (18 km/h)
  /// 2. Either: |vertical speed| > threshold OR |altitude change| > threshold
  ///    This handles BOTH climbing (thermal) AND descending (sled ride) flights
  /// 3. IMU data (if available) indicates smooth flight, not ground handling
  /// 
  /// The key insight: paragliders ALWAYS move forward at 20-50 km/h airspeed.
  /// Even with strong headwind, ground speed should exceed walking speed.
  /// Combined with altitude change (up OR down), this reliably detects takeoff.
  FlightEvent? _checkForTakeoff(TrackPoint currentPoint) {
    if (_recentTrackPoints.length < movingAverageWindowSize) {
      return null;
    }

    // Calculate current speeds
    final horizontalSpeed = _calculateHorizontalSpeed();
    final verticalSpeed = _calculateVerticalSpeed();
    
    // DEBUG: Log detection values
    developer.log('[FlightDetection] h_speed=${horizontalSpeed.toStringAsFixed(1)}m/s (need>$takeoffHorizontalSpeedThreshold), '
          'v_speed=${verticalSpeed.toStringAsFixed(2)}m/s, alt=${currentPoint.altitude.toStringAsFixed(0)}m, '
          'ground=${_groundAltitude?.toStringAsFixed(0) ?? "?"}m', name: 'FlightDetection');

    // Update ground altitude reference AND remember position when stationary.
    // This is the industry-standard technique: the last point where the pilot
    // was still "on the ground" becomes the takeoff coordinate, NOT the point
    // where the algorithm finally fires (which can be 50-100 m into the flight).
    if (horizontalSpeed < groundSpeedThreshold && verticalSpeed.abs() < 0.5) {
      _groundAltitude = currentPoint.altitude;
      _lastStationaryPoint = currentPoint;
    }

    // Use initial altitude as ground reference if not set
    _groundAltitude ??= currentPoint.altitude;

    // Calculate altitude CHANGE from ground (absolute - works for climb OR descent)
    final altitudeChange = (currentPoint.altitude - _groundAltitude!).abs();

    // Check IMU conditions (if sensor data available)
    final imuIndicatesFlight = _checkImuForFlight();
    final imuIndicatesGround = _checkImuForGround();

    // --- IMU-assisted early detection ---
    // If accelerometer shows a sustained acceleration burst (launch run),
    // we can relax the GPS-speed requirement slightly because GPS lags ~1-2s
    // behind real movement.
    final imuShowsLaunchRun = _checkImuForLaunchRun();

    // PRIMARY TAKEOFF CONDITION:
    // 1. Horizontal speed must exceed threshold (paragliders always move forward)
    //    – OR the IMU detects a launch-run acceleration burst AND speed is at
    //      least 2.5 m/s (9 km/h) to avoid false positives while reacting faster
    // 2. PLUS either significant vertical movement OR altitude change
    //    - Vertical speed uses ABSOLUTE value (climb OR descent)
    //    - Altitude change uses ABSOLUTE value (gain OR loss from ground)
    final speedIndicatesTakeoff = horizontalSpeed >= takeoffHorizontalSpeedThreshold ||
        (imuShowsLaunchRun && horizontalSpeed >= 2.5);
    final verticalIndicatesTakeoff = verticalSpeed.abs() > takeoffVerticalSpeedThreshold || 
                                     altitudeChange >= minAltitudeChangeForTakeoff;
    
    // DEBUG: Log condition status
    if (speedIndicatesTakeoff || verticalIndicatesTakeoff) {
      developer.log('[FlightDetection] CONDITIONS: speed=${speedIndicatesTakeoff ? "✓" : "✗"}, '
            'vertical=${verticalIndicatesTakeoff ? "✓" : "✗"} (altChange=${altitudeChange.toStringAsFixed(1)}m), '
            'imuFlight=${imuIndicatesFlight ? "✓" : "-"}, imuGround=${imuIndicatesGround ? "✗" : "-"}', name: 'FlightDetection');
    }

    // If IMU strongly indicates ground (walking, driving), reject takeoff
    if (imuIndicatesGround && !imuIndicatesFlight) {
      _takeoffConditionsStartTime = null;
      _takeoffConditionsStartAltitude = null;
      return null;
    }

    // Check if basic takeoff conditions are met
    final takeoffConditionsMet = speedIndicatesTakeoff && verticalIndicatesTakeoff;

    if (takeoffConditionsMet) {
      // Start tracking takeoff conditions
      if (_takeoffConditionsStartTime == null) {
        _takeoffConditionsStartTime = currentPoint.timestamp;
        _takeoffConditionsStartAltitude = currentPoint.altitude;
        developer.log('[FlightDetection] 🛫 TAKEOFF CONDITIONS STARTED at alt=${currentPoint.altitude.toStringAsFixed(0)}m', name: 'FlightDetection');
      }

      // Check if conditions sustained for required duration
      final conditionsDuration = currentPoint.timestamp
          .difference(_takeoffConditionsStartTime!)
          .inSeconds;

      // Verify altitude CHANGE during the confirmation period (absolute - up or down)
      // This handles both climbing (thermal) and descending (sled ride) flights
      final altitudeChangeDuringConfirmation = 
          (currentPoint.altitude - (_takeoffConditionsStartAltitude ?? currentPoint.altitude)).abs();

      developer.log('[FlightDetection] ⏱️ Confirmation: ${conditionsDuration}s/${takeoffConfirmationSeconds}s needed, '
            'altChange=${altitudeChangeDuringConfirmation.toStringAsFixed(1)}m', name: 'FlightDetection');

      // CONFIRM TAKEOFF: conditions held + meaningful altitude change (up OR down)
      // Use a smaller threshold here since we already had initial conditions met
      if (conditionsDuration >= takeoffConfirmationSeconds && 
          altitudeChangeDuringConfirmation >= minAltitudeChangeForTakeoff / 2) {
        _isInFlight = true;
        _takeoffConditionsStartTime = null;
        _takeoffConditionsStartAltitude = null;
        
        developer.log('[FlightDetection] ✅ TAKEOFF CONFIRMED!', name: 'FlightDetection');

        // --- Industry-standard takeoff coordinate selection ---
        // Priority:
        //   1. Last stationary point (where pilot was standing before the run)
        //   2. Heuristic scan of recent points (_findTakeoffPoint)
        //   3. Current point as last resort
        final takeoffPoint = _lastStationaryPoint ?? _findTakeoffPoint() ?? currentPoint;

        developer.log('[FlightDetection] Takeoff coord source: '
              '${_lastStationaryPoint != null ? "last-stationary" : "heuristic/current"}, '
              'alt=${takeoffPoint.altitude.toStringAsFixed(0)}m', name: 'FlightDetection');

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
    } else {
      // Reset confirmation timer if conditions not met
      _takeoffConditionsStartTime = null;
      _takeoffConditionsStartAltitude = null;
    }

    return null;
  }

  /// Check for landing conditions using variometer-style detection
  /// 
  /// Landing is confirmed when ALL of these conditions are met for [landingConfirmationSeconds]:
  /// 1. Horizontal speed < [landingSpeedThreshold]
  /// 2. Vertical speed magnitude < [landingVerticalThreshold]
  /// 3. IMU data (if available) indicates ground conditions
  FlightEvent? _checkForLanding(TrackPoint currentPoint) {
    if (_recentTrackPoints.length < movingAverageWindowSize) {
      return null;
    }

    final verticalSpeed = _calculateVerticalSpeed();
    final horizontalSpeed = _calculateHorizontalSpeed();

    // Check IMU for additional confidence
    final imuIndicatesGround = _checkImuForGround();

    // Landing conditions: both speeds very low
    final speedsIndicateLanding = 
        horizontalSpeed < landingSpeedThreshold && 
        verticalSpeed.abs() < landingVerticalThreshold;

    if (speedsIndicateLanding) {
      // Start or continue landing confirmation timer
      _lowSpeedStartTime ??= currentPoint.timestamp;

      final lowSpeedDuration =
          currentPoint.timestamp.difference(_lowSpeedStartTime!).inSeconds;

      // Confirm landing after sustained low speed
      // Shorter confirmation if IMU confirms ground conditions
      final requiredDuration = imuIndicatesGround 
          ? landingConfirmationSeconds ~/ 2 
          : landingConfirmationSeconds;

      if (lowSpeedDuration >= requiredDuration) {
        _isInFlight = false;
        _groundAltitude = currentPoint.altitude;
        final landingTime = _lowSpeedStartTime ?? currentPoint.timestamp;
        _lowSpeedStartTime = null;

        return FlightEvent(
          type: FlightEventType.landing,
          timestamp: landingTime,
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

  /// Check if IMU data indicates smooth flight conditions
  bool _checkImuForFlight() {
    if (_recentSensorData.isEmpty) return true; // No data = don't block

    // Get recent sensor readings
    final recentData = _recentSensorData.toList();
    if (recentData.length < 3) return true;

    // Calculate average acceleration deviation from gravity (9.8 m/s²)
    double totalAccelDeviation = 0;
    double totalRotation = 0;
    int count = 0;

    for (final data in recentData.skip(max(0, recentData.length - 5))) {
      if (data.accelerometerX != null) {
        final accelMag = sqrt(data.accelerationMagnitude);
        final deviation = (accelMag - 9.8).abs();
        totalAccelDeviation += deviation;
        count++;
      }
      if (data.gyroscopeX != null) {
        totalRotation += sqrt(data.rotationMagnitude);
      }
    }

    if (count == 0) return true;

    final avgAccelDeviation = totalAccelDeviation / count;
    final avgRotation = totalRotation / count;

    // Flight conditions: smooth accelerations, gentle rotations
    return avgAccelDeviation < accelerometerFlightThreshold && 
           avgRotation < gyroscopeFlightThreshold;
  }

  /// Check if IMU data indicates ground/walking/driving conditions
  bool _checkImuForGround() {
    if (_recentSensorData.isEmpty) return false; // No data = can't confirm ground

    // Get recent sensor readings
    final recentData = _recentSensorData.toList();
    if (recentData.length < 3) return false;

    // Calculate acceleration variance (high variance = ground movement)
    final accels = <double>[];
    for (final data in recentData.skip(max(0, recentData.length - 10))) {
      if (data.accelerometerX != null) {
        accels.add(sqrt(data.accelerationMagnitude));
      }
    }

    if (accels.length < 3) return false;

    // Calculate variance
    final mean = accels.reduce((a, b) => a + b) / accels.length;
    final variance = accels.map((a) => pow(a - mean, 2)).reduce((a, b) => a + b) / accels.length;

    // High variance indicates jerky ground movement (walking, driving on rough road)
    // Low variance indicates smooth flight or stationary
    return variance > accelerometerGroundThreshold;
  }

  /// Check if IMU data indicates a launch-run acceleration pattern.
  ///
  /// During a paraglider launch, the pilot sprints from near-standstill.
  /// This produces a distinct forward-acceleration signature that the
  /// accelerometer picks up ~1-2 seconds before GPS speed reflects it.
  /// Cable cars produce constant velocity (≈ 0 excess accel) so they
  /// won't trigger this.
  bool _checkImuForLaunchRun() {
    if (_recentSensorData.isEmpty) return false;

    final recentData = _recentSensorData.toList();
    // Need at least a few samples (at ~50 Hz we get plenty in 1s)
    if (recentData.length < 3) return false;

    // Check the last ~1s of data (last 5 samples at varying rates)
    int spikeCount = 0;
    int total = 0;
    for (final data in recentData.skip(max(0, recentData.length - 10))) {
      if (data.accelerometerX != null) {
        total++;
        final accelMag = sqrt(data.accelerationMagnitude);
        // Excess acceleration above resting gravity
        final excess = accelMag - 9.8;
        if (excess > launchAccelerationThreshold) {
          spikeCount++;
        }
      }
    }

    if (total < 3) return false;
    // If more than 40% of recent samples show launch-level acceleration
    return spikeCount / total > 0.4;
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

  /// Find the approximate takeoff point by analyzing altitude and speed history
  /// 
  /// For ascending flights (thermals): finds the lowest point before climb
  /// For descending flights (sled rides): finds the point where speed first exceeded threshold
  /// 
  /// The takeoff point is where the pilot left the ground, which is typically:
  /// - The last point with low horizontal speed before sustained fast movement
  /// - OR the point with the most extreme altitude before the change
  TrackPoint? _findTakeoffPoint() {
    if (_recentTrackPoints.length < movingAverageWindowSize) {
      return _recentTrackPoints.firstOrNull;
    }

    final points = _recentTrackPoints.toList();
    
    // Find the first point where horizontal speed consistently exceeded threshold
    // This is likely where the pilot became airborne
    int takeoffIndex = 0;
    int consecutiveFastPoints = 0;
    
    for (int i = 1; i < points.length; i++) {
      final timeDiff = points[i].timestamp.difference(points[i-1].timestamp).inMilliseconds / 1000.0;
      if (timeDiff <= 0) continue;
      
      final distance = _haversineDistance(
        points[i-1].latitude, points[i-1].longitude,
        points[i].latitude, points[i].longitude,
      );
      final speed = distance / timeDiff;
      
      if (speed >= takeoffHorizontalSpeedThreshold) {
        consecutiveFastPoints++;
        if (consecutiveFastPoints >= 3 && takeoffIndex == 0) {
          // Found sustained fast movement - takeoff was just before this
          takeoffIndex = max(0, i - 3);
        }
      } else {
        consecutiveFastPoints = 0;
      }
    }
    
    // If we found a takeoff point based on speed, use it
    if (takeoffIndex > 0) {
      return points[takeoffIndex];
    }
    
    // Fallback: find point closest to ground reference altitude
    if (_groundAltitude != null) {
      double minAltDiff = double.infinity;
      int bestIndex = 0;
      for (int i = 0; i < points.length ~/ 2; i++) {
        final diff = (points[i].altitude - _groundAltitude!).abs();
        if (diff < minAltDiff) {
          minAltDiff = diff;
          bestIndex = i;
        }
      }
      return points[bestIndex];
    }

    return points.first;
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
