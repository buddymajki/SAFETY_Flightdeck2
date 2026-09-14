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
  // Cache key is user-specific so a second account on the same device never sees
  // the previous user's flights while its own stream is still loading.
  static const String _flightsCacheKeyBase = 'flightbook_flights';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<Flight> _flights = [];
  bool _isLoading = false;
  String? _currentUid;
  // NOTE: _currentSchoolId is stored for potential future use in school-specific queries
  // ignore: unused_field
  String? _currentSchoolId;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _flightsSubscription;
  Completer<void>? _initializationCompleter;

  // Callback for stats updates (set by external service)
  Function()? onFlightDataChanged;

  List<Flight> get flights => List.unmodifiable(_flights);
  bool get isLoading => _isLoading;
  bool get isInitialized => _currentUid != null;

  FlightService() {
    _loadDataFromCacheOnly();
  }

  static String _cacheKeyFor(String uid) => '${_flightsCacheKeyBase}_$uid';

  // --- Cache Management ---

  Future<void> _cacheFlights(String uid, List<Flight> flights) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheable = flights.map((f) => f.toCache()).toList();
      await prefs.setString(_cacheKeyFor(uid), json.encode(cacheable));
    } catch (e) {
      debugPrint('[FlightService] Cache error: $e');
    }
  }

  Future<List<Flight>> _getFlightsFromCache(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_cacheKeyFor(uid));
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
    // Don't overwrite data that a stream delivered while the cache was loading
    if (_flights.isEmpty && cached.isNotEmpty) {
      _flights = cached;
      notifyListeners();
    }
  }

  // --- Initialization & Stream Setup ---

  Future<void> initializeData(String uid, String schoolId) async {
    // Called both by the SplashScreen and by the ChangeNotifierProxyProvider on every
    // ProfileService notification. Re-subscribing each time cancelled and recreated
    // the Firestore listener over and over; keep the existing subscription for the
    // same user and only remember the (currently unused) school id.
    if (_currentUid == uid && _flightsSubscription != null) {
      _currentSchoolId = schoolId;
      await waitForInitialData();
      return;
    }

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
        .snapshots()
        .listen(
      (snapshot) async {
        final flights = <Flight>[];
        for (var doc in snapshot.docs) {
          try {
            flights.add(Flight.fromFirestore(doc.data(), doc.id, uid));
          } catch (e) {
            // One malformed legacy document must not blank the whole Flight Book
            debugPrint('[FlightService] Skipping unparsable flight ${doc.id}: $e');
          }
        }

        // Sort by date descending (newest first), then by created_at descending for same-date flights
        flights.sort((a, b) {
          final aDate = DateTime.tryParse(a.date) ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = DateTime.tryParse(b.date) ?? DateTime.fromMillisecondsSinceEpoch(0);
          final dateComparison = bDate.compareTo(aDate);
          if (dateComparison != 0) {
            return dateComparison;
          }
          // If dates are equal, sort by created_at descending (newer created_at first)
          final aCreatedAt = a.createdAt ?? DateTime.now();
          final bCreatedAt = b.createdAt ?? DateTime.now();
          return bCreatedAt.compareTo(aCreatedAt);
        });

        _flights = flights;
        await _cacheFlights(uid, _flights);

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

  // --- Flight Operations ---

  /// Add a new flight (offline-first)
  Future<String> addFlight(Flight flight) async {
    final uid = _currentUid ?? _auth.currentUser?.uid;
    if (uid == null) throw StateError('User not authenticated');

    // Generate temporary ID and mark as pending. copyWith keeps every field the form
    // filled in (glider, gpsTracked, ...) - rebuilding the object by hand used to drop
    // the selected glider, so glider_id was always null in Firestore.
    final tempId = _firestore.collection('flights').doc().id;
    final now = DateTime.now();
    final flightWithId = flight.copyWith(
      id: tempId,
      studentUid: uid,
      status: 'pending',
      createdAt: now,
      updatedAt: now,
      isPendingUpload: true,
    );

    debugPrint('[FlightService] addFlight: gpsTracked=${flightWithId.gpsTracked}, glider=${flightWithId.gliderId}');

    // Optimistic cache update
    _flights.insert(0, flightWithId);
    await _cacheFlights(uid, _flights);
    notifyListeners();

    // Trigger stats update from the optimistic state
    onFlightDataChanged?.call();

    // Background sync (only write to user's flightlog collection).
    // NOT awaited: with offline persistence the write future only completes once the
    // server acknowledges it, which blocked the form's spinner forever while offline.
    // Firestore queues the write locally and delivers it when the device is online.
    final serverNow = FieldValue.serverTimestamp();
    final payload = {
      ...flightWithId.toFirestore(),
      'created_at': serverNow,
      'updated_at': serverNow,
    };
    unawaited(_firestore
        .collection('users')
        .doc(uid)
        .collection('flightlog')
        .doc(tempId)
        .set(payload)
        .then((_) => log('[FlightService] Flight added: $tempId'))
        .catchError((e) => debugPrint('[FlightService] Background sync error: $e')));

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

    // Optimistic cache update (copyWith keeps glider / gpsTracked intact)
    final localFlight = updatedFlight.copyWith(
      studentUid: uid,
      updatedAt: DateTime.now(),
      isPendingUpload: false,
    );

    _flights[index] = localFlight;
    await _cacheFlights(uid, _flights);
    notifyListeners();
    onFlightDataChanged?.call();

    // Background sync (only write to user's flightlog collection) - not awaited, see addFlight
    patch['updated_at'] = FieldValue.serverTimestamp();
    unawaited(_firestore
        .collection('users')
        .doc(uid)
        .collection('flightlog')
        .doc(localFlight.id)
        .update(patch)
        .then((_) => log('[FlightService] Flight updated: ${localFlight.id}'))
        .catchError((e) => debugPrint('[FlightService] Update sync error: $e')));
  }

  /// Delete a flight (offline-first)
  Future<void> deleteFlight(String flightId) async {
    final uid = _currentUid ?? _auth.currentUser?.uid;
    if (uid == null) throw StateError('User not authenticated');

    // Optimistic cache removal
    _flights.removeWhere((f) => f.id == flightId);
    await _cacheFlights(uid, _flights);
    notifyListeners();
    onFlightDataChanged?.call();

    // Background sync (only delete from user's flightlog collection) - not awaited, see addFlight
    unawaited(_firestore
        .collection('users')
        .doc(uid)
        .collection('flightlog')
        .doc(flightId)
        .delete()
        .then((_) => log('[FlightService] Flight deleted: $flightId'))
        .catchError((e) => debugPrint('[FlightService] Delete sync error: $e')));
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

  Future<void> waitForInitialData() async {
    if (_initializationCompleter == null) return;
    await _initializationCompleter!.future;
  }

  void resetService() {
    final uid = _currentUid;
    _flightsSubscription?.cancel();
    _flightsSubscription = null;
    _flights = [];
    _isLoading = false;
    _currentUid = null;
    _currentSchoolId = null;
    _initializationCompleter = null;
    if (uid != null) {
      // Remove the signed-out user's flights from the device cache
      SharedPreferences.getInstance()
          .then((prefs) => prefs.remove(_cacheKeyFor(uid)))
          .catchError((e) {
        debugPrint('[FlightService] Cache clear error: $e');
        return false;
      });
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _flightsSubscription?.cancel();
    super.dispose();
  }
}
