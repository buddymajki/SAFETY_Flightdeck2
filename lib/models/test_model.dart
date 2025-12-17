/// Data models for the test system
/// 
/// This file contains all model classes for representing tests,
/// questions, and user submissions.

import 'package:cloud_firestore/cloud_firestore.dart';

/// Metadata for a test loaded from Firestore globalTests/ collection
/// 
/// This is the lightweight metadata that lists available tests.
/// The actual questions are loaded separately from the test_url.
class TestMetadata {
  final String id;
  final String testEn;
  final String testUrl;
  final Map<String, dynamic>? additionalData;

  TestMetadata({
    required this.id,
    required this.testEn,
    required this.testUrl,
    this.additionalData,
  });

  /// Create TestMetadata from Firestore document
  factory TestMetadata.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return TestMetadata(
      id: doc.id,
      testEn: data['test_en'] as String? ?? 'Untitled Test',
      testUrl: data['test_url'] as String? ?? '',
      additionalData: data,
    );
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'test_en': testEn,
      'test_url': testUrl,
      ...?additionalData,
    };
  }
}

/// Full test content loaded from JSON URL
/// 
/// Contains all questions in multiple languages.
/// The structure supports multiple question types.
class TestContent {
  final Map<String, List<Question>> questions;
  final Map<String, dynamic>? metadata;

  TestContent({
    required this.questions,
    this.metadata,
  });

  /// Parse from JSON structure
  /// 
  /// Expected JSON format:
  /// {
  ///   "en": [
  ///     {
  ///       "id": "q1",
  ///       "type": "single_choice",
  ///       "text": "Question text",
  ///       "options": ["Option 1", "Option 2"]
  ///     }
  ///   ],
  ///   "de": [...]
  /// }
  factory TestContent.fromJson(Map<String, dynamic> json) {
    final Map<String, List<Question>> questions = {};
    
    // Parse questions for each language
    json.forEach((key, value) {
      if (value is List) {
        questions[key] = value.map((q) {
          if (q is Map<String, dynamic>) {
            return Question.fromJson(q);
          }
          throw FormatException('Invalid question format');
        }).toList();
      }
    });

    return TestContent(
      questions: questions,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}

/// Enum for different question types
enum QuestionType {
  singleChoice,
  multipleChoice,
  trueFalse,
  text,
  matching,
  image,
  unknown;

  /// Parse from string
  static QuestionType fromString(String type) {
    switch (type.toLowerCase()) {
      case 'single_choice':
      case 'single':
        return QuestionType.singleChoice;
      case 'multiple_choice':
      case 'multiple':
        return QuestionType.multipleChoice;
      case 'true_false':
      case 'boolean':
        return QuestionType.trueFalse;
      case 'text':
      case 'short_answer':
        return QuestionType.text;
      case 'matching':
        return QuestionType.matching;
      case 'image':
        return QuestionType.image;
      default:
        return QuestionType.unknown;
    }
  }
}

/// Individual question in a test
class Question {
  final String id;
  final QuestionType type;
  final String text;
  final List<String> options;
  final List<String> matchingPairs;
  final String? imageUrl;
  final Map<String, dynamic>? additionalData;

  Question({
    required this.id,
    required this.type,
    required this.text,
    this.options = const [],
    this.matchingPairs = const [],
    this.imageUrl,
    this.additionalData,
  });

  /// Parse from JSON
  factory Question.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'unknown';
    final type = QuestionType.fromString(typeStr);
    
    // Parse options list
    List<String> options = [];
    if (json['options'] is List) {
      options = (json['options'] as List)
          .map((e) => e.toString())
          .toList();
    }

    // Parse matching pairs if present
    List<String> matchingPairs = [];
    if (json['matching_pairs'] is List) {
      matchingPairs = (json['matching_pairs'] as List)
          .map((e) => e.toString())
          .toList();
    }

    return Question(
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      text: json['text'] as String? ?? '',
      options: options,
      matchingPairs: matchingPairs,
      imageUrl: json['image_url'] as String?,
      additionalData: json,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.toString().split('.').last,
      'text': text,
      if (options.isNotEmpty) 'options': options,
      if (matchingPairs.isNotEmpty) 'matching_pairs': matchingPairs,
      if (imageUrl != null) 'image_url': imageUrl,
      ...?additionalData,
    };
  }
}

/// User's submission for a test
/// 
/// Saved to users/{uid}/tests/{testId} in Firestore
class TestSubmission {
  final String testId;
  final String userId;
  final Map<String, dynamic> answers;
  final DateTime submittedAt;
  final String status;
  final Map<String, dynamic>? reviewData;

  TestSubmission({
    required this.testId,
    required this.userId,
    required this.answers,
    required this.submittedAt,
    this.status = 'submitted',
    this.reviewData,
  });

  /// Convert to Firestore format
  Map<String, dynamic> toFirestore() {
    return {
      'test_id': testId,
      'user_id': userId,
      'answers': answers,
      'submitted_at': Timestamp.fromDate(submittedAt),
      'status': status,
      if (reviewData != null) 'review_data': reviewData,
    };
  }

  /// Create from Firestore document
  factory TestSubmission.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return TestSubmission(
      testId: data['test_id'] as String,
      userId: data['user_id'] as String,
      answers: data['answers'] as Map<String, dynamic>,
      submittedAt: (data['submitted_at'] as Timestamp).toDate(),
      status: data['status'] as String? ?? 'submitted',
      reviewData: data['review_data'] as Map<String, dynamic>?,
    );
  }
}
