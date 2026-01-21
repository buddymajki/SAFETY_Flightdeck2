// File: lib/services/airspace_service.dart

import 'dart:convert';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

/// Represents a restricted airspace zone from SHV/FSVL GeoJSON API
class RestrictedZone {
  final String id;
  final String name;
  final String type; // ASType: 'CTR', 'TMA', 'R', 'Q', 'Airfield', 'Heliport', etc.
  final String? asClass; // Airspace class: A-G (mostly C, D for Switzerland)
  final double minAltitude; // meters (lower limit)
  final double maxAltitude; // meters (upper limit)
  final String minAltitudeType; // 'QNH', 'STD', 'AGL', 'FL'
  final String maxAltitudeType; // 'QNH', 'STD', 'AGL', 'FL'
  final List<GeoPoint> polygon; // boundary coordinates
  final bool hx; // HX activated (can be activated any time)
  final bool dabs; // DABS activated
  final bool informational; // Only for information, no entry restrictions
  final String? frequency;
  final String? callsign;
  final String? additionalInfos;

  RestrictedZone({
    required this.id,
    required this.name,
    required this.type,
    this.asClass,
    required this.minAltitude,
    required this.maxAltitude,
    this.minAltitudeType = 'QNH',
    this.maxAltitudeType = 'QNH',
    required this.polygon,
    this.hx = false,
    this.dabs = false,
    this.informational = false,
    this.frequency,
    this.callsign,
    this.additionalInfos,
  });

