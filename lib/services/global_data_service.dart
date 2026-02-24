import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/checklist_item.dart';

class GlobalDataService extends ChangeNotifier {
  // Fixed category order and multilingual titles
  static const List<String> categoryOrder = [
    'gh-bas', 'gh-adv', 'th-flight', 'th-core', 'hf-bas', 'hf-adv', 'exam'
  ];

  static const Map<String, Map<String, String>> categoryTitles = {
    'gh-bas': {'en': 'Groundhandling Basics', 'de': 'Bodenhandling Grundlagen', 'it': 'Groundhandling base', 'fr': 'Bases du maniement au sol'},
    'gh-adv': {'en': 'Groundhandling Advanced', 'de': 'Bodenhandling Fortgeschritten', 'it': 'Groundhandling avanzato', 'fr': 'Maniement au sol avancé'},
    'th-flight': {'en': 'In flight Theory', 'de': 'Theorie im Flug', 'it': 'Teoria in volo', 'fr': 'Théorie en vol'},
    'th-core': {'en': 'Core Theory', 'de': 'Kerntheorie', 'it': 'Teoria di base', 'fr': 'Théorie fondamentale'},
    'hf-bas': {'en': 'High Flights Basic', 'de': 'Höhenflüge Grundlagen', 'it': 'Voli in quota base', 'fr': 'Vols en altitude bases'},
    'hf-adv': {'en': 'High Flights Advanced', 'de': 'Höhenflüge Fortgeschritten', 'it': 'Voli in quota avanzato', 'fr': 'Vols en altitude avancé'},
    'exam': {'en': 'Exam Preparation', 'de': 'Prüfungsvorbereitung', 'it': 'Preparazione esame', 'fr': 'Préparation à l\'examen'},
  };

  // Short names for tab display
  static const Map<String, Map<String, String>> categoryShortNames = {
    'gh-bas': {'en': 'GH Basic', 'de': 'ÜH Grund', 'it': 'GH Base', 'fr': 'MS Base'},
    'gh-adv': {'en': 'GH Adv', 'de': 'ÜH Fort', 'it': 'GH Avanz', 'fr': 'MS Av'},
    'th-flight': {'en': 'TH Flight', 'de': 'TH Flug', 'it': 'TH Volo', 'fr': 'TH Vol'},
    'th-core': {'en': 'TH Core', 'de': 'TH Kern', 'it': 'TH Base', 'fr': 'TH Fond'},
    'hf-bas': {'en': 'HF Basic', 'de': 'HF Grund', 'it': 'VA Base', 'fr': 'VA Base'},
    'hf-adv': {'en': 'HF Adv', 'de': 'HF Fort', 'it': 'VA Avanz', 'fr': 'VA Av'},
    'exam': {'en': 'Exam', 'de': 'Prüf', 'it': 'Esame', 'fr': 'Exam'},
  };

  List<Map<String, dynamic>>? globalChecklists;
  List<Map<String, dynamic>>? globalFlighttypes;
  List<Map<String, dynamic>>? globalStarttypes;
  List<Map<String, dynamic>>? globalManeuvers;
  List<Map<String, dynamic>>? globalLocations;
  List<Map<String, dynamic>>? schools;

  Map<String, dynamic>? _globalChecklists;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> initializeData() async {
    final fs = FirebaseFirestore.instance;
    try {
      final opts = const GetOptions(source: Source.serverAndCache);


      final results = await Future.wait([
        fs.collection('globalChecklists').get(opts),         // 0
        fs.collection('globalFlighttypes').get(opts),         // 1
        fs.collection('globalStarttypes').get(opts),          // 2
        fs.collection('globalManeuvers').get(opts),           // 3
        fs.collection('globalLocations').get(opts),           // 4
        fs.collection('schools').get(opts),                  // 5
      ]);

      _globalChecklists = {
        for (final d in results[0].docs) d.id: {'id': d.id, ...d.data()}
      };
      globalChecklists = results[0].docs.map((d) => _withId(d)).toList();
      globalFlighttypes = results[1].docs.map((d) => _withId(d)).toList();
      globalStarttypes = results[2].docs.map((d) => _withId(d)).toList();
      globalManeuvers = results[3].docs.map((d) => _withId(d)).toList();
      globalLocations = results[4].docs.map((d) => _withId(d)).toList();
      schools = results[5].docs.map((d) => _withId(d)).toList();

      _initialized = true;
      notifyListeners();

      log('[GlobalDataService] Loaded: checklists=${globalChecklists?.length ?? 0}, flighttypes=${globalFlighttypes?.length ?? 0}, starttypes=${globalStarttypes?.length ?? 0}, maneuvers=${globalManeuvers?.length ?? 0}');
    } catch (e, st) {
      if (kDebugMode) {
        log('[GlobalDataService] initializeData error: $e', stackTrace: st);
      }
      rethrow;
    }
  }

  void resetService() {
    _globalChecklists = null;
    globalChecklists = null;
    globalFlighttypes = null;
    globalStarttypes = null;
    globalManeuvers = null;
    globalLocations = null;
    schools = null;
    _initialized = false;
    notifyListeners();
  }

  List<ChecklistItem> get allChecklistItems {
    if (_globalChecklists == null) return const [];
    return _globalChecklists!.values.map((raw) {
      final data = raw as Map<String, dynamic>;
      return ChecklistItem(
        id: data['id'] as String? ?? '',
        title_en: (data['title_en'] as String?) ?? (data['title'] as String? ?? ''),
        title_de: (data['title_de'] as String?) ?? (data['title'] as String? ?? ''),
        category: data['category'] as String? ?? '',
        description_en: (data['description_en'] as String?) ?? (data['description'] as String?),
        description_de: (data['description_de'] as String?) ?? (data['description'] as String?),
        isCompleted: data['isCompleted'] as bool? ?? false,
        completedAt: (data['completedAt'] is Timestamp)
            ? (data['completedAt'] as Timestamp).toDate()
            : null,
      );
    }).toList();
  }

  Map<String, dynamic> _withId(DocumentSnapshot d) {
    final data = (d.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
    return {'id': d.id, ...data};
  }

  /// Get the translated title for a category.
  /// Falls back to English if the requested language is not available.
  String getCategoryTitle(String categoryId, String languageCode) {
    final titles = categoryTitles[categoryId];
    if (titles == null) return categoryId;
    return titles[languageCode] ?? titles['en'] ?? categoryId;
  }

  /// Get the short name for a category (for tab display).
  /// Falls back to English if the requested language is not available.
  String getCategoryShortName(String categoryId, String languageCode) {
    final shortNames = categoryShortNames[categoryId];
    if (shortNames == null) return categoryId;
    return shortNames[languageCode] ?? shortNames['en'] ?? categoryId;
  }
}
