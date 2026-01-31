// File: lib/services/tracklog_parser_service.dart

import 'dart:convert';
import 'dart:math';

import '../models/tracked_flight.dart';

/// Service for parsing historical tracklogs (GPX, IGC, KML formats)
/// Used for testing flight detection algorithms with real data
class TracklogParserService {
  /// Parse tracklog from file content based on format
  static List<TrackPoint> parseTracklog(String content, TracklogFormat format) {
    switch (format) {
      case TracklogFormat.gpx:
        return parseGpx(content);
      case TracklogFormat.igc:
        return parseIgc(content);
      case TracklogFormat.kml:
        return parseKml(content);
      case TracklogFormat.json:
        return parseJson(content);
    }
  }

  /// Detect format from file extension
  static TracklogFormat? detectFormat(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.gpx')) return TracklogFormat.gpx;
    if (lower.endsWith('.igc')) return TracklogFormat.igc;
    if (lower.endsWith('.kml')) return TracklogFormat.kml;
    if (lower.endsWith('.json')) return TracklogFormat.json;
    return null;
  }

  /// Parse GPX format tracklog
  static List<TrackPoint> parseGpx(String content) {
    final points = <TrackPoint>[];

    // Simple XML parsing for GPX format
    // GPX structure: <trkpt lat="..." lon="..."><ele>...</ele><time>...</time></trkpt>
    final trkptRegex = RegExp(
      r'<trkpt\s+lat="([^"]+)"\s+lon="([^"]+)"[^>]*>(.*?)</trkpt>',
      multiLine: true,
      dotAll: true,
    );

    final eleRegex = RegExp(r'<ele>([^<]+)</ele>');
    final timeRegex = RegExp(r'<time>([^<]+)</time>');
    final speedRegex = RegExp(r'<speed>([^<]+)</speed>');

    for (final match in trkptRegex.allMatches(content)) {
      try {
        final lat = double.parse(match.group(1)!);
        final lon = double.parse(match.group(2)!);
        final innerContent = match.group(3) ?? '';

        double altitude = 0;
        DateTime? timestamp;
        double? speed;

        final eleMatch = eleRegex.firstMatch(innerContent);
        if (eleMatch != null) {
          altitude = double.tryParse(eleMatch.group(1)!) ?? 0;
        }

        final timeMatch = timeRegex.firstMatch(innerContent);
        if (timeMatch != null) {
          timestamp = DateTime.tryParse(timeMatch.group(1)!);
        }

        final speedMatch = speedRegex.firstMatch(innerContent);
        if (speedMatch != null) {
          speed = double.tryParse(speedMatch.group(1)!);
        }

        if (timestamp != null) {
          points.add(TrackPoint(
            timestamp: timestamp,
            latitude: lat,
            longitude: lon,
            altitude: altitude,
            speed: speed,
          ));
        }
      } catch (e) {
        // Skip malformed points
        continue;
      }
    }

    // Sort by timestamp
    points.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Calculate vertical speeds
    return _calculateVerticalSpeeds(points);
  }

