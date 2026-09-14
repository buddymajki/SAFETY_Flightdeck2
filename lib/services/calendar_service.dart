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

  /// Events whose registrations have been fetched, and those being fetched now.
  final Set<String> _loadedRegistrations = {};
  final Set<String> _loadingRegistrations = {};

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

      // Registrations live in a subcollection, so each event costs its own
      // query and a school can have hundreds of events. Prefetch only what the
      // calendar shows first (upcoming events); older events load on demand
      // through ensureRegistrationsLoaded().
      final horizon = DateTime.now().subtract(const Duration(days: 1));
      for (final event in _events) {
        if (event.startTime.isBefore(horizon)) continue;
        unawaited(ensureRegistrationsLoaded(event.id));
      }

      notifyListeners();
    }, onError: (e) {
      debugPrint('[CalendarService] Error listening to events: $e');
    });
  }

  /// Loads an event's registrations once. Safe to call from build().
  Future<void> ensureRegistrationsLoaded(String eventId) async {
    if (_loadedRegistrations.contains(eventId)) return;
    await _loadRegistrations(eventId);
  }

  Future<void> _loadRegistrations(String eventId) async {
    if (_schoolId == null) return;
    if (!_loadingRegistrations.add(eventId)) return; // already in flight

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

      _loadedRegistrations.add(eventId);
      notifyListeners();
    } catch (e) {
      debugPrint('[CalendarService] Error loading registrations for $eventId: $e');
    } finally {
      _loadingRegistrations.remove(eventId);
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
  /// Registers the current user. Only the display name is stored: the school
  /// admin can reach the student through their uid, so the registration list
  /// does not need to carry e-mail addresses.
  Future<void> register(String eventId, {required String name, String? note}) async {
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
      'registeredAt': FieldValue.serverTimestamp(),
      'status': 'registered',
      'note': note,
    });

    _myRegistrations[eventId] = true;
    _loadedRegistrations.remove(eventId);
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
    _loadedRegistrations.remove(eventId);
    await _loadRegistrations(eventId);
    notifyListeners();
  }

  /// Reset service on logout.
  void resetService() {
    _eventsSubscription?.cancel();
    _events = [];
    _registrations.clear();
    _myRegistrations.clear();
    _loadedRegistrations.clear();
    _loadingRegistrations.clear();
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
