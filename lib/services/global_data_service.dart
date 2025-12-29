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
    'gh-bas': {'en': 'Groundhandling Basics', 'de': 'Bodenhandling Grundlagen'},
    'gh-adv': {'en': 'Groundhandling Advanced', 'de': 'Bodenhandling Fortgeschritten'},
    'th-flight': {'en': 'In flight Theory', 'de': 'Theorie im Flug'},
    'th-core': {'en': 'Core Theory', 'de': 'Kerntheorie'},
    'hf-bas': {'en': 'High Flights Basic', 'de': 'Höhenflüge Grundlagen'},
    'hf-adv': {'en': 'High Flights Advanced', 'de': 'Höhenflüge Fortgeschritten'},
    'exam': {'en': 'Exam Preparation', 'de': 'Prüfungsvorbereitung'},
  };

  // Short names for tab display
  static const Map<String, Map<String, String>> categoryShortNames = {
    'gh-bas': {'en': 'GH Basic', 'de': 'ÜH Grund'},
    'gh-adv': {'en': 'GH Adv', 'de': 'ÜH Fort'},
    'th-flight': {'en': 'TH Flight', 'de': 'TH Flug'},
    'th-core': {'en': 'TH Core', 'de': 'TH Kern'},
    'hf-bas': {'en': 'HF Basic', 'de': 'HF Grund'},
    'hf-adv': {'en': 'HF Adv', 'de': 'HF Fort'},
    'exam': {'en': 'Exam', 'de': 'Prüf'},
  };

  List<Map<String, dynamic>>? globalChecklists;
  List<Map<String, dynamic>>? globalFlighttypes;
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
        fs.collection('globalChecklists').get(opts),
        fs.collection('globalFlighttypes').get(opts),
        fs.collection('globalLocations').get(opts),
        fs.collection('schools').get(opts),
      ]);

      _globalChecklists = {
        for (final d in results[0].docs) d.id: {'id': d.id, ...d.data()}
      };
      globalChecklists = results[0].docs.map((d) => _withId(d)).toList();
      globalFlighttypes = results[1].docs.map((d) => _withId(d)).toList();
      globalLocations = results[2].docs.map((d) => _withId(d)).toList();
      schools = results[3].docs.map((d) => _withId(d)).toList();

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
    _globalChecklists = null;
    globalChecklists = null;
    globalFlighttypes = null;
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
