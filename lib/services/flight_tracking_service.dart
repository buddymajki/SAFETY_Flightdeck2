// File: lib/services/flight_tracking_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tracked_flight.dart';
import 'flight_detection_service.dart';
import 'live_tracking_service.dart';
import 'location_service.dart';
import 'tracklog_parser_service.dart';

/// Main service for flight tracking functionality
/// Manages GPS tracking, flight detection, and local caching
class FlightTrackingService extends ChangeNotifier {
  static const String _trackedFlightsCacheKey = 'gps_tracked_flights';
  static const String _currentFlightCacheKey = 'gps_current_flight';
  static const String _trackingEnabledKey = 'gps_tracking_enabled';

  // Services
  final FlightDetectionService _detectionService = FlightDetectionService();
  
  // Live tracking service for authorities (optional, can be null if not injected)
  LiveTrackingService? _liveTrackingService;

  // State
  bool _isTrackingEnabled = false;
  bool _isInitialized = false;
  TrackedFlight? _currentFlight;
  List<TrackedFlight> _trackedFlights = [];
  List<Map<String, dynamic>> _cachedSites = [];
  String _currentLanguage = 'en';

  // GPS simulation/testing state
  bool _isSimulating = false;
  List<TrackPoint>? _simulationTracklog;
  int _simulationIndex = 0;
  Timer? _simulationTimer;

  // Current position state
  TrackPoint? _lastPosition;
  Timer? _autoCloseFlightTimer;
  String _currentStatus = 'Idle';
  String? _nearestTakeoffSiteName;
  double? _nearestTakeoffSiteDistance;
  String? _nearestLandingSiteName;
  double? _nearestLandingSiteDistance;
  FlightEvent? _lastFlightEvent;

  // ============================================
  // AUTO-CLOSE SETTINGS (For Testing/Simulation)
  // ============================================
  /// Auto-close flight if no position update for this duration
  /// NOTE: In production/real-world flying, this should be MUCH longer (5-10 minutes)
  /// This is set to 10 seconds for testing tracklog files that may end abruptly
  /// static const Duration autoCloseFlightTimeout = Duration(minutes: 5); // or longer
  static const Duration autoCloseFlightTimeout = Duration(seconds: 10);

  // Callbacks for UI updates
  Function(TrackPoint)? onPositionUpdate;
  Function(TrackedFlight)? onFlightStarted;
  Function(TrackedFlight)? onFlightEnded;
  Function(String)? onStatusChanged;

  // Getters
  bool get isTrackingEnabled => _isTrackingEnabled;
  bool get isInitialized => _isInitialized;
  bool get isInFlight => _currentFlight != null;
  bool get isSimulating => _isSimulating;
  TrackedFlight? get currentFlight => _currentFlight;
  List<TrackedFlight> get trackedFlights => List.unmodifiable(_trackedFlights);
  TrackPoint? get lastPosition => _lastPosition;
  String get currentStatus => _currentStatus;
  String? get nearestTakeoffSiteName => _nearestTakeoffSiteName;
  double? get nearestTakeoffSiteDistance => _nearestTakeoffSiteDistance;
  String? get nearestLandingSiteName => _nearestLandingSiteName;
  double? get nearestLandingSiteDistance => _nearestLandingSiteDistance;
  // Backward compatibility
  String? get nearestSiteName => _nearestTakeoffSiteName;
  double? get nearestSiteDistance => _nearestTakeoffSiteDistance;
  FlightEvent? get lastFlightEvent => _lastFlightEvent;
  
  // Live tracking getters
  LiveTrackingService? get liveTrackingService => _liveTrackingService;
  bool get isLiveTrackingEnabled => _liveTrackingService?.isEnabled ?? false;
  bool get isLiveTrackingActive => _liveTrackingService?.isActive ?? false;

  FlightTrackingService() {
    _loadFromCache();
  }

  /// Initialize the service with site data from GlobalDataService
  Future<void> initialize(List<Map<String, dynamic>> sites, {String lang = 'en'}) async {
    _cachedSites = sites;
    _currentLanguage = lang;
    _isInitialized = true;
    notifyListeners();
    log('[FlightTrackingService] Initialized with ${sites.length} sites');
  }
  
  /// Set the live tracking service for authorities
  /// Call this after creating both services in your app initialization
  void setLiveTrackingService(LiveTrackingService service) {
    _liveTrackingService = service;
    log('[FlightTrackingService] Live tracking service connected');
  }

