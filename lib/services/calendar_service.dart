// File: lib/services/calendar_service.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/calendar_event.dart';

/// Service for managing school calendar events and registrations.
///
/// Events are synced from Google Calendar → Firestore by a Cloud Function.
/// This service reads from Firestore and manages student registrations.
class CalendarService extends ChangeNotifier {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  String? _schoolId;
  String? _uid;
  bool _initialized = false;
  bool get isInitialized => _initialized;

  List<CalendarEvent> _events = [];
  List<CalendarEvent> get events => _events;

  /// Map of eventId → list of registrations
  final Map<String, List<EventRegistration>> _registrations = {};

  /// Map of eventId → whether the current user is registered
  final Map<String, bool> _myRegistrations = {};

  StreamSubscription? _eventsSubscription;

  /// Initialize with school ID and current user UID.
  void initialize(String? schoolId, String? uid) {
    if (schoolId == null || schoolId.isEmpty || uid == null) {
      _initialized = false;
      return;
    }
    // Avoid re-initializing if already watching the same school
    if (_schoolId == schoolId && _uid == uid && _initialized) return;

    _schoolId = schoolId;
    _uid = uid;
    _initialized = true;

    _listenToEvents();
  }

  void _listenToEvents() {
    _eventsSubscription?.cancel();

    if (_schoolId == null) return;

    _eventsSubscription = _fs
        .collection('schools')
        .doc(_schoolId)
        .collection('events')
        .orderBy('startTime', descending: false)
        .snapshots()
        .listen((snapshot) {
      _events = snapshot.docs
          .map((doc) => CalendarEvent.fromFirestore(doc))
          .where((e) => e.isActive) // Only show active events
          .toList();

      // Load registrations for each event
      for (final event in _events) {
        _loadRegistrations(event.id);
      }

      notifyListeners();
    }, onError: (e) {
      debugPrint('[CalendarService] Error listening to events: $e');
    });
  }

  Future<void> _loadRegistrations(String eventId) async {
    if (_schoolId == null) return;

    try {
      final snap = await _fs
          .collection('schools')
          .doc(_schoolId)
          .collection('events')
          .doc(eventId)
          .collection('registrations')
          .where('status', isEqualTo: 'registered')
          .get();

      _registrations[eventId] =
          snap.docs.map((d) => EventRegistration.fromFirestore(d)).toList();

      _myRegistrations[eventId] =
          _registrations[eventId]?.any((r) => r.uid == _uid && r.isRegistered) ?? false;

      notifyListeners();
    } catch (e) {
      debugPrint('[CalendarService] Error loading registrations for $eventId: $e');
    }
  }

  /// Get upcoming events (today and future).
  List<CalendarEvent> get upcomingEvents {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _events.where((e) => !e.startTime.isBefore(today)).toList();
  }

  /// Get events for a specific day.
  List<CalendarEvent> eventsForDay(DateTime day) {
    return _events.where((e) {
      return e.startTime.year == day.year &&
          e.startTime.month == day.month &&
          e.startTime.day == day.day;
    }).toList();
  }

  /// Get the set of days that have events (for calendar markers).
  Set<DateTime> get eventDays {
    return _events
        .map((e) => DateTime(e.startTime.year, e.startTime.month, e.startTime.day))
        .toSet();
  }

  /// Number of active registrations for a given event.
  int registrationCount(String eventId) {
    return _registrations[eventId]?.length ?? 0;
  }

  /// List of registrations for a given event.
  List<EventRegistration> getRegistrations(String eventId) {
    return _registrations[eventId] ?? [];
  }

  /// Whether the current user is registered for an event.
  bool isRegistered(String eventId) {
    return _myRegistrations[eventId] ?? false;
  }

  /// Register the current user for an event.
  Future<void> register(String eventId, {required String name, String email = '', String? note}) async {
    if (_schoolId == null || _uid == null) return;

    await _fs
        .collection('schools')
        .doc(_schoolId)
        .collection('events')
        .doc(eventId)
        .collection('registrations')
        .doc(_uid)
        .set({
      'uid': _uid,
      'name': name,
      'email': email,
      'registeredAt': FieldValue.serverTimestamp(),
      'status': 'registered',
      'note': note,
    });

    _myRegistrations[eventId] = true;
    await _loadRegistrations(eventId);
    notifyListeners();
  }

  /// Unregister the current user from an event.
  Future<void> unregister(String eventId) async {
    if (_schoolId == null || _uid == null) return;

    await _fs
        .collection('schools')
        .doc(_schoolId)
        .collection('events')
        .doc(eventId)
        .collection('registrations')
        .doc(_uid)
        .update({'status': 'cancelled'});

    _myRegistrations[eventId] = false;
    await _loadRegistrations(eventId);
    notifyListeners();
  }

  /// Reset service on logout.
  void resetService() {
    _eventsSubscription?.cancel();
    _events = [];
    _registrations.clear();
    _myRegistrations.clear();
    _schoolId = null;
    _uid = null;
    _initialized = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _eventsSubscription?.cancel();
    super.dispose();
  }
}
