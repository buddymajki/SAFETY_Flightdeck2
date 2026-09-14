// Unit tests for the Flight model parsing.
//
// The Firestore flightlog contains data written by three generations of tooling
// (the app, migrate_flights.js and import.js), so the parser has to accept mixed
// types. A type error inside Flight.fromFirestore blanks the whole Flight Book.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flightdeck_firebase/models/flight.dart';

void main() {
  group('Flight.fromFirestore', () {
    test('parses an app-written flight (Timestamp date, numeric fields)', () {
      final flight = Flight.fromFirestore({
        'date': Timestamp.fromDate(DateTime.utc(2026, 3, 1)),
        'takeoffName': 'Büelen',
        'takeoffAltitude': 1089.0,
        'landingName': 'Neufallenbach',
        'landingAltitude': 545,
        'altitudeDifference': 544.0,
        'flightTimeMinutes': 20,
        'license_type': 'Student',
        'status': 'accepted',
        'glider_id': 'abc',
        'glider_display_name': 'Eiko 2 (Supair)',
      }, 'doc1', 'uid1');

      expect(flight.id, 'doc1');
      expect(flight.flightTimeMinutes, 20);
      expect(flight.landingAltitude, 545.0);
      expect(flight.gliderId, 'abc');
      expect(DateTime.parse(flight.date).year, 2026);
    });

    test('reads the migrated "flightTypeMinutes" typo and string numbers', () {
      final flight = Flight.fromFirestore({
        'date': '2025-09-28T00:00:00Z',
        'takeoffName': 'Haldi',
        'takeoffAltitude': '1100',
        'landingName': 'Schattdorf',
        'landingAltitude': '485',
        'altitudeDifference': '615',
        'flightTypeMinutes': 42,
        'license_type': 'Student',
        'status': 'accepted',
      }, 'doc2', 'uid1');

      expect(flight.flightTimeMinutes, 42);
      expect(flight.altitudeDifference, 615.0);
      expect(flight.takeoffAltitude, 1100.0);
      expect(DateTime.parse(flight.date).month, 9);
    });

    test('never throws on odd minute values', () {
      expect(Flight.fromFirestore({'flightTimeMinutes': 12.6}, 'a', 'u').flightTimeMinutes, 13);
      expect(Flight.fromFirestore({'flightTimeMinutes': '15'}, 'b', 'u').flightTimeMinutes, 15);
      expect(Flight.fromFirestore({'flightTimeMinutes': 'n/a'}, 'c', 'u').flightTimeMinutes, 0);
      expect(Flight.fromFirestore({}, 'd', 'u').flightTimeMinutes, 0);
    });
  });

  group('Flight.copyWith', () {
    test('keeps every field that is not overridden', () {
      final original = Flight(
        id: 'x',
        studentUid: 'u',
        mainSchoolId: 's',
        thisFlightSchoolId: 's',
        date: DateTime(2026, 1, 1).toIso8601String(),
        takeoffName: 'A',
        takeoffAltitude: 1000,
        landingName: 'B',
        landingAltitude: 500,
        altitudeDifference: 500,
        flightTimeMinutes: 10,
        licenseType: 'Student',
        gpsTracked: true,
        gliderId: 'g1',
        gliderDisplayName: 'Glider 1',
      );

      final copy = original.copyWith(id: 'y', status: 'pending');

      expect(copy.id, 'y');
      expect(copy.gpsTracked, isTrue);
      expect(copy.gliderId, 'g1');
      expect(copy.gliderDisplayName, 'Glider 1');
      expect(copy.takeoffName, 'A');
    });
  });
}