  /// Update cached sites (when GlobalDataService updates)
  void updateSites(List<Map<String, dynamic>> sites) {
    _cachedSites = sites;
    notifyListeners();
  }

  /// Set current language for site names
  void setLanguage(String lang) {
    _currentLanguage = lang;
    notifyListeners();
  }

  // ============================================
  // TRACKING CONTROL
  // ============================================

  /// Enable GPS tracking
  Future<void> enableTracking() async {
    if (_isTrackingEnabled) return;

    _isTrackingEnabled = true;
    _updateStatus('Tracking Active');;

    // Reset detection service to prepare for new flight
    _detectionService.reset();

    await _saveTrackingState();
    notifyListeners();

    log('[FlightTrackingService] Tracking enabled');
  }

  /// Disable GPS tracking
  Future<void> disableTracking() async {
    if (!_isTrackingEnabled) return;

    _isTrackingEnabled = false;
    _updateStatus('Tracking Disabled');

    // Reset detection service when disabling tracking
    _detectionService.reset();

    // Stop any ongoing simulation
    stopSimulation();

    await _saveTrackingState();
    notifyListeners();

    log('[FlightTrackingService] Tracking disabled');
  }

  /// Toggle tracking state
  Future<void> toggleTracking() async {
    if (_isTrackingEnabled) {
      await disableTracking();
    } else {
      await enableTracking();
    }
  }

  // ============================================
  // GPS DATA PROCESSING
  // ============================================

  /// Process incoming GPS position
  /// Call this from location updates (real GPS or simulation)
  Future<void> processPosition({
    required double latitude,
    required double longitude,
    required double altitude,
    double? speed,
    double? heading,
    DateTime? timestamp,
  }) async {
    if (!_isTrackingEnabled) return;

    final now = timestamp ?? DateTime.now();

    // Calculate vertical speed from previous position
    double? verticalSpeed;
    if (_lastPosition != null) {
      final timeDiff = now.difference(_lastPosition!.timestamp).inMilliseconds / 1000.0;
      if (timeDiff > 0) {
        verticalSpeed = (altitude - _lastPosition!.altitude) / timeDiff;
      }
    }

    final trackPoint = TrackPoint(
      timestamp: now,
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      speed: speed,
      verticalSpeed: verticalSpeed,
      heading: heading,
    );

    _lastPosition = trackPoint;

    // Reset auto-close timer when position updates are received
    _resetAutoCloseTimer();

    // Check for nearby sites
    _updateNearbySite(latitude, longitude, altitude);

    // Process through flight detection
    final event = _detectionService.processTrackPoint(trackPoint);
    print('🔍 [FlightTracking] Detection result: ${event?.type ?? "null (no event)"}');

    if (event != null) {
      print('🔍 [FlightTracking] Event detected! Type: ${event.type}');
      await _handleFlightEvent(event, trackPoint);
    }

    // If in flight, add track point to current flight
    if (_currentFlight != null) {
      _currentFlight = _currentFlight!.copyWith(
        trackPoints: [..._currentFlight!.trackPoints, trackPoint],
      );
      await _saveCurrentFlight();
      
      // Send position to live tracking service
      print('🌐 [FlightTracking] In flight, sending position to LiveTrackingService');
      print('🌐 [FlightTracking] LiveTrackingService is ${_liveTrackingService == null ? "NULL" : "connected"}');
      await _liveTrackingService?.processPosition(trackPoint);
    } else {
      print('⚪ [FlightTracking] Not in flight, skipping live tracking');
    }

    // Notify listeners
    onPositionUpdate?.call(trackPoint);
    notifyListeners();
  }

  /// Process sensor data for enhanced detection
  void processSensorData({
    double? accelerometerX,
    double? accelerometerY,
    double? accelerometerZ,
    double? gyroscopeX,
    double? gyroscopeY,
    double? gyroscopeZ,
  }) {
    if (!_isTrackingEnabled) return;

    final sensorData = SensorData(
      timestamp: DateTime.now(),
      accelerometerX: accelerometerX,
      accelerometerY: accelerometerY,
      accelerometerZ: accelerometerZ,
      gyroscopeX: gyroscopeX,
      gyroscopeY: gyroscopeY,
      gyroscopeZ: gyroscopeZ,
    );

    _detectionService.processSensorData(sensorData);
  }

