// File: lib/config/flight_constants.dart

/// Flight safety constants for the FlightDeck app
///
/// These values define the limits and thresholds for flight safety monitoring.
/// Adjust these values based on local regulations and requirements.
class FlightConstants {
  // Prevent instantiation
  FlightConstants._();

  // ============================================
  // ALTITUDE LIMITS
  // ============================================

  /// Maximum allowed altitude in meters AGL (Above Ground Level)
  /// Swiss regulations typically allow paragliding up to FL100 (3050m)
  /// but practical limit is often lower due to airspace
  static const double maxAltitudeMeters = 4000.0;

  // ============================================
  // ALERT SETTINGS
  // ============================================

  /// Minimum time between same type of alert (prevents spam)
  /// Don't create the same alert twice within this duration
  static const Duration alertCooldownDuration = Duration(minutes: 5);

  /// How often to check for safety violations (in position updates)
  static const Duration alertCheckInterval = Duration(seconds: 1);

  // ============================================
  // AIRSPACE SETTINGS
  // ============================================

  /// Radius in km to check for nearby airspace zones (for warnings)
  static const double airspaceWarningRadiusKm = 5.0;

  // ============================================
  // LIVE TRACKING SETTINGS
  // ============================================

  /// Minimum interval between live tracking uploads
  static const Duration minUploadInterval = Duration(seconds: 12);

  /// Minimum distance moved before uploading new position (meters)
  static const double minDistanceMeters = 50.0;

  // ============================================
  // FLIGHT DETECTION SETTINGS
  // ============================================

  /// Minimum altitude gain to consider as takeoff (meters)
  static const double takeoffAltitudeThresholdMeters = 20.0;

  /// Minimum speed to consider as in-flight (m/s)
  static const double minFlightSpeedMs = 2.0;

  /// Duration to wait before auto-closing a flight (no position updates)
  static const Duration autoCloseFlightTimeout = Duration(minutes: 5);

  // ============================================
  // UI SETTINGS
  // ============================================

  /// Duration to show critical alerts on screen (seconds)
  static const int criticalAlertDisplaySeconds = 10;

  /// Duration to show normal alerts on screen (seconds)
  static const int normalAlertDisplaySeconds = 5;
}
