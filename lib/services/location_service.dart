// File: lib/services/location_service.dart

import 'dart:math';

/// Location service for GPS proximity and distance calculations
/// Uses Haversine formula for accurate distance calculation
class LocationService {
  static const double earthRadiusMeters = 6371000;

  /// Horizontal proximity threshold in meters
  static const double horizontalProximityThreshold = 80.0;

  /// Vertical proximity threshold in meters
  static const double verticalProximityThreshold = 100.0;

  /// Calculate distance between two GPS coordinates using Haversine formula
  /// Returns distance in meters
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  /// Convert degrees to radians
  static double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  /// Check if position is within proximity of a site
  /// Returns true if within horizontalProximityThreshold meters horizontally
  /// and verticalProximityThreshold meters vertically
  static bool isWithinProximity(
    double currentLat,
    double currentLon,
    double currentAlt,
    double siteLat,
    double siteLon,
    double siteAlt,
  ) {
    final horizontalDistance = calculateDistance(
      currentLat,
      currentLon,
      siteLat,
      siteLon,
    );

    final verticalDifference = (currentAlt - siteAlt).abs();

    return horizontalDistance <= horizontalProximityThreshold &&
        verticalDifference <= verticalProximityThreshold;
  }

  /// Find the nearest site from a list of sites
  /// Returns the site data and distance, or null if no sites provided
  static ({Map<String, dynamic> site, double distance})? findNearestSite(
    double currentLat,
    double currentLon,
    double currentAlt,
    List<Map<String, dynamic>> sites,
  ) {
    if (sites.isEmpty) return null;

    Map<String, dynamic>? nearestSite;
    double minDistance = double.infinity;

    for (final site in sites) {
      final siteLat = _parseDouble(site['latitude'] ?? site['lat']);
      final siteLon = _parseDouble(site['longitude'] ?? site['lon']);

      if (siteLat == null || siteLon == null) continue;

      final distance = calculateDistance(
        currentLat,
        currentLon,
        siteLat,
        siteLon,
      );

      if (distance < minDistance) {
        minDistance = distance;
        nearestSite = site;
      }
    }

    if (nearestSite == null) return null;

    return (site: nearestSite, distance: minDistance);
  }

  /// Find all sites within proximity threshold
  /// Returns list of sites with their distances
  static List<({Map<String, dynamic> site, double horizontalDistance, double verticalDifference})>
      findSitesWithinProximity(
    double currentLat,
    double currentLon,
    double currentAlt,
    List<Map<String, dynamic>> sites,
  ) {
    final result = <({
      Map<String, dynamic> site,
      double horizontalDistance,
      double verticalDifference
    })>[];

    for (final site in sites) {
      final siteLat = _parseDouble(site['latitude'] ?? site['lat']);
      final siteLon = _parseDouble(site['longitude'] ?? site['lon']);
      final siteAlt = _parseDouble(site['altitude'] ?? site['alt']) ?? 0;

      if (siteLat == null || siteLon == null) continue;

      final horizontalDistance = calculateDistance(
        currentLat,
        currentLon,
        siteLat,
        siteLon,
      );

      final verticalDifference = (currentAlt - siteAlt).abs();

      if (horizontalDistance <= horizontalProximityThreshold &&
          verticalDifference <= verticalProximityThreshold) {
        result.add((
          site: site,
          horizontalDistance: horizontalDistance,
          verticalDifference: verticalDifference,
        ));
      }
    }

    // Sort by horizontal distance
    result.sort((a, b) => a.horizontalDistance.compareTo(b.horizontalDistance));

    return result;
  }

  /// Get site type (takeoff, landing, etc.)
  static String? getSiteType(Map<String, dynamic> site) {
    return site['type'] as String?;
  }

  /// Find the nearest site of a specific type from a list of sites
  /// Type should be 'takeoff', 'landing', or null for any type
  /// Returns the site data and distance, or null if no matching sites
  static ({Map<String, dynamic> site, double distance})? findNearestSiteByType(
    double currentLat,
    double currentLon,
    double currentAlt,
    List<Map<String, dynamic>> sites,
    String siteType,
  ) {
    if (sites.isEmpty) return null;

    Map<String, dynamic>? nearestSite;
    double minDistance = double.infinity;

    for (final site in sites) {
      // Filter by type if specified
      final type = getSiteType(site);
      if (type != siteType) continue;

      final siteLat = _parseDouble(site['latitude'] ?? site['lat'] ?? site['coords']?['lat']);
      final siteLon = _parseDouble(site['longitude'] ?? site['lon'] ?? site['coords']?['lng']);

      if (siteLat == null || siteLon == null) continue;

      final distance = calculateDistance(
        currentLat,
        currentLon,
        siteLat,
        siteLon,
      );

      if (distance < minDistance) {
        minDistance = distance;
        nearestSite = site;
      }
    }

    if (nearestSite == null) return null;

    return (site: nearestSite, distance: minDistance);
  }

  /// Find the nearest site of a specific type within a radius threshold
  /// Searches for sites within [radiusThreshold] meters (default 500m)
  /// Does NOT check altitude threshold - only horizontal distance
  /// This is useful for takeoff/landing detection where altitude varies during flight
  /// Returns the closest site within radius, or null if no sites found
  static ({Map<String, dynamic> site, double distance})? findNearestSiteByTypeWithinRadius(
    double currentLat,
    double currentLon,
    List<Map<String, dynamic>> sites,
    String siteType, {
    double radiusThreshold = 500.0,
  }) {
    if (sites.isEmpty) return null;

    Map<String, dynamic>? nearestSite;
    double minDistance = double.infinity;

    for (final site in sites) {
      // Filter by type if specified
      final type = getSiteType(site);
      if (type != siteType) continue;

      final siteLat = _parseDouble(site['latitude'] ?? site['lat'] ?? site['coords']?['lat']);
      final siteLon = _parseDouble(site['longitude'] ?? site['lon'] ?? site['coords']?['lng']);

      if (siteLat == null || siteLon == null) continue;

      final distance = calculateDistance(
        currentLat,
        currentLon,
        siteLat,
        siteLon,
      );

      // Only consider sites within the radius threshold
      if (distance <= radiusThreshold && distance < minDistance) {
        minDistance = distance;
        nearestSite = site;
      }
    }

    if (nearestSite == null) return null;

    return (site: nearestSite, distance: minDistance);
  }

  /// Get site name from site data
  static String getSiteName(Map<String, dynamic> site, {String lang = 'en'}) {
    return site['name_$lang'] as String? ??
        site['name'] as String? ??
        site['title'] as String? ??
        'Unknown Site';
  }

  /// Get site ID from site data
  static String? getSiteId(Map<String, dynamic> site) {
    return site['id'] as String?;
  }

  /// Get site altitude from site data
  static double getSiteAltitude(Map<String, dynamic> site) {
    return _parseDouble(site['altitude'] ?? site['alt']) ?? 0;
  }

  /// Calculate bearing between two points in degrees
  static double calculateBearing(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLon = _degreesToRadians(lon2 - lon1);
    final lat1Rad = _degreesToRadians(lat1);
    final lat2Rad = _degreesToRadians(lat2);

    final y = sin(dLon) * cos(lat2Rad);
    final x = cos(lat1Rad) * sin(lat2Rad) -
        sin(lat1Rad) * cos(lat2Rad) * cos(dLon);

    var bearing = atan2(y, x);
    bearing = bearing * 180 / pi;
    bearing = (bearing + 360) % 360;

    return bearing;
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