  /// Handle flight events (takeoff/landing)
  Future<void> _handleFlightEvent(FlightEvent event, TrackPoint position) async {
    print('🎯 [FlightTracking] _handleFlightEvent called: ${event.type}');
    print('🎯 [FlightTracking] Event details: lat=${event.latitude}, lon=${event.longitude}, alt=${event.altitude}');
    
    _lastFlightEvent = event;
    Future.microtask(() => notifyListeners());
    
    switch (event.type) {
      case FlightEventType.takeoff:
        print('🎯 [FlightTracking] Calling _handleTakeoff...');
        await _handleTakeoff(event, position);
        break;
      case FlightEventType.landing:
        print('🎯 [FlightTracking] Calling _handleLanding...');
        await _handleLanding(event, position);
        break;
    }
  }

  /// Handle takeoff detection
  Future<void> _handleTakeoff(FlightEvent event, TrackPoint position) async {
    // Find nearest takeoff site within 500m radius
    // Use the current position (position parameter) which is the fresh GPS reading,
    // not the event coordinates which may be from the detection algorithm
    String takeoffSiteName = 'Unknown Location';
    String? takeoffSiteId;

    // Search for any site typed as "takeoff" within 500m radius (no altitude restriction)
    // Use position.latitude/longitude for fresh GPS data
    final takeoffSiteMatch = LocationService.findNearestSiteByTypeWithinRadius(
      position.latitude,
      position.longitude,
      _cachedSites,
      'takeoff',
      radiusThreshold: 500.0,
    );

    if (takeoffSiteMatch != null) {
      final site = takeoffSiteMatch.site;
      takeoffSiteName = LocationService.getSiteName(site, lang: _currentLanguage);
      takeoffSiteId = LocationService.getSiteId(site);
      log('[FlightTrackingService] Found takeoff site within 500m: $takeoffSiteName (distance: ${takeoffSiteMatch.distance.toStringAsFixed(0)}m)');
    } else {
      // If no takeoff site found, use "Unknown Location (coordinates)" format
      // This allows the user to edit and name the location later
      // Use position coordinates (fresh GPS) instead of event coordinates
      takeoffSiteName = 'Unknown Location (${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)})';
      log('[FlightTrackingService] No takeoff site found within 500m - saving as Unknown Location with coordinates');
    }

    // Create new flight
    // Store position coordinates (fresh GPS data) instead of event coordinates
    _currentFlight = TrackedFlight(
      id: _generateFlightId(),
      takeoffTime: event.timestamp,
      takeoffSiteId: takeoffSiteId,
      takeoffSiteName: takeoffSiteName,
      takeoffLatitude: position.latitude,
      takeoffLongitude: position.longitude,
      takeoffAltitude: position.altitude,
      status: FlightTrackingStatus.inFlight,
      trackPoints: [position],
    );

    log('[FlightTrackingService] TAKEOFF: lat=${position.latitude.toStringAsFixed(6)}, lon=${position.longitude.toStringAsFixed(6)}, alt=${position.altitude.toStringAsFixed(0)}m at $takeoffSiteName');

    _updateStatus('IN FLIGHT - Takeoff: $takeoffSiteName');
    await _saveCurrentFlight();

    // Start auto-close timer for testing/simulation
    _resetAutoCloseTimer();
    
    // Start live tracking for authorities (pass position for credential checks at takeoff)
    print('🛫 [FlightTracking] Takeoff detected, starting live tracking...');
    print('🛫 [FlightTracking] LiveTrackingService is ${_liveTrackingService == null ? "NULL ⚠️" : "connected ✓"}');
    await _liveTrackingService?.startTracking(
      takeoffSiteName: takeoffSiteName,
      latitude: position.latitude,
      longitude: position.longitude,
      altitude: position.altitude,
    );

    onFlightStarted?.call(_currentFlight!);
    onStatusChanged?.call(_currentStatus);
    notifyListeners();

    log('[FlightTrackingService] Takeoff detected at $takeoffSiteName');
  }

