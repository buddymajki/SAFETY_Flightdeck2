import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class UserDataService extends ChangeNotifier {
  String? _uid;
  String? get uid => _uid;
  // NOTE: the flightlog subcollection is owned by FlightService, which keeps a
  // realtime stream of it. Reading it here as well doubled the Firestore reads
  // on every login for a copy nothing consumed.
  List<Map<String, dynamic>> checklistprogress = const [];
  // Map of itemId -> { completed: bool, completedAt: DateTime? }
  Map<String, Map<String, dynamic>> _userChecklistProgress = const {};
  
  // Callback for stats updates (set by external service)
  Function()? onChecklistDataChanged;

  bool _initialized = false;
  bool get isInitialized => _initialized && _uid != null;

  Future<void> initializeData(String uid) async {
    _uid = uid;
    final fs = FirebaseFirestore.instance;
    try {
      final opts = const GetOptions(source: Source.serverAndCache);

      final userRef = fs.collection('users').doc(uid);

      final checklistDoc =
          await userRef.collection('checklistprogress').doc('progress').get(opts);
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

      log('[UserDataService] Loaded for uid=$uid: checklist=${_userChecklistProgress.length}');
    } catch (e, st) {
      if (kDebugMode) {
        log('[UserDataService] initializeData error: $e', stackTrace: st);
      }
      rethrow;
    }
  }

  void resetService() {
    _uid = null;
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
    
    // Trigger stats update
    onChecklistDataChanged?.call();
  }
}
