// File: lib/services/airspace_service.dart

import 'dart:convert';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

/// Represents a restricted airspace zone (CTR, TMA, Danger, Restricted areas)
class RestrictedZone {
  final String name;
  final String type; // 'CTR', 'TMA', 'Danger', 'Restricted', 'Prohibited'
  final double minAltitude; // meters MSL
  final double maxAltitude; // meters MSL
  final List<GeoPoint> polygon; // boundary coordinates

  RestrictedZone({
    required this.name,
    required this.type,
    required this.minAltitude,
    required this.maxAltitude,
    required this.polygon,
  });

  /// Check if a point is inside this zone
  bool contains(double lat, double lng, double altitudeM) {
    // Check altitude range first (faster)
    if (altitudeM < minAltitude || altitudeM > maxAltitude) {
      return false;
    }

    // Point-in-polygon algorithm for lat/lng
    return _pointInPolygon(lat, lng, polygon);
  }

  /// Ray casting algorithm for point-in-polygon test
  bool _pointInPolygon(double lat, double lng, List<GeoPoint> polygon) {
    if (polygon.length < 3) return false;

    bool isInside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].latitude;
      final yi = polygon[i].longitude;
      final xj = polygon[j].latitude;
      final yj = polygon[j].longitude;

      if (((yi > lng) != (yj > lng)) &&
          (lat < (xj - xi) * (lng - yi) / (yj - yi) + xi)) {
        isInside = !isInside;
      }
    }
    return isInside;
  }

  /// Create from JSON
  factory RestrictedZone.fromJson(Map<String, dynamic> json) {
    return RestrictedZone(
      name: json['name'] as String? ?? 'Unknown',
      type: json['type'] as String? ?? 'Restricted',
      minAltitude: (json['minAltitude'] as num?)?.toDouble() ?? 0.0,
      maxAltitude: (json['maxAltitude'] as num?)?.toDouble() ?? 99999.0,
      polygon: (json['polygon'] as List<dynamic>?)
              ?.map((p) => GeoPoint(
                    (p['latitude'] as num).toDouble(),
                    (p['longitude'] as num).toDouble(),
                  ))
              .toList() ??
          [],
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'minAltitude': minAltitude,
        'maxAltitude': maxAltitude,
        'polygon': polygon
            .map((p) => {
                  'latitude': p.latitude,
                  'longitude': p.longitude,
                })
            .toList(),
      };

  @override
  String toString() {
    return 'RestrictedZone(name: $name, type: $type, altRange: $minAltitude-$maxAltitude m, vertices: ${polygon.length})';
  }
}

/// Service for managing airspace data and checking violations
///
/// Features:
/// - Loads Swiss airspace data from local asset or Firestore
/// - Checks if a position is inside restricted airspace
/// - Provides zone information for alerts
class AirspaceService {
  static final AirspaceService _instance = AirspaceService._internal();

  List<RestrictedZone> _restrictedZones = [];
  bool _isInitialized = false;
  bool _isLoading = false;
  String? _lastError;

  factory AirspaceService() {
    return _instance;
  }

  AirspaceService._internal();

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;
  int get zoneCount => _restrictedZones.length;
  List<RestrictedZone> get zones => List.unmodifiable(_restrictedZones);

  /// Initialize the airspace service
  /// Call this at app startup
  Future<void> initialize() async {
    if (_isInitialized || _isLoading) return;

    _isLoading = true;
    _lastError = null;

    try {
      _restrictedZones = await _loadAirspaceData();
      _isInitialized = true;
      log('[AirspaceService] ✓ Initialized with ${_restrictedZones.length} restricted zones');
    } catch (e) {
      _lastError = e.toString();
      log('[AirspaceService] ✗ Error initializing: $e');
      // Don't throw - allow app to continue without airspace data
      _restrictedZones = [];
      _isInitialized =
          true; // Mark as initialized even on error to prevent retry loops
    } finally {
      _isLoading = false;
    }
  }

  /// Load airspace data from local JSON asset
  Future<List<RestrictedZone>> _loadAirspaceData() async {
    try {
      // Try to load from local asset first
      final data =
          await rootBundle.loadString('assets/airspace/swiss_airspace.json');
      final json = jsonDecode(data) as Map<String, dynamic>;

      final zonesJson = json['restrictedZones'] as List<dynamic>? ?? [];
      final zones = zonesJson
          .map((z) => RestrictedZone.fromJson(z as Map<String, dynamic>))
          .toList();

      log('[AirspaceService] Loaded ${zones.length} zones from local asset');
      return zones;
    } catch (e) {
      log('[AirspaceService] Error loading from asset: $e');

      // Fallback: Return empty list (airspace checking will be disabled)
      log('[AirspaceService] No airspace data available - airspace checking disabled');
      return [];
    }
  }

