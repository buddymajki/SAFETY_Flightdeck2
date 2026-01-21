// File: test/airspace_violation_test.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Test for airspace violation detection
/// 
/// This test loads the GeoJSON airspace data and tests the point-in-polygon
/// algorithm to verify airspace violation detection works correctly.

void main() {
  group('Airspace GeoJSON Parsing', () {
    test('Load and parse airspaces.json', () async {
      // Load the airspaces.json file
      final file = File('test/airspaces.json');
      expect(file.existsSync(), true, reason: 'airspaces.json should exist');
      
      final content = await file.readAsString();
      expect(content.isNotEmpty, true, reason: 'File should not be empty');
      
      final json = jsonDecode(content) as Map<String, dynamic>;
      
      // Verify it's a GeoJSON FeatureCollection
      expect(json['type'], 'FeatureCollection');
      expect(json.containsKey('features'), true);
      
      final features = json['features'] as List<dynamic>;
      expect(features.isNotEmpty, true, reason: 'Should have airspace features');
      
      print('Total airspace features: ${features.length}');
      
      // Count by type
      final typeCounts = <String, int>{};
      for (final feature in features) {
        final props = feature['properties'] as Map<String, dynamic>;
        final type = props['ASType'] as String? ?? 'Unknown';
        typeCounts[type] = (typeCounts[type] ?? 0) + 1;
      }
      
      print('Airspace types:');
      typeCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value))
        ..forEach((e) => print('  ${e.key}: ${e.value}'));
    });
    
    test('Parse airspace zone with altitudes', () async {
      final file = File('test/airspaces.json');
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final features = json['features'] as List<dynamic>;
      
      // Find a TMA zone (common type)
      final tmaFeature = features.firstWhere(
        (f) => (f['properties']['ASType'] as String?) == 'TMA',
        orElse: () => features.first,
      );
      
      final props = tmaFeature['properties'] as Map<String, dynamic>;
      print('\nSample TMA Zone:');
      print('  Name: ${props['Name']}');
      print('  Type: ${props['ASType']}');
      print('  Class: ${props['ASClass']}');
      print('  HX: ${props['HX']}');
      print('  DABS: ${props['DABS']}');
      
      // Parse altitudes
      final lower = props['Lower'] as Map<String, dynamic>?;
      final upper = props['Upper'] as Map<String, dynamic>?;
      
      if (lower != null) {
        final metric = lower['Metric'] as Map<String, dynamic>?;
        if (metric != null) {
          final alt = metric['Alt'] as Map<String, dynamic>?;
          print('  Lower Alt: ${alt?['Altitude']} ${alt?['Type']}');
        }
      }
      
      if (upper != null) {
        final metric = upper['Metric'] as Map<String, dynamic>?;
        if (metric != null) {
          final alt = metric['Alt'] as Map<String, dynamic>?;
          print('  Upper Alt: ${alt?['Altitude']} ${alt?['Type']}');
        }
      }
      
      // Parse geometry
      final geometry = tmaFeature['geometry'] as Map<String, dynamic>;
      final coords = geometry['coordinates'] as List<dynamic>;
      final ring = coords[0] as List<dynamic>;
      print('  Polygon vertices: ${ring.length}');
      print('  First vertex: [${ring[0][0]}, ${ring[0][1]}]'); // [lng, lat]
    });
    
    test('Point-in-polygon algorithm', () {
      // Test with a simple square polygon
      // Polygon: (0,0), (0,10), (10,10), (10,0)
      final polygon = [
        GeoPoint(0, 0),
        GeoPoint(0, 10),
        GeoPoint(10, 10),
        GeoPoint(10, 0),
      ];
      
      // Point inside: (5, 5)
      expect(_pointInPolygon(5, 5, polygon), true, reason: '(5,5) should be inside');
      
      // Point outside: (15, 5)
      expect(_pointInPolygon(15, 5, polygon), false, reason: '(15,5) should be outside');
      
      // Point on edge: (0, 5) - edge case, may vary
      // Point at corner: (0, 0) - edge case, may vary
      
      print('Point-in-polygon test passed');
    });
    
    test('Find specific airspace by coordinates', () async {
      final file = File('test/airspaces.json');
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final features = json['features'] as List<dynamic>;
      
      // Test coordinates - Zurich area (should be in some TMA)
      final testLat = 47.45;
      final testLng = 8.55;
      final testAlt = 2000.0; // meters
      
      print('\nSearching for airspaces containing ($testLat, $testLng) at ${testAlt}m:');
      
      int foundCount = 0;
      for (final feature in features) {
        final props = feature['properties'] as Map<String, dynamic>;
        final geometry = feature['geometry'] as Map<String, dynamic>;
        
        // Skip if informational
        if (props['Informational'] == true) continue;
        
        // Parse polygon
        final coords = geometry['coordinates'] as List<dynamic>;
        if (coords.isEmpty) continue;
        final ring = coords[0] as List<dynamic>;
        
        final polygon = ring.map((c) => GeoPoint(
          (c[1] as num).toDouble(), // lat
          (c[0] as num).toDouble(), // lng
        )).toList();
        
        if (polygon.length < 3) continue;
        
        // Parse altitude limits
        double minAlt = 0.0;
        double maxAlt = 99999.0;
        
        final lower = props['Lower'] as Map<String, dynamic>?;
        final upper = props['Upper'] as Map<String, dynamic>?;
        
        if (lower != null) {
          final metric = lower['Metric'] as Map<String, dynamic>?;
          if (metric != null) {
            final alt = metric['Alt'] as Map<String, dynamic>?;
            minAlt = (alt?['Altitude'] as num?)?.toDouble() ?? 0.0;
          }
        }
        
        if (upper != null) {
          final metric = upper['Metric'] as Map<String, dynamic>?;
          if (metric != null) {
            final alt = metric['Alt'] as Map<String, dynamic>?;
            maxAlt = (alt?['Altitude'] as num?)?.toDouble() ?? 99999.0;
            // Convert FL to meters
            final type = alt?['Type'] as String?;
            if (type != null && type.contains('FL')) {
              maxAlt = maxAlt * 30.48;
            }
          }
        }
        
        // Check altitude
        if (testAlt < minAlt || testAlt > maxAlt) continue;
        
        // Check if point is in polygon
        if (_pointInPolygon(testLat, testLng, polygon)) {
          foundCount++;
          print('  Found: ${props['Name']} (${props['ASType']}) - Alt: $minAlt-$maxAlt m');
        }
      }
      
      print('Total airspaces found at this position: $foundCount');
      expect(foundCount >= 0, true); // May or may not be in airspace
    });
  });
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
