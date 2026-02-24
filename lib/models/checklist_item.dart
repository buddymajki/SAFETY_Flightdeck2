import 'package:cloud_firestore/cloud_firestore.dart';

/// Checklist item model for pre-flight/post-flight checklists
/// Note: Field names use snake_case to match Firestore document structure
// ignore_for_file: non_constant_identifier_names
class ChecklistItem {
  final String id;
  final String title_en;
  final String title_de;
  final String? title_it;
  final String? title_fr;
  final String category;
  final String? description_en;
  final String? description_de;
  final String? description_it;
  final String? description_fr;
  final bool isCompleted;
  final DateTime? completedAt;

  const ChecklistItem({
    required this.id,
    required this.title_en,
    required this.title_de,
    this.title_it,
    this.title_fr,
    required this.category,
    this.description_en,
    this.description_de,
    this.description_it,
    this.description_fr,
    this.isCompleted = false,
    this.completedAt,
  });

  factory ChecklistItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return ChecklistItem(
      id: doc.id,
      title_en: data['title_en'] as String? ?? (data['title'] as String? ?? ''),
      title_de: data['title_de'] as String? ?? (data['title'] as String? ?? ''),
      title_it: data['title_it'] as String?,
      title_fr: data['title_fr'] as String?,
      category: data['category'] as String? ?? '',
      description_en: data['description_en'] as String? ?? data['description'] as String?,
      description_de: data['description_de'] as String? ?? data['description'] as String?,
      description_it: data['description_it'] as String?,
      description_fr: data['description_fr'] as String?,
      isCompleted: data['isCompleted'] as bool? ?? false,
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title_en': title_en,
      'title_de': title_de,
      if (title_it != null) 'title_it': title_it,
      if (title_fr != null) 'title_fr': title_fr,
      'category': category,
      'description_en': description_en,
      'description_de': description_de,
      if (description_it != null) 'description_it': description_it,
      if (description_fr != null) 'description_fr': description_fr,
      'isCompleted': isCompleted,
      'completedAt': completedAt,
    };
  }

  /// Get the title for the given language code.
  /// Tries the requested language first, then falls back to English.
  String getTitle(String languageCode) {
    switch (languageCode) {
      case 'de':
        return title_de;
      case 'it':
        return title_it ?? title_en;
      case 'fr':
        return title_fr ?? title_en;
      default:
        return title_en;
    }
  }

  /// Get the description for the given language code.
  /// Tries the requested language first, then falls back to English.
  String? getDescription(String languageCode) {
    switch (languageCode) {
      case 'de':
        return description_de;
      case 'it':
        return description_it ?? description_en;
      case 'fr':
        return description_fr ?? description_en;
      default:
        return description_en;
    }
  }
}