  /// Check if a position is inside any restricted airspace
  bool isInRestrictedAirspace(double lat, double lng, double altitudeM) {
    if (!_isInitialized || _restrictedZones.isEmpty) {
      return false;
    }

    for (final zone in _restrictedZones) {
      if (zone.contains(lat, lng, altitudeM)) {
        return true;
      }
    }
    return false;
  }

  /// Get the restricted zone containing the given position
  /// Returns null if position is not in any restricted zone
  RestrictedZone? getRestrictedZone(double lat, double lng, double altitudeM) {
    if (!_isInitialized || _restrictedZones.isEmpty) {
      return null;
    }

    for (final zone in _restrictedZones) {
      if (zone.contains(lat, lng, altitudeM)) {
        return zone;
      }
    }
    return null;
  }

  /// Get all zones that contain the given position
  /// Useful when zones overlap
  List<RestrictedZone> getAllRestrictedZones(
      double lat, double lng, double altitudeM) {
    if (!_isInitialized || _restrictedZones.isEmpty) {
      return [];
    }

    return _restrictedZones
        .where((zone) => zone.contains(lat, lng, altitudeM))
        .toList();
  }

  /// Find zones near a position (within approximate radius)
  /// Useful for preemptive warnings
  List<RestrictedZone> getNearbyZones(double lat, double lng, double radiusKm) {
    if (!_isInitialized || _restrictedZones.isEmpty) {
      return [];
    }

    final nearbyZones = <RestrictedZone>[];

    for (final zone in _restrictedZones) {
      // Simple bounding box check for efficiency
      // Check if any polygon vertex is within approximate radius
      for (final point in zone.polygon) {
        final distance =
            _approximateDistanceKm(lat, lng, point.latitude, point.longitude);
        if (distance <= radiusKm) {
          nearbyZones.add(zone);
          break; // Found one point within radius, move to next zone
        }
      }
    }

    return nearbyZones;
  }

  /// Approximate distance calculation (fast but not precise)
  /// Good enough for proximity checks
  double _approximateDistanceKm(
      double lat1, double lng1, double lat2, double lng2) {
    // Simple equirectangular approximation
    const double kmPerDegLat = 111.0; // km per degree latitude
    final kmPerDegLng =
        111.0 * _cosApprox(lat1); // km per degree longitude at latitude

    final dLat = (lat2 - lat1) * kmPerDegLat;
    final dLng = (lng2 - lng1) * kmPerDegLng;

    return _sqrt(dLat * dLat + dLng * dLng);
  }

  /// Approximate cosine (avoids dart:math import for simple calculation)
  double _cosApprox(double degrees) {
    final rad = degrees * 0.0174533; // degrees to radians
    // Taylor series approximation
    final x2 = rad * rad;
    return 1.0 - x2 / 2.0 + x2 * x2 / 24.0;
  }

  /// Approximate square root (Newton's method)
  double _sqrt(double x) {
    if (x <= 0) return 0;
    double guess = x / 2.0;
    for (int i = 0; i < 10; i++) {
      guess = (guess + x / guess) / 2.0;
    }
    return guess;
  }

  /// Reload airspace data (e.g., after an update)
  Future<void> reload() async {
    _isInitialized = false;
    _restrictedZones = [];
    await initialize();
  }

  /// Add zones manually (for testing or dynamic updates)
  void addZones(List<RestrictedZone> zones) {
    _restrictedZones.addAll(zones);
    log('[AirspaceService] Added ${zones.length} zones, total: ${_restrictedZones.length}');
  }

  /// Clear all zones (for testing)
  void clearZones() {
    _restrictedZones.clear();
    log('[AirspaceService] Cleared all zones');
  }

  /// Get summary for debugging
  String getSummary() {
    final typeCounts = <String, int>{};
    for (final zone in _restrictedZones) {
      typeCounts[zone.type] = (typeCounts[zone.type] ?? 0) + 1;
    }
    return 'AirspaceService: ${_restrictedZones.length} zones - $typeCounts';
  }
}