  /// Parse IGC format tracklog (International Gliding Commission format)
  static List<TrackPoint> parseIgc(String content) {
    final points = <TrackPoint>[];
    final lines = content.split('\n');

    DateTime? flightDate;

    // B record format: BHHMMSSDDMMMMMNSDDMMMMMEWAAAAAGGGGSSS
    // B = record type
    // HHMMSS = UTC time
    // DDMMMMM = latitude (degrees, minutes * 1000)
    // N/S = hemisphere
    // DDDMMMMM = longitude (degrees, minutes * 1000)
    // E/W = hemisphere
    // A = validity
    // AAAAA = pressure altitude
    // GGGGG = GPS altitude
    final bRecordRegex = RegExp(
      r'^B(\d{2})(\d{2})(\d{2})(\d{2})(\d{5})([NS])(\d{3})(\d{5})([EW])([AV])(\d{5})(\d{5})',
    );

    // HFDTE record for date: HFDTEddmmyy or HFDTEDATE:ddmmyy,nn
    final dateRegex = RegExp(r'^HFDTE(?:DATE:)?(\d{2})(\d{2})(\d{2})');

    for (final line in lines) {
      final trimmed = line.trim();

      // Parse date header
      final dateMatch = dateRegex.firstMatch(trimmed);
      if (dateMatch != null) {
        final day = int.parse(dateMatch.group(1)!);
        final month = int.parse(dateMatch.group(2)!);
        var year = int.parse(dateMatch.group(3)!);
        // Convert 2-digit year
        year = year < 70 ? 2000 + year : 1900 + year;
        flightDate = DateTime(year, month, day);
        continue;
      }

      // Parse B records
      final bMatch = bRecordRegex.firstMatch(trimmed);
      if (bMatch != null && flightDate != null) {
        try {
          final hour = int.parse(bMatch.group(1)!);
          final minute = int.parse(bMatch.group(2)!);
          final second = int.parse(bMatch.group(3)!);

          final latDeg = int.parse(bMatch.group(4)!);
          final latMin = int.parse(bMatch.group(5)!) / 1000.0;
          final latHem = bMatch.group(6)!;

          final lonDeg = int.parse(bMatch.group(7)!);
          final lonMin = int.parse(bMatch.group(8)!) / 1000.0;
          final lonHem = bMatch.group(9)!;

          final pressureAlt = int.parse(bMatch.group(11)!);
          final gpsAlt = int.parse(bMatch.group(12)!);

          // Convert to decimal degrees
          var latitude = latDeg + latMin / 60.0;
          if (latHem == 'S') latitude = -latitude;

          var longitude = lonDeg + lonMin / 60.0;
          if (lonHem == 'W') longitude = -longitude;

          // Use GPS altitude if valid, otherwise pressure altitude
          final altitude = gpsAlt > 0 ? gpsAlt.toDouble() : pressureAlt.toDouble();

          final timestamp = DateTime(
            flightDate.year,
            flightDate.month,
            flightDate.day,
            hour,
            minute,
            second,
          );

          points.add(TrackPoint(
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
          ));
        } catch (e) {
          // Skip malformed records
          continue;
        }
      }
    }

    // Sort by timestamp
    points.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Calculate vertical speeds
    return _calculateVerticalSpeeds(points);
  }

  /// Parse KML format tracklog
  static List<TrackPoint> parseKml(String content) {
    final points = <TrackPoint>[];

    // KML coordinates format: lon,lat,alt (space separated)
    final coordsRegex = RegExp(
      r'<coordinates>\s*([\s\S]*?)\s*</coordinates>',
      multiLine: true,
    );

    // When tag for timestamps
    final whenRegex = RegExp(r'<when>([^<]+)</when>');

    // Try to find gx:Track format first (with timestamps)
    final trackRegex = RegExp(
      r'<gx:Track>([\s\S]*?)</gx:Track>',
      multiLine: true,
    );

    final trackMatch = trackRegex.firstMatch(content);
    if (trackMatch != null) {
      final trackContent = trackMatch.group(1)!;
      final whenMatches = whenRegex.allMatches(trackContent).toList();
      final coordMatches = RegExp(r'<gx:coord>([^<]+)</gx:coord>')
          .allMatches(trackContent)
          .toList();

      for (int i = 0; i < coordMatches.length && i < whenMatches.length; i++) {
        try {
          final timestamp = DateTime.parse(whenMatches[i].group(1)!);
          final coords = coordMatches[i].group(1)!.trim().split(RegExp(r'\s+'));
          if (coords.length >= 3) {
            final lon = double.parse(coords[0]);
            final lat = double.parse(coords[1]);
            final alt = double.parse(coords[2]);

            points.add(TrackPoint(
              timestamp: timestamp,
              latitude: lat,
              longitude: lon,
              altitude: alt,
            ));
          }
        } catch (e) {
          continue;
        }
      }
    } else {
      // Fall back to simple coordinates parsing
      for (final match in coordsRegex.allMatches(content)) {
        final coordString = match.group(1)!;
        final coordPairs = coordString.trim().split(RegExp(r'\s+'));

        for (int i = 0; i < coordPairs.length; i++) {
          try {
            final parts = coordPairs[i].split(',');
            if (parts.length >= 3) {
              final lon = double.parse(parts[0]);
              final lat = double.parse(parts[1]);
              final alt = double.parse(parts[2]);

              // Generate synthetic timestamp (1 second apart)
              points.add(TrackPoint(
                timestamp: DateTime.now().add(Duration(seconds: i)),
                latitude: lat,
                longitude: lon,
                altitude: alt,
              ));
            }
          } catch (e) {
            continue;
          }
        }
      }
    }

    // Sort by timestamp
    points.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return _calculateVerticalSpeeds(points);
  }