  /// Handle landing detection
  Future<void> _handleLanding(FlightEvent event, TrackPoint position) async {
    print('🛬🛬🛬 [FlightTracking] ========================================');
    print('🛬 [FlightTracking] _handleLanding CALLED!');
    print('🛬 [FlightTracking] Current flight: ${_currentFlight?.id ?? "NULL"}');
    
    if (_currentFlight == null) {
      print('🛬 [FlightTracking] ❌ No current flight, cannot handle landing');
      return;
    }

    // Find nearest landing site by type
    String landingSiteName = 'Unknown Location';
    String? landingSiteId;

    // First try to find a site specifically typed as "landing"
    final landingSiteMatch = LocationService.findNearestSiteByType(
      event.latitude,
      event.longitude,
      event.altitude,
      _cachedSites,
      'landing',
    );

    if (landingSiteMatch != null) {
      final site = landingSiteMatch.site;
      landingSiteName = LocationService.getSiteName(site, lang: _currentLanguage);
      landingSiteId = LocationService.getSiteId(site);
      log('[FlightTrackingService] Found landing site: $landingSiteName (distance: ${landingSiteMatch.distance.toStringAsFixed(0)}m)');
    } else {
      // Fallback to any nearby site if no landing-specific site found
      final nearbySites = LocationService.findSitesWithinProximity(
        event.latitude,
        event.longitude,
        event.altitude,
        _cachedSites,
      );

      if (nearbySites.isNotEmpty) {
        final site = nearbySites.first.site;
        landingSiteName = LocationService.getSiteName(site, lang: _currentLanguage);
        landingSiteId = LocationService.getSiteId(site);
        log('[FlightTrackingService] Found nearby site (not typed as landing): $landingSiteName (distance: ${nearbySites.first.horizontalDistance.toStringAsFixed(0)}m)');
      } else {
        // Final fallback to coordinates if no site found
        landingSiteName = 'Unknown Landing (${event.latitude.toStringAsFixed(4)}, ${event.longitude.toStringAsFixed(4)})';
        log('[FlightTrackingService] No landing site found nearby - using coordinates');
      }
    }

    // Complete the flight
    final completedFlight = _currentFlight!.copyWith(
      landingTime: event.timestamp,
      landingSiteId: landingSiteId,
      landingSiteName: landingSiteName,
      landingLatitude: event.latitude,
      landingLongitude: event.longitude,
      landingAltitude: event.altitude,
      status: FlightTrackingStatus.completed,
      trackPoints: [..._currentFlight!.trackPoints, position],
    );

    // Add to tracked flights list
    _trackedFlights.insert(0, completedFlight);
    await _saveTrackedFlights();

    // Clear current flight
    _currentFlight = null;
    await _clearCurrentFlight();

    // Cancel auto-close timer
    _cancelAutoCloseTimer();

    // Reset detection service so next takeoff can be detected
    _detectionService.reset();
    
    // Stop live tracking for authorities
    print('🛬 [FlightTracking] Landing detected, stopping live tracking...');
    print('🛬 [FlightTracking] LiveTrackingService is ${_liveTrackingService == null ? "NULL" : "connected"}');
    print('🛬 [FlightTracking] LiveTrackingService.isActive = ${_liveTrackingService?.isActive}');
    
    try {
      print('🛬 [FlightTracking] Calling stopTracking()...');
      await _liveTrackingService?.stopTracking();
      print('🛬 [FlightTracking] ✅ stopTracking() completed successfully');
    } catch (e, st) {
      print('🛬 [FlightTracking] ❌ Error calling stopTracking(): $e');
      print('🛬 [FlightTracking] Stack trace: $st');
    }

    _updateStatus('Flight Complete: ${completedFlight.takeoffSiteName} → ${completedFlight.landingSiteName}');

    onFlightEnded?.call(completedFlight);
    onStatusChanged?.call(_currentStatus);
    
    // Wrap notifyListeners in microtask to avoid "setState during build" error
    Future.microtask(() => notifyListeners());

    // Reset status to Idle after notifying listeners so UI shows ground state
    _updateStatus('Idle');
    Future.microtask(() => notifyListeners());

    log('[FlightTrackingService] Landing detected at ${completedFlight.landingSiteName}');
  }

  /// Update nearest site information
  void _updateNearbySite(double lat, double lon, double alt) {
    // Find nearest takeoff site
    final nearestTakeoff = LocationService.findNearestSiteByType(
      lat,
      lon,
      alt,
      _cachedSites,
      'takeoff',
    );

    if (nearestTakeoff != null) {
      _nearestTakeoffSiteName = LocationService.getSiteName(nearestTakeoff.site, lang: _currentLanguage);
      _nearestTakeoffSiteDistance = nearestTakeoff.distance;
    } else {
      _nearestTakeoffSiteName = null;
      _nearestTakeoffSiteDistance = null;
    }

    // Find nearest landing site
    final nearestLanding = LocationService.findNearestSiteByType(
      lat,
      lon,
      alt,
      _cachedSites,
      'landing',
    );

    if (nearestLanding != null) {
      _nearestLandingSiteName = LocationService.getSiteName(nearestLanding.site, lang: _currentLanguage);
      _nearestLandingSiteDistance = nearestLanding.distance;
    } else {
      _nearestLandingSiteName = null;
      _nearestLandingSiteDistance = null;
    }
  }

