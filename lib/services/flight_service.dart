// File: lib/services/flight_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/flight.dart';

class FlightService extends ChangeNotifier {
  static const String _flightsCacheKey = 'flightbook_flights';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<Flight> _flights = [];
  bool _isLoading = false;
  String? _currentUid;
  String? _currentSchoolId;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _flightsSubscription;
  Completer<void>? _initializationCompleter;

  List<Flight> get flights => List.unmodifiable(_flights);
  bool get isLoading => _isLoading;
  bool get isInitialized => _currentUid != null;

  FlightService() {
    _loadDataFromCacheOnly();
  }

  // --- Cache Management ---

  Future<void> _cacheFlights(List<Flight> flights) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheable = flights.map((f) => f.toCache()).toList();
      await prefs.setString(_flightsCacheKey, json.encode(cacheable));
    } catch (e) {
      debugPrint('[FlightService] Cache error: $e');
    }
  }

  Future<List<Flight>> _getFlightsFromCache(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_flightsCacheKey);
      if (jsonString != null) {
        final List<dynamic> decoded = json.decode(jsonString);
        return decoded
            .map((item) => Flight.fromCache(item as Map<String, dynamic>, uid))
            .toList();
      }
    } catch (e) {
      debugPrint('[FlightService] Cache read error: $e');
    }
    return [];
  }

  Future<void> _loadDataFromCacheOnly() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final cached = await _getFlightsFromCache(uid);
    _flights = cached;
  }

  // --- Initialization & Stream Setup ---

  Future<void> initializeData(String uid, String schoolId) async {
    _isLoading = true;
    _currentUid = uid;
    _currentSchoolId = schoolId;

    notifyListeners();

    _initializationCompleter = Completer<void>();

    await _flightsSubscription?.cancel();

    _flightsSubscription = _firestore
        .collection('users')
        .doc(uid)
        .collection('flightlog')
        .orderBy('date', descending: true)
        .orderBy('created_at', descending: false)
        .snapshots()
        .listen(
      (snapshot) async {
        final flights = <Flight>[];
        for (var doc in snapshot.docs) {
          final flight = Flight.fromFirestore(doc.data(), doc.id, uid);
          flights.add(flight);
        }

        _flights = flights;
        await _cacheFlights(_flights);

        _isLoading = false;
        notifyListeners();

        if (_initializationCompleter != null && !_initializationCompleter!.isCompleted) {
          _initializationCompleter!.complete();
        }

        log('[FlightService] Loaded ${flights.length} flights for $uid');
      },
      onError: (e) {
        debugPrint('[FlightService] Stream error: $e');
        _isLoading = false;
        notifyListeners();
        if (_initializationCompleter != null && !_initializationCompleter!.isCompleted) {
          _initializationCompleter!.complete();
        }
      },
    );

    // Wait a bit for first event from stream
    await Future.delayed(const Duration(milliseconds: 500));
  }

  Future<void> waitForInitialData() async {
    if (_initializationCompleter == null) return;
    await _initializationCompleter!.future;
  }

  // --- Flight Operations ---

  /// Add a new flight (offline-first)
  Future<String> addFlight(Flight flight) async {
    final uid = _currentUid ?? _auth.currentUser?.uid;
    if (uid == null) throw StateError('User not authenticated');

    // Generate temporary ID and mark as pending
    final tempId = _firestore.collection('flights').doc().id;
    final flightWithId = Flight(
      id: tempId,
      studentUid: uid,
      schoolId: flight.schoolId,
      date: flight.date,
      takeoffName: flight.takeoffName,
      takeoffId: flight.takeoffId,
      takeoffAltitude: flight.takeoffAltitude,
      landingName: flight.landingName,
      landingId: flight.landingId,
      landingAltitude: flight.landingAltitude,
      altitudeDifference: flight.altitudeDifference,
      flightTimeMinutes: flight.flightTimeMinutes,
      comment: flight.comment,
      flightTypeId: flight.flightTypeId,
      advancedManeuvers: flight.advancedManeuvers,
      schoolManeuvers: flight.schoolManeuvers,
      licenseType: flight.licenseType,
      status: 'pending',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isPendingUpload: true,
    );

    // Optimistic cache update
    _flights.insert(0, flightWithId);
    await _cacheFlights(_flights);
    notifyListeners();

    // Background sync (only write to user's flightlog collection)
    try {
      final now = FieldValue.serverTimestamp();
      final payload = {
        ...flightWithId.toFirestore(),
        'created_at': now,
        'updated_at': now,
      };

      // Write ONLY to user flightlog
      // Cloud Functions will handle cross-user and school processing
      await _firestore.collection('users').doc(uid).collection('flightlog').doc(tempId).set(payload);

      log('[FlightService] Flight added: $tempId');
    } catch (e) {
      debugPrint('[FlightService] Background sync error: $e');
      // Keep in cache even if sync fails
    }

    return tempId;
  }

  /// Update an existing flight (offline-first)
  Future<void> updateFlight(Flight updatedFlight) async {
    final uid = _currentUid ?? _auth.currentUser?.uid;
    if (uid == null) throw StateError('User not authenticated');

    final index = _flights.indexWhere((f) => f.id == updatedFlight.id);
    if (index == -1) throw StateError('Flight not found');

    final originalFlight = _flights[index];
    final patch = updatedFlight.getPatch(originalFlight);

    if (patch.isEmpty) {
      debugPrint('[FlightService] No changes detected');
      return;
    }

    // Optimistic cache update
    updatedFlight = Flight(
      id: updatedFlight.id,
      studentUid: uid,
      schoolId: updatedFlight.schoolId,
      date: updatedFlight.date,
      takeoffName: updatedFlight.takeoffName,
      takeoffId: updatedFlight.takeoffId,
      takeoffAltitude: updatedFlight.takeoffAltitude,
      landingName: updatedFlight.landingName,
      landingId: updatedFlight.landingId,
      landingAltitude: updatedFlight.altitudeDifference,
      altitudeDifference: updatedFlight.altitudeDifference,
      flightTimeMinutes: updatedFlight.flightTimeMinutes,
      comment: updatedFlight.comment,
      flightTypeId: updatedFlight.flightTypeId,
      advancedManeuvers: updatedFlight.advancedManeuvers,
      schoolManeuvers: updatedFlight.schoolManeuvers,
      licenseType: updatedFlight.licenseType,
      status: updatedFlight.status,
      createdAt: updatedFlight.createdAt,
      updatedAt: DateTime.now(),
      isPendingUpload: false,
    );

    _flights[index] = updatedFlight;
    await _cacheFlights(_flights);
    notifyListeners();

    // Background sync (only write to user's flightlog collection)
    try {
      patch['updated_at'] = FieldValue.serverTimestamp();

      // Update ONLY in user flightlog
      // Cloud Functions will handle cross-user and school processing
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('flightlog')
          .doc(updatedFlight.id)
          .update(patch);

      log('[FlightService] Flight updated: ${updatedFlight.id}');
    } catch (e) {
      debugPrint('[FlightService] Update sync error: $e');
    }
  }

  /// Delete a flight (offline-first)
  Future<void> deleteFlight(String flightId) async {
    final uid = _currentUid ?? _auth.currentUser?.uid;
    if (uid == null) throw StateError('User not authenticated');

    // Optimistic cache removal
    _flights.removeWhere((f) => f.id == flightId);
    await _cacheFlights(_flights);
    notifyListeners();

    // Background sync (only delete from user's flightlog collection)
    try {
      // Delete ONLY from user flightlog
      // Cloud Functions will handle cross-user and school cleanup
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('flightlog')
          .doc(flightId)
          .delete();

      log('[FlightService] Flight deleted: $flightId');
    } catch (e) {
      debugPrint('[FlightService] Delete sync error: $e');
    }
  }

  /// Get a flight by ID
  Flight? getFlightById(String flightId) {
    try {
      return _flights.firstWhere((f) => f.id == flightId);
    } catch (_) {
      return null;
    }
  }

  // --- Utility ---

  void resetService() {
    _flightsSubscription?.cancel();
    _flights = [];
    _isLoading = false;
    _currentUid = null;
    _currentSchoolId = null;
    _initializationCompleter = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _flightsSubscription?.cancel();
    super.dispose();
  }
}