  /// Check if a point is inside this zone (horizontal and vertical)
  bool contains(double lat, double lng, double altitudeM) {
    // Skip informational airspaces (no entry restrictions)
    if (informational) return false;
    
    // Check altitude range first (faster)
    // Note: For AGL altitudes, we would need terrain data for accurate check
    // For now, assume QNH/MSL altitudes
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

  /// Create from SHV/FSVL GeoJSON Feature
  factory RestrictedZone.fromGeoJsonFeature(Map<String, dynamic> feature) {
    final properties = feature['properties'] as Map<String, dynamic>? ?? {};
    final geometry = feature['geometry'] as Map<String, dynamic>? ?? {};
    
    // Parse polygon coordinates from GeoJSON (note: GeoJSON is [lng, lat])
    final List<GeoPoint> polygonPoints = [];
    final coordinates = geometry['coordinates'] as List<dynamic>?;
    if (coordinates != null && coordinates.isNotEmpty) {
      // GeoJSON Polygon has an outer ring at index 0
      final ring = coordinates[0] as List<dynamic>;
      for (final coord in ring) {
        if (coord is List && coord.length >= 2) {
          // GeoJSON is [longitude, latitude]
          polygonPoints.add(GeoPoint(
            (coord[1] as num).toDouble(), // latitude
            (coord[0] as num).toDouble(), // longitude
          ));
        }
      }
    }
    
    // Parse altitude limits from the SHV API format
    double minAlt = 0.0;
    double maxAlt = 99999.0;
    String minAltType = 'QNH';
    String maxAltType = 'QNH';
    
    final lower = properties['Lower'] as Map<String, dynamic>?;
    final upper = properties['Upper'] as Map<String, dynamic>?;
    
    if (lower != null) {
      final metric = lower['Metric'] as Map<String, dynamic>?;
      if (metric != null) {
        final alt = metric['Alt'] as Map<String, dynamic>?;
        if (alt != null) {
          minAlt = (alt['Altitude'] as num?)?.toDouble() ?? 0.0;
          minAltType = _parseAltitudeType(alt['Type'] as String?);
        }
      }
    }
    
    if (upper != null) {
      final metric = upper['Metric'] as Map<String, dynamic>?;
      if (metric != null) {
        final alt = metric['Alt'] as Map<String, dynamic>?;
        if (alt != null) {
          maxAlt = (alt['Altitude'] as num?)?.toDouble() ?? 99999.0;
          maxAltType = _parseAltitudeType(alt['Type'] as String?);
          // Convert FL to meters (1 FL = 30.48m, FL is in hundreds of feet)
          if (maxAltType == 'FL') {
            maxAlt = maxAlt * 30.48; // FL value * 100 feet * 0.3048 m/ft
          }
        }
      }
    }
    
    return RestrictedZone(
      id: properties['ID'] as String? ?? '',
      name: properties['Name'] as String? ?? 'Unknown',
      type: properties['ASType'] as String? ?? 'Restricted',
      asClass: properties['ASClass'] as String?,
      minAltitude: minAlt,
      maxAltitude: maxAlt,
      minAltitudeType: minAltType,
      maxAltitudeType: maxAltType,
      polygon: polygonPoints,
      hx: properties['HX'] as bool? ?? false,
      dabs: properties['DABS'] as bool? ?? false,
      informational: properties['Informational'] as bool? ?? false,
      frequency: properties['Frequency'] as String?,
      callsign: properties['Callsign'] as String?,
      additionalInfos: properties['AdditionalInfos'] as String?,
    );
  }
  
  /// Parse altitude type string
  static String _parseAltitudeType(String? typeStr) {
    if (typeStr == null) return 'QNH';
    if (typeStr.contains('AGL')) return 'AGL';
    if (typeStr.contains('STD')) return 'STD';
    if (typeStr.contains('FL')) return 'FL';
    return 'QNH';
  }

  /// Create from legacy JSON format
  factory RestrictedZone.fromJson(Map<String, dynamic> json) {
    return RestrictedZone(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      type: json['type'] as String? ?? 'Restricted',
      asClass: json['asClass'] as String?,
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
        'id': id,
        'name': name,
        'type': type,
        'asClass': asClass,
        'minAltitude': minAltitude,
        'maxAltitude': maxAltitude,
        'minAltitudeType': minAltitudeType,
        'maxAltitudeType': maxAltitudeType,
        'hx': hx,
        'dabs': dabs,
        'informational': informational,
        'frequency': frequency,
        'callsign': callsign,
        'polygon': polygon
            .map((p) => {
                  'latitude': p.latitude,
                  'longitude': p.longitude,
                })
            .toList(),
      };

  @override
  String toString() {
    return 'RestrictedZone(id: $id, name: $name, type: $type, class: $asClass, altRange: $minAltitude-$maxAltitude m, vertices: ${polygon.length})';
  }
}

/// Service for managing airspace data and checking violations
///
/// Features:
/// - Loads Swiss airspace data from SHV/FSVL GeoJSON API format
/// - Checks if a position is inside restricted airspace
/// - Provides zone information for alerts
class AirspaceService {
  static final AirspaceService _instance = AirspaceService._internal();

  List<RestrictedZone> _restrictedZones = [];
  bool _isInitialized = false;
  bool _isLoading = false;
  String? _lastError;
  DateTime? _lastUpdate;

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
  DateTime? get lastUpdate => _lastUpdate;

  /// Initialize the airspace service
  /// Call this at app startup
  Future<void> initialize() async {
    if (_isInitialized || _isLoading) return;

    _isLoading = true;
    _lastError = null;

    try {
      _restrictedZones = await _loadAirspaceData();
      _isInitialized = true;
      _lastUpdate = DateTime.now();
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

  /// Load airspace data from GeoJSON file
  /// First tries test/airspaces.json, then falls back to assets
  Future<List<RestrictedZone>> _loadAirspaceData() async {
    try {
      // Try to load from test folder first (for development/testing)
      String? data;
      try {
        data = await rootBundle.loadString('test/airspaces.json');
        log('[AirspaceService] Loading airspaces from test/airspaces.json');
      } catch (_) {
        // Fall back to assets folder
        try {
          data = await rootBundle.loadString('assets/airspace/swiss_airspace.json');
          log('[AirspaceService] Loading airspaces from assets/airspace/swiss_airspace.json');
        } catch (_) {
          log('[AirspaceService] No airspace data file found');
          return [];
        }
      }
      
      if (data.isEmpty) {
        log('[AirspaceService] Airspace data file is empty');
        return [];
      }
      
      final json = jsonDecode(data);
      
      // Check if it's GeoJSON FeatureCollection format (SHV/FSVL API)
      if (json is Map<String, dynamic> && json['type'] == 'FeatureCollection') {
        return _parseGeoJsonFeatureCollection(json);
      }
      
      // Legacy format with 'restrictedZones' array
      if (json is Map<String, dynamic> && json['restrictedZones'] != null) {
        final zonesJson = json['restrictedZones'] as List<dynamic>;
        return zonesJson
            .map((z) => RestrictedZone.fromJson(z as Map<String, dynamic>))
            .toList();
      }
      
      log('[AirspaceService] Unknown airspace data format');
      return [];
    } catch (e) {
      log('[AirspaceService] Error loading airspace data: $e');
      return [];
    }
  }
  
  /// Parse GeoJSON FeatureCollection from SHV/FSVL API
  List<RestrictedZone> _parseGeoJsonFeatureCollection(Map<String, dynamic> geoJson) {
    final features = geoJson['features'] as List<dynamic>? ?? [];
    final zones = <RestrictedZone>[];
    
    for (final feature in features) {
      try {
        if (feature is Map<String, dynamic>) {
          final zone = RestrictedZone.fromGeoJsonFeature(feature);
          // Only add zones with valid polygons
          if (zone.polygon.length >= 3) {
            zones.add(zone);
          }
        }
      } catch (e) {
        log('[AirspaceService] Error parsing feature: $e');
        // Continue with other features
      }
    }
    
    log('[AirspaceService] Parsed ${zones.length} zones from GeoJSON');
    return zones;
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
  
  /// Get zone by ID
  RestrictedZone? getZoneById(String id) {
    if (!_isInitialized || _restrictedZones.isEmpty) {
      return null;
    }
    try {
      return _restrictedZones.firstWhere((z) => z.id == id);
    } catch (_) {
      return null;
    }
  }
  
  /// Get zone by name
  RestrictedZone? getZoneByName(String name) {
    if (!_isInitialized || _restrictedZones.isEmpty) {
      return null;
    }
    try {
      return _restrictedZones.firstWhere(
        (z) => z.name.toLowerCase() == name.toLowerCase()
      );
    } catch (_) {
      return null;
    }
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