  /// Update status message
  void _updateStatus(String status) {
    _currentStatus = status;
    onStatusChanged?.call(status);
  }

  /// Reset the auto-close timer
  /// If no position update is received for autoCloseFlightTimeout, automatically close the flight
  void _resetAutoCloseTimer() {
    if (!isInFlight) return;

    // Cancel existing timer
    _autoCloseFlightTimer?.cancel();

    // Start new timer
    _autoCloseFlightTimer = Timer(autoCloseFlightTimeout, () {
      if (_currentFlight != null && _lastPosition != null) {
        log('[FlightTrackingService] Auto-closing flight: No position update for ${autoCloseFlightTimeout.inSeconds}s');
        _autoCloseCurrentFlight();
      }
    });
  }

  /// Auto-close the current flight using the last known position as landing
  /// This is used when a tracklog file ends or GPS updates stop
  Future<void> _autoCloseCurrentFlight() async {
    if (_currentFlight == null || _lastPosition == null) return;

    final lastPosition = _lastPosition!;

    log('[FlightTrackingService] AUTO-CLOSE: Using last position as landing');
    log('[FlightTrackingService] LANDING: lat=${lastPosition.latitude.toStringAsFixed(6)}, lon=${lastPosition.longitude.toStringAsFixed(6)}, alt=${lastPosition.altitude.toStringAsFixed(0)}m');
    log('[FlightTrackingService] TAKEOFF stored: lat=${_currentFlight!.takeoffLatitude.toStringAsFixed(6)}, lon=${_currentFlight!.takeoffLongitude.toStringAsFixed(6)}');

    // Find nearest landing site by type
    String landingSiteName = 'Unknown Location';
    String? landingSiteId;

    // First try to find a site specifically typed as "landing"
    final landingSiteMatch = LocationService.findNearestSiteByType(
      lastPosition.latitude,
      lastPosition.longitude,
      lastPosition.altitude,
      _cachedSites,
      'landing',
    );

    if (landingSiteMatch != null) {
      final site = landingSiteMatch.site;
      landingSiteName = LocationService.getSiteName(site, lang: _currentLanguage);
      landingSiteId = LocationService.getSiteId(site);
      log('[FlightTrackingService] Auto-close: Found landing site: $landingSiteName (distance: ${landingSiteMatch.distance.toStringAsFixed(0)}m)');
    } else {
      // Fallback to any nearby site if no landing-specific site found
      final nearbySites = LocationService.findSitesWithinProximity(
        lastPosition.latitude,
        lastPosition.longitude,
        lastPosition.altitude,
        _cachedSites,
      );

      if (nearbySites.isNotEmpty) {
        final site = nearbySites.first.site;
        landingSiteName = LocationService.getSiteName(site, lang: _currentLanguage);
        landingSiteId = LocationService.getSiteId(site);
        log('[FlightTrackingService] Auto-close: Found nearby site (not typed as landing): $landingSiteName (distance: ${nearbySites.first.horizontalDistance.toStringAsFixed(0)}m)');
      } else {
        // Final fallback to coordinates if no site found
        landingSiteName = 'Unknown Landing (${lastPosition.latitude.toStringAsFixed(4)}, ${lastPosition.longitude.toStringAsFixed(4)})';
        log('[FlightTrackingService] Auto-close: No landing site found nearby - using coordinates');
      }
    }

    // Complete the flight
    final completedFlight = _currentFlight!.copyWith(
      landingTime: lastPosition.timestamp,
      landingSiteId: landingSiteId,
      landingSiteName: landingSiteName,
      landingLatitude: lastPosition.latitude,
      landingLongitude: lastPosition.longitude,
      landingAltitude: lastPosition.altitude,
      status: FlightTrackingStatus.completed,
      trackPoints: [..._currentFlight!.trackPoints, lastPosition],
    );

    // Add to tracked flights list
    _trackedFlights.insert(0, completedFlight);
    await _saveTrackedFlights();

    // Clear current flight
    _currentFlight = null;
    await _clearCurrentFlight();

    // Cancel auto-close timer
    _cancelAutoCloseTimer();

    // Reset detection service for next flight
    _detectionService.reset();
    
    // Stop live tracking for authorities
    print('🛬 [FlightTracking] AUTO-CLOSE: Stopping live tracking...');
    print('🛬 [FlightTracking] LiveTrackingService is ${_liveTrackingService == null ? "NULL" : "connected"}');
    print('🛬 [FlightTracking] LiveTrackingService.isActive = ${_liveTrackingService?.isActive}');
    
    try {
      print('🛬 [FlightTracking] Calling stopTracking()...');
      await _liveTrackingService?.stopTracking();
      print('🛬 [FlightTracking] ✅ stopTracking() completed successfully');
    } catch (e, st) {
      print('🛬 [FlightTracking] ❌ Error calling stopTracking(): $e');
      print('🛬 [FlightTracking] Stack trace: $st');
    }

    _updateStatus('Flight Recorded: ${completedFlight.takeoffSiteName} → ${completedFlight.landingSiteName}');

    onFlightEnded?.call(completedFlight);
    onStatusChanged?.call(_currentStatus);
    notifyListeners();

    // Reset status to Idle after notifying listeners so UI shows ground state
    _updateStatus('Idle');
    notifyListeners();

    log('[FlightTrackingService] Flight auto-closed with landing at ${completedFlight.landingSiteName}');
  }

