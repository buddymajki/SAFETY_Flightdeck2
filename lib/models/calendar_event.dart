// File: lib/models/calendar_event.dart

import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a school calendar event (synced from Google Calendar to Firestore).
class CalendarEvent {
  final String id;
  final String title;
  final String description;
  final String location;
  final DateTime startTime;
  final DateTime? endTime;
  final String status; // 'active' | 'cancelled'
  final String source; // 'google_calendar' | 'manual'
  final String? gcalId;
  final DateTime? updatedAt;

  CalendarEvent({
    required this.id,
    required this.title,
    this.description = '',
    this.location = '',
    required this.startTime,
    this.endTime,
    this.status = 'active',
    this.source = 'google_calendar',
    this.gcalId,
    this.updatedAt,
  });

  factory CalendarEvent.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return CalendarEvent(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      location: data['location'] ?? '',
      startTime: _parseDateTime(data['startTime']) ?? DateTime.now(),
      endTime: _parseDateTime(data['endTime']),
      status: data['status'] ?? 'active',
      source: data['source'] ?? 'google_calendar',
      gcalId: data['gcalId'],
      updatedAt: _parseDateTime(data['updatedAt']),
    );
  }

  /// Parses a Firestore field that could be a Timestamp or an ISO8601 string.
  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  bool get isActive => status == 'active';
  bool get isCancelled => status == 'cancelled';
  bool get isPast => startTime.isBefore(DateTime.now());

  /// Duration of the event in a human-friendly format.
  String get durationText {
    if (endTime == null) return '';
    final diff = endTime!.difference(startTime);
    if (diff.inHours > 0) {
      return '${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
    }
    return '${diff.inMinutes}m';
  }

  @override
  String toString() => 'CalendarEvent($id, $title, $startTime)';
}

/// Represents a single user's registration for an event.
class EventRegistration {
  final String uid;
  final String name;
  final String email;
  final DateTime registeredAt;
  final String status; // 'registered' | 'cancelled'
  final String? note;

  EventRegistration({
    required this.uid,
    required this.name,
    this.email = '',
    required this.registeredAt,
    this.status = 'registered',
    this.note,
  });

  factory EventRegistration.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return EventRegistration(
      uid: doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      registeredAt: (data['registeredAt'] is Timestamp)
          ? (data['registeredAt'] as Timestamp).toDate()
          : DateTime.now(),
      status: data['status'] ?? 'registered',
      note: data['note'],
    );
  }

  bool get isRegistered => status == 'registered';
}