  /// Parse JSON format tracklog (custom format)
  static List<TrackPoint> parseJson(String content) {
    final points = <TrackPoint>[];

    try {
      final data = json.decode(content);
      List<dynamic> trackData;

      if (data is List) {
        trackData = data;
      } else if (data is Map && data['track'] is List) {
        trackData = data['track'] as List;
      } else if (data is Map && data['points'] is List) {
        trackData = data['points'] as List;
      } else {
        return points;
      }

      for (final item in trackData) {
        if (item is Map) {
          try {
            final timestamp = item['timestamp'] != null
                ? DateTime.parse(item['timestamp'] as String)
                : item['time'] != null
                    ? DateTime.parse(item['time'] as String)
                    : DateTime.now();

            final lat = (item['latitude'] ?? item['lat'] as num).toDouble();
            final lon = (item['longitude'] ?? item['lon'] as num).toDouble();
            final alt = (item['altitude'] ?? item['alt'] ?? 0 as num).toDouble();
            final speed = item['speed'] != null
                ? (item['speed'] as num).toDouble()
                : null;
            final vspeed = item['verticalSpeed'] ?? item['vspeed'];
            final heading = item['heading'] ?? item['bearing'];

            points.add(TrackPoint(
              timestamp: timestamp,
              latitude: lat,
              longitude: lon,
              altitude: alt,
              speed: speed,
              verticalSpeed: vspeed != null ? (vspeed as num).toDouble() : null,
              heading: heading != null ? (heading as num).toDouble() : null,
            ));
          } catch (e) {
            continue;
          }
        }
      }
    } catch (e) {
      // Return empty list on parse error
    }

    // Sort by timestamp
    points.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return _calculateVerticalSpeeds(points);
  }

  /// Calculate vertical speeds and horizontal speeds between consecutive points
  static List<TrackPoint> _calculateVerticalSpeeds(List<TrackPoint> points) {
    if (points.length < 2) return points;

    final result = <TrackPoint>[];

    for (int i = 0; i < points.length; i++) {
      final point = points[i];

      double? verticalSpeed = point.verticalSpeed;
      double? speed = point.speed;

      if (i > 0) {
        final prev = points[i - 1];
        final timeDiff =
            point.timestamp.difference(prev.timestamp).inMilliseconds / 1000.0;
        
        if (timeDiff > 0) {
          // Calculate vertical speed if not already set
          if (verticalSpeed == null) {
            verticalSpeed = (point.altitude - prev.altitude) / timeDiff;
          }
          
          // Calculate horizontal speed if not already set (from coordinate distance)
          if (speed == null) {
            final horizontalDistanceM = _haversineDistance(
              prev.latitude,
              prev.longitude,
              point.latitude,
              point.longitude,
            );
            // Convert m/s from: meters / seconds
            speed = horizontalDistanceM / timeDiff;
          }
        }
      }

      result.add(TrackPoint(
        timestamp: point.timestamp,
        latitude: point.latitude,
        longitude: point.longitude,
        altitude: point.altitude,
        speed: speed,
        verticalSpeed: verticalSpeed,
        heading: point.heading,
      ));
    }

    return result;
  }

  /// Calculate haversine distance between two points in meters
  static double _haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusM = 6371000; // Earth radius in meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusM * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180;

