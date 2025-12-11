import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class GlobalDataService extends ChangeNotifier {
  List<Map<String, dynamic>>? globalChecklists;
  List<Map<String, dynamic>>? globalFlighttypes;
  List<Map<String, dynamic>>? globalLocations;
  List<Map<String, dynamic>>? globalManeuverlist;
  List<Map<String, dynamic>>? globalSchoolmaneuvers;
  List<Map<String, dynamic>>? schools;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> initializeData() async {
    final fs = FirebaseFirestore.instance;
    try {
      final opts = const GetOptions(source: Source.serverAndCache);

      final results = await Future.wait([
        fs.collection('globalChecklists').get(opts),
        fs.collection('globalFlighttypes').get(opts),
        fs.collection('globalLocations').get(opts),
        fs.collection('globalManeuverlist').get(opts),
        fs.collection('globalSchoolmaneuvers').get(opts),
        fs.collection('schools').get(opts),
      ]);

      globalChecklists = results[0].docs.map((d) => _withId(d)).toList();
      globalFlighttypes = results[1].docs.map((d) => _withId(d)).toList();
      globalLocations = results[2].docs.map((d) => _withId(d)).toList();
      globalManeuverlist = results[3].docs.map((d) => _withId(d)).toList();
      globalSchoolmaneuvers = results[4].docs.map((d) => _withId(d)).toList();
      schools = results[5].docs.map((d) => _withId(d)).toList();

      _initialized = true;
      notifyListeners();

      log('[GlobalDataService] Loaded: checklists=${globalChecklists?.length ?? 0}, flighttypes=${globalFlighttypes?.length ?? 0}');
    } catch (e, st) {
      if (kDebugMode) {
        log('[GlobalDataService] initializeData error: $e', stackTrace: st);
      }
      rethrow;
    }
  }

  void resetService() {
    globalChecklists = null;
    globalFlighttypes = null;
    globalLocations = null;
    globalManeuverlist = null;
    globalSchoolmaneuvers = null;
    schools = null;
    _initialized = false;
    notifyListeners();
  }

  Map<String, dynamic> _withId(DocumentSnapshot d) {
    final data = (d.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
    return {'id': d.id, ...data};
  }
}
