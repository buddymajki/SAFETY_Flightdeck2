import 'package:cloud_firestore/cloud_firestore.dart';

class ChecklistItem {
  final String id;
  final String title_en;
  final String title_de;
  final String category;
  final String? description_en;
  final String? description_de;
  final bool isCompleted;
  final DateTime? completedAt;

  const ChecklistItem({
    required this.id,
    required this.title_en,
    required this.title_de,
    required this.category,
    this.description_en,
    this.description_de,
    this.isCompleted = false,
    this.completedAt,
  });

  factory ChecklistItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return ChecklistItem(
      id: doc.id,
      title_en: data['title_en'] as String? ?? (data['title'] as String? ?? ''),
      title_de: data['title_de'] as String? ?? (data['title'] as String? ?? ''),
      category: data['category'] as String? ?? '',
      description_en: data['description_en'] as String? ?? data['description'] as String?,
      description_de: data['description_de'] as String? ?? data['description'] as String?,
      isCompleted: data['isCompleted'] as bool? ?? false,
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title_en': title_en,
      'title_de': title_de,
      'category': category,
      'description_en': description_en,
      'description_de': description_de,
      'isCompleted': isCompleted,
      'completedAt': completedAt,
    };
  }
}