  /// Cancel the auto-close timer
  void _cancelAutoCloseTimer() {
    _autoCloseFlightTimer?.cancel();
    _autoCloseFlightTimer = null;
  }

  // ============================================
  // SIMULATION / TESTING
  // ============================================

  /// Start simulation from tracklog data
  Future<void> startSimulation(List<TrackPoint> tracklog, {Duration interval = const Duration(milliseconds: 100)}) async {
    if (tracklog.isEmpty) return;

    await enableTracking();

    _isSimulating = true;
    _simulationTracklog = tracklog;
    _simulationIndex = 0;

    _updateStatus('Simulating flight...');
    notifyListeners();

    _simulationTimer = Timer.periodic(interval, (timer) {
      if (_simulationIndex >= _simulationTracklog!.length) {
        stopSimulation();
        return;
      }

      final point = _simulationTracklog![_simulationIndex];
      processPosition(
        latitude: point.latitude,
        longitude: point.longitude,
        altitude: point.altitude,
        speed: point.speed,
        heading: point.heading,
        timestamp: point.timestamp,
      );

      _simulationIndex++;
    });

    log('[FlightTrackingService] Started simulation with ${tracklog.length} points');
  }

  /// Start simulation from file content
  Future<void> startSimulationFromFile(String content, TracklogFormat format) async {
    final tracklog = TracklogParserService.parseTracklog(content, format);
    await startSimulation(tracklog);
  }

  /// Stop ongoing simulation
  void stopSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _isSimulating = false;
    _simulationTracklog = null;
    _simulationIndex = 0;

    if (!_detectionService.isInFlight) {
      _updateStatus('Simulation ended');
    }

