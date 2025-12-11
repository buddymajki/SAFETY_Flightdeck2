import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class UserDataService extends ChangeNotifier {
  String? _uid;
  String? get uid => _uid;

  Map<String, dynamic>? profile;
  List<Map<String, dynamic>> flightlog = const [];
  List<Map<String, dynamic>> checklistprogress = const [];
  // Map of itemId -> { completed: bool, completedAt: DateTime? }
  Map<String, Map<String, dynamic>> _userChecklistProgress = const {};

  bool _initialized = false;
  bool get isInitialized => _initialized && _uid != null;

  Future<void> initializeData(String uid) async {
    _uid = uid;
    final fs = FirebaseFirestore.instance;
    try {
      final opts = const GetOptions(source: Source.serverAndCache);

      final userRef = fs.collection('users').doc(uid);

      final results = await Future.wait([
        userRef.get(opts),
        userRef.collection('flightlog').orderBy('date', descending: true).get(opts),
        userRef.collection('checklistprogress').doc('progress').get(opts),
      ]);

      final profileSnap = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      profile = profileSnap.data() != null
          ? {'id': profileSnap.id, ...profileSnap.data()!}
          : <String, dynamic>{'id': profileSnap.id};

      final flightlogSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;
      flightlog = flightlogSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList();

      final checklistDoc = results[2] as DocumentSnapshot<Map<String, dynamic>>;
      final progressData = checklistDoc.data() ?? <String, dynamic>{};
      _userChecklistProgress = progressData.map((key, value) {
        if (value is bool) {
          // Backward compatibility: old schema { itemId: true/false }
          return MapEntry(key, {
            'completed': value,
            'completedAt': null,
          });
        }
        final v = value as Map<String, dynamic>? ?? <String, dynamic>{};
        final completed = v['completed'] as bool? ?? false;
        final ts = v['completedAt'];
        final completedAt = ts is Timestamp ? ts.toDate() : null;
        return MapEntry(key, {
          'completed': completed,
          'completedAt': completedAt,
        });
      });

      _initialized = true;
      notifyListeners();

      log('[UserDataService] Loaded for uid=$uid: flightlog=${flightlog.length}, checklist=${checklistprogress.length}');
    } catch (e, st) {
      if (kDebugMode) {
        log('[UserDataService] initializeData error: $e', stackTrace: st);
      }
      rethrow;
    }
  }

  Future<String> saveFlightLog(Map<String, dynamic> flightData) async {
    final currentUid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) {
      throw StateError('UserDataService has no uid; call initializeData first.');
    }

    final userRef = FirebaseFirestore.instance.collection('users').doc(currentUid);
    final now = FieldValue.serverTimestamp();

    final payload = {
      ...flightData,
      'createdAt': now,
      'updatedAt': now,
    };

    final ref = await userRef.collection('flightlog').add(payload);

    // Update local cache optimistically; next refresh will reconcile timestamps
    flightlog = [
      {'id': ref.id, ...flightData},
      ...flightlog,
    ];
    notifyListeners();

    return ref.id;
  }

  void resetService() {
    _uid = null;
    profile = null;
    flightlog = const [];
    checklistprogress = const [];
    _userChecklistProgress = const {};
    _initialized = false;
    notifyListeners();
  }

  Map<String, Map<String, dynamic>> get userChecklistProgress => Map.unmodifiable(_userChecklistProgress);

  bool isChecklistItemCompleted(String itemId) {
    final v = _userChecklistProgress[itemId];
    return (v != null) ? (v['completed'] as bool? ?? false) : false;
  }

    int get checklistProgressCount => _userChecklistProgress.values
      .where((v) => (v['completed'] as bool? ?? false))
      .length;

  Future<void> toggleProgress(String itemId, bool newValue) async {
    final currentUid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) {
      throw StateError('UserDataService has no uid; call initializeData first.');
    }

    // Update local cache immediately
    _userChecklistProgress = {
      ..._userChecklistProgress,
      itemId: {
        'completed': newValue,
        'completedAt': newValue ? DateTime.now() : null,
      },
    };
    notifyListeners();

    final userRef = FirebaseFirestore.instance.collection('users').doc(currentUid);
    await userRef
        .collection('checklistprogress')
        .doc('progress')
        .set({
          itemId: {
            'completed': newValue,
            'completedAt': newValue ? FieldValue.serverTimestamp() : null,
          }
        }, SetOptions(merge: true));

    // Confirm update and notify again after remote write
    notifyListeners();
  }
}