  /// Generate sample tracklog for testing
  /// Generate a realistic paraglider tracklog for testing
  /// 
  /// Physics-based simulation:
  /// - Sink rate: -1.0 to -1.3 m/s (typical paraglider)
  /// - Horizontal speed: 20-38 km/h (5.5-10.5 m/s)
  /// - Flight time calculated from altitude drop and sink rate
  /// - Creates a scenic route (figure-8 pattern) to achieve realistic speeds
  static List<TrackPoint> generateTestTracklog({
    required double startLat,
    required double startLon,
    required double startAlt,
    required double endLat,
    required double endLon,
    required double endAlt,
    required Duration flightDuration,
    int pointsPerMinute = 6, // 10-second intervals
  }) {
    final points = <TrackPoint>[];
    
    // Physics constants for paraglider
    const double sinkRate = 1.2; // m/s (positive value, will be applied as descent)
    const double horizontalSpeed = 8.0; // m/s (~29 km/h - typical cruise speed)
    
    // Calculate realistic flight duration based on altitude drop
    final altitudeDrop = startAlt - endAlt;
    final calculatedFlightSeconds = (altitudeDrop / sinkRate).abs();
    
    // Use the longer of: provided duration or physics-calculated duration
    // Add 20 seconds for ground phases (before takeoff + after landing)
    final actualFlightSeconds = max(
      flightDuration.inSeconds.toDouble(),
      calculatedFlightSeconds + 20,
    );
    
    // Calculate total horizontal distance needed for realistic speed
    final totalHorizontalDistance = horizontalSpeed * (actualFlightSeconds - 20);
    
    // Direct distance between start and end
    final directDistance = _haversineDistance(startLat, startLon, endLat, endLon);
    
    // If direct distance is too short, create a scenic route (figure-8 or loops)
    // This makes the pilot fly around before landing at the target
    final loopRadius = (totalHorizontalDistance - directDistance) / (2 * 3.14159);
    final needsScenic = loopRadius > 50; // Need scenic route if > 50m radius needed
    
    final startTime = DateTime.now().subtract(Duration(seconds: actualFlightSeconds.toInt()));
    final totalPoints = max(24, (actualFlightSeconds / 10).toInt()); // At least 24 points, ~10s intervals
    
    // Calculate center point for scenic loops (offset from direct line)
    final midLat = (startLat + endLat) / 2;
    final midLon = (startLon + endLon) / 2;
    
    for (int i = 0; i < totalPoints; i++) {
      final progress = i / (totalPoints - 1);
      final timestamp = startTime.add(Duration(
        seconds: (actualFlightSeconds * progress).toInt(),
      ));

      double lat, lon, alt;

      if (progress < 0.05) {
        // Ground phase before takeoff - stationary
        lat = startLat;
        lon = startLon;
        alt = startAlt;
      } else if (progress < 0.10) {
        // Takeoff run - accelerating
        final phase = (progress - 0.05) / 0.05;
        lat = startLat + (endLat - startLat) * 0.02 * phase;
        lon = startLon + (endLon - startLon) * 0.02 * phase;
        alt = startAlt - altitudeDrop * 0.02 * phase; // Slight descent during launch
      } else if (progress < 0.85) {
        // Main flight phase
        final flightPhase = (progress - 0.10) / 0.75;
        
        // Linear descent at sink rate
        alt = startAlt - altitudeDrop * (0.02 + 0.88 * flightPhase);
        
        if (needsScenic && loopRadius > 100) {
          // Create figure-8 pattern for longer flights
          // This adds distance while keeping start/end points fixed
          final loopAngle = flightPhase * 4 * 3.14159; // Two complete loops
          final loopOffsetLat = (loopRadius / 111000) * (loopAngle).sin() * (1 - flightPhase);
          final loopOffsetLon = (loopRadius / 85000) * (loopAngle * 0.5).sin() * (1 - flightPhase);
          
          // Progress along direct line + scenic offset
          lat = startLat + (endLat - startLat) * (0.02 + 0.88 * flightPhase) + loopOffsetLat;
          lon = startLon + (endLon - startLon) * (0.02 + 0.88 * flightPhase) + loopOffsetLon;
        } else {
          // Direct flight for short distances
          lat = startLat + (endLat - startLat) * (0.02 + 0.88 * flightPhase);
          lon = startLon + (endLon - startLon) * (0.02 + 0.88 * flightPhase);
        }
      } else if (progress < 0.92) {
        // Final approach - converging to landing
        final approachPhase = (progress - 0.85) / 0.07;
        lat = startLat + (endLat - startLat) * (0.90 + 0.08 * approachPhase);
        lon = startLon + (endLon - startLon) * (0.90 + 0.08 * approachPhase);
        alt = endAlt + (startAlt - endAlt) * 0.10 * (1 - approachPhase) + 5;
      } else if (progress < 0.95) {
        // Flare and touchdown
        final flarePhase = (progress - 0.92) / 0.03;
        lat = startLat + (endLat - startLat) * (0.98 + 0.02 * flarePhase);
        lon = startLon + (endLon - startLon) * (0.98 + 0.02 * flarePhase);
        alt = endAlt + 5 * (1 - flarePhase);
      } else {
        // STATIONARY ON GROUND - essential for landing detection
        // ~5% of flight = sufficient for 10-second landing confirmation
        lat = endLat;
        lon = endLon;
        alt = endAlt;
      }

      points.add(TrackPoint(
        timestamp: timestamp,
        latitude: lat,
        longitude: lon,
        altitude: alt,
      ));
    }

    return _calculateVerticalSpeeds(points);
  }

  /// Simulate thermal activity for test data
  static double _simulateThermal(double phase) {
    // Simple sine wave to simulate thermal climbing
    return (phase * 10 * 3.14159).sin();
  }
}

/// Supported tracklog formats
enum TracklogFormat {
  gpx,
  igc,
  kml,
  json,
}

// Extension for sin function on double
extension MathExtension on double {
  double sin() => _sin(this);
}

double _sin(double x) {
  // Taylor series approximation for sin
  x = x % (2 * 3.14159265359);
  double result = 0;
  double term = x;
  for (int i = 1; i < 10; i++) {
    result += term;
    term *= -x * x / ((2 * i) * (2 * i + 1));
  }
  return result;
}