    notifyListeners();
    log('[FlightTrackingService] Simulation stopped');
  }

  /// Generate a test tracklog for simulation
  List<TrackPoint> generateTestTracklog({
    double? startLat,
    double? startLon,
    double? startAlt,
    double? endLat,
    double? endLon,
    double? endAlt,
    Duration? duration,
  }) {
    // Use first site as default if available
    double defaultLat = 47.0;
    double defaultLon = 10.0;
    double defaultAlt = 1000;

    if (_cachedSites.isNotEmpty) {
      final site = _cachedSites.first;
      final latVal = site['latitude'] ?? site['lat'] ?? 47.0;
      final lonVal = site['longitude'] ?? site['lon'] ?? 10.0;
      final altVal = site['altitude'] ?? site['alt'] ?? 1000;
      
      defaultLat = (latVal is int) ? latVal.toDouble() : (latVal as double);
      defaultLon = (lonVal is int) ? lonVal.toDouble() : (lonVal as double);
      defaultAlt = (altVal is int) ? altVal.toDouble() : (altVal as double);
    }

    return TracklogParserService.generateTestTracklog(
      startLat: startLat ?? defaultLat,
      startLon: startLon ?? defaultLon,
      startAlt: startAlt ?? defaultAlt,
      endLat: endLat ?? defaultLat + 0.05,
      endLon: endLon ?? defaultLon + 0.05,
      endAlt: endAlt ?? defaultAlt - 200,
      flightDuration: duration ?? const Duration(minutes: 30),
    );
  }

  // ============================================
  // FLIGHT MANAGEMENT
  // ============================================

  /// Cancel current flight (if in progress)
  Future<void> cancelCurrentFlight() async {
    if (_currentFlight == null) return;

    _cancelAutoCloseTimer();

    final cancelledFlight = _currentFlight!.copyWith(
      status: FlightTrackingStatus.cancelled,
      landingTime: DateTime.now(),
    );

    _trackedFlights.insert(0, cancelledFlight);
    await _saveTrackedFlights();

    _currentFlight = null;
    await _clearCurrentFlight();

    _detectionService.reset();
    _updateStatus('Flight cancelled');

    notifyListeners();
    log('[FlightTrackingService] Flight cancelled');
  }

  /// Clear current flight after it has been saved to the Flight Book
  Future<void> clearCurrentFlightAfterSave() async {
    if (_currentFlight == null) return;

    _cancelAutoCloseTimer();
    _currentFlight = null;
    await _clearCurrentFlight();

    _detectionService.reset();
    _updateStatus('Flight saved to Flight Book. Ready for next flight.');

    notifyListeners();
    log('[FlightTrackingService] Current flight cleared after saving to Flight Book');
  }

  /// Set status to Standby (after flight is saved)
  /// Also clears all flight-related state to ensure clean UI display
  void setStatusToStandby() {
    _updateStatus('Standby');
    // Clear flight-related state to ensure status card shows only "Standby"
    _nearestTakeoffSiteName = null;
    _nearestTakeoffSiteDistance = null;
    _nearestLandingSiteName = null;
    _nearestLandingSiteDistance = null;
    _lastFlightEvent = null;
    notifyListeners();
  }

  /// Remove a tracked flight from the recent flights list (after it's been saved to Flight Book)
  Future<void> removeTrackedFlight(String flightId) async {
    _trackedFlights.removeWhere((flight) => flight.id == flightId);
    await _saveTrackedFlights();
    notifyListeners();
    log('[FlightTrackingService] Tracked flight $flightId removed from recent flights');
  }

  /// Delete a tracked flight
  Future<void> deleteTrackedFlight(String flightId) async {
    _trackedFlights.removeWhere((f) => f.id == flightId);
    await _saveTrackedFlights();
    notifyListeners();
    log('[FlightTrackingService] Deleted flight: $flightId');
  }

  /// Mark flight as synced to Firebase
  Future<void> markFlightAsSynced(String flightId) async {
    final index = _trackedFlights.indexWhere((f) => f.id == flightId);
    if (index >= 0) {
      _trackedFlights[index] = _trackedFlights[index].copyWith(
        isSyncedToFirebase: true,
        syncedAt: DateTime.now(),
      );
      await _saveTrackedFlights();
      notifyListeners();
    }
  }

  /// Get flights that haven't been synced to Firebase
  List<TrackedFlight> getUnsyncedFlights() {
    return _trackedFlights
        .where((f) => !f.isSyncedToFirebase && f.status == FlightTrackingStatus.completed)
        .toList();
  }

  // ============================================
  // CACHE MANAGEMENT
  // ============================================

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Always start with tracking disabled (toggle OFF)
      _isTrackingEnabled = false;

      // Load tracked flights
      final flightsJson = prefs.getString(_trackedFlightsCacheKey);
      if (flightsJson != null) {
        final List<dynamic> decoded = json.decode(flightsJson);
        _trackedFlights = decoded
            .map((item) => TrackedFlight.fromJson(item as Map<String, dynamic>))
            .toList();
      }

      // Load current flight (if tracking was interrupted)
      final currentJson = prefs.getString(_currentFlightCacheKey);
      if (currentJson != null) {
        _currentFlight = TrackedFlight.fromJson(json.decode(currentJson));
      }

      log('[FlightTrackingService] Loaded ${_trackedFlights.length} flights from cache');
      // Notify listeners after loading cached data so UI updates with pending tracklogs on startup
      notifyListeners();
    } catch (e) {
      log('[FlightTrackingService] Cache load error: $e');
    }
  }

  Future<void> _saveTrackedFlights() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final flightsJson = json.encode(_trackedFlights.map((f) => f.toJson()).toList());
      await prefs.setString(_trackedFlightsCacheKey, flightsJson);
    } catch (e) {
      log('[FlightTrackingService] Cache save error: $e');
    }
  }

  Future<void> _saveCurrentFlight() async {
    if (_currentFlight == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_currentFlightCacheKey, json.encode(_currentFlight!.toJson()));
    } catch (e) {
      log('[FlightTrackingService] Current flight save error: $e');
    }
  }

  Future<void> _clearCurrentFlight() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_currentFlightCacheKey);
    } catch (e) {
      log('[FlightTrackingService] Clear current flight error: $e');
    }
  }

  Future<void> _saveTrackingState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_trackingEnabledKey, _isTrackingEnabled);
    } catch (e) {
      log('[FlightTrackingService] Save tracking state error: $e');
    }
  }

  /// Clear all cached data
  Future<void> clearAllData() async {
    _trackedFlights.clear();
    _currentFlight = null;
    _detectionService.reset();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_trackedFlightsCacheKey);
    await prefs.remove(_currentFlightCacheKey);

    notifyListeners();
    log('[FlightTrackingService] All data cleared');
  }

  /// Reset service state
  void resetService() {
    _isTrackingEnabled = false;
    _isInitialized = false;
    _currentFlight = null;
    _trackedFlights.clear();
    _cachedSites.clear();
    _detectionService.reset();
    stopSimulation();

    _lastPosition = null;
    _currentStatus = 'Idle';
    _nearestTakeoffSiteName = null;
    _nearestTakeoffSiteDistance = null;
    _nearestLandingSiteName = null;
    _nearestLandingSiteDistance = null;

    notifyListeners();
  }

  // ============================================
  // UTILITIES
  // ============================================

  String _generateFlightId() {
    return 'flight_${DateTime.now().millisecondsSinceEpoch}_${_trackedFlights.length}';
  }

  /// Analyze a tracklog and detect all flights in it
  List<TrackedFlight> analyzeTracklog(List<TrackPoint> trackPoints) {
    if (trackPoints.isEmpty) return [];

    final detectedFlights = <TrackedFlight>[];
    TrackedFlight? currentFlight;

    for (int i = 0; i < trackPoints.length; i++) {
      final event = _detectionService.processTrackPoint(trackPoints[i]);

      if (event != null) {
        if (event.type == FlightEventType.takeoff) {
          // Start new flight
          if (currentFlight != null) {
            detectedFlights.add(currentFlight);
          }

          final nearbySites = LocationService.findSitesWithinProximity(
            trackPoints[i].latitude,
            trackPoints[i].longitude,
            trackPoints[i].altitude,
            _cachedSites,
          );
          final takeoffSite = nearbySites.isNotEmpty ? nearbySites.first.site : null;

          currentFlight = TrackedFlight(
            id: _generateFlightId(),
            takeoffTime: trackPoints[i].timestamp,
            takeoffSiteName: takeoffSite?['name'] ?? 'Unknown',
            takeoffLatitude: trackPoints[i].latitude,
            takeoffLongitude: trackPoints[i].longitude,
            takeoffAltitude: trackPoints[i].altitude,
            status: FlightTrackingStatus.inFlight,
            trackPoints: [trackPoints[i]],
          );
        } else if (event.type == FlightEventType.landing && currentFlight != null) {
          // End current flight
          final nearbySites = LocationService.findSitesWithinProximity(
            trackPoints[i].latitude,
            trackPoints[i].longitude,
            trackPoints[i].altitude,
            _cachedSites,
          );
          final landingSite = nearbySites.isNotEmpty ? nearbySites.first.site : null;

          currentFlight = currentFlight.copyWith(
            landingTime: trackPoints[i].timestamp,
            landingSiteName: landingSite?['name'] ?? 'Unknown',
            landingLatitude: trackPoints[i].latitude,
            landingLongitude: trackPoints[i].longitude,
            landingAltitude: trackPoints[i].altitude,
            status: FlightTrackingStatus.completed,
          );
          currentFlight.trackPoints.add(trackPoints[i]);
          detectedFlights.add(currentFlight);
          currentFlight = null;
        }
      } else if (currentFlight != null) {
        // Add track point to current flight
        currentFlight.trackPoints.add(trackPoints[i]);
      }
    }

    // If still in flight, add the last one
    if (currentFlight != null) {
      detectedFlights.add(currentFlight);
    }

    return detectedFlights;
  }

  /// Format duration as string
  static String formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  @override
  void dispose() {
    stopSimulation();
    super.dispose();
  }
}
