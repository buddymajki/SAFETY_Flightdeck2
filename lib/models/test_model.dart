// Data models for the test system
//
// This file contains all model classes for representing tests,
// questions, and user submissions.

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
  final String? disclaimer;

  TestContent({
    required this.questions,
    this.metadata,
    this.disclaimer,
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
  ///     },
  ///     {
  ///       "id": "disclaimer",
  ///       "type": "text",
  ///       "text": "Disclaimer text..."
  ///     }
  ///   ],
  ///   "de": [...]
  /// }
  factory TestContent.fromJson(Map<String, dynamic> json) {
    final Map<String, List<Question>> questions = {};
    String? disclaimer;

    // Parse questions for each language
    json.forEach((key, value) {
      if (value is List) {
        final parsedQuestions = <Question>[];
        for (final q in value) {
          if (q is Map<String, dynamic>) {
            final question = Question.fromJson(q);
            // Extract disclaimer if found in questions list
            if (question.id == 'disclaimer' && disclaimer == null) {
              disclaimer = question.text;
            } else {
              parsedQuestions.add(question);
            }
          }
        }
        questions[key] = parsedQuestions;
      }
    });

    return TestContent(
      questions: questions,
      metadata: json['metadata'] as Map<String, dynamic>?,
      disclaimer: disclaimer,
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

  // Correct answer fields for automatic evaluation
  final int? correctOptionIndex; // For single_choice
  final List<int>? correctOptionIndices; // For multiple_choice
  final bool? correctBoolAnswer; // For true_false
  final String? correctTextAnswer; // For text (exact match or keywords)
  final List<Map<String, String>>? correctMatchingPairs; // For matching

  Question({
    required this.id,
    required this.type,
    required this.text,
    this.options = const [],
    this.matchingPairs = const [],
    this.imageUrl,
    this.additionalData,
    this.correctOptionIndex,
    this.correctOptionIndices,
    this.correctBoolAnswer,
    this.correctTextAnswer,
    this.correctMatchingPairs,
  });

  /// Parse from JSON
  factory Question.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'unknown';
    final type = QuestionType.fromString(typeStr);

    // Parse options list
    List<String> options = [];
    if (json['options'] is List) {
      options = (json['options'] as List).map((e) => e.toString()).toList();
    }

    // Parse matching pairs if present
    List<String> matchingPairs = [];
    // New structured form: matchingPairs: [{left,right}, ...]
    if (json['matchingPairs'] is List) {
      final pairs = (json['matchingPairs'] as List).whereType<Map>();
      // If options were not explicitly given, infer left side from pairs
      if (options.isEmpty) {
        options = pairs.map((e) => (e['left'] ?? '').toString()).toList();
      }
      matchingPairs = pairs.map((e) => (e['right'] ?? '').toString()).toList();
    } else if (json['matching_pairs'] is List) {
      // Legacy simple list form (right side only)
      matchingPairs =
          (json['matching_pairs'] as List).map((e) => e.toString()).toList();
    }

    // Parse correct answers based on question type
    int? correctOptionIndex;
    List<int>? correctOptionIndices;
    bool? correctBoolAnswer;
    String? correctTextAnswer;
    List<Map<String, String>>? correctMatchingPairs;

    if (json['correctAnswer'] != null) {
      switch (type) {
        case QuestionType.singleChoice:
          correctOptionIndex = json['correctAnswer'] as int?;
          break;
        case QuestionType.multipleChoice:
          if (json['correctAnswer'] is List) {
            correctOptionIndices =
                (json['correctAnswer'] as List).map((e) => e as int).toList();
          }
          break;
        case QuestionType.trueFalse:
          correctBoolAnswer = json['correctAnswer'] as bool?;
          break;
        case QuestionType.text:
          correctTextAnswer = json['correctAnswer'] as String?;
          break;
        case QuestionType.matching:
          if (json['correctAnswer'] is List) {
            correctMatchingPairs = (json['correctAnswer'] as List)
                .map((e) => Map<String, String>.from(e as Map))
                .toList();
          }
          break;
        default:
          break;
      }
    }

    return Question(
      id: json['id'] as String? ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      text: json['text'] as String? ?? '',
      options: options,
      matchingPairs: matchingPairs,
      imageUrl: json['image_url'] as String? ?? json['img_url'] as String?,
      additionalData: json,
      correctOptionIndex: correctOptionIndex,
      correctOptionIndices: correctOptionIndices,
      correctBoolAnswer: correctBoolAnswer,
      correctTextAnswer: correctTextAnswer,
      correctMatchingPairs: correctMatchingPairs,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    dynamic correctAnswer;
    switch (type) {
      case QuestionType.singleChoice:
        correctAnswer = correctOptionIndex;
        break;
      case QuestionType.multipleChoice:
        correctAnswer = correctOptionIndices;
        break;
      case QuestionType.trueFalse:
        correctAnswer = correctBoolAnswer;
        break;
      case QuestionType.text:
        correctAnswer = correctTextAnswer;
        break;
      case QuestionType.matching:
        correctAnswer = correctMatchingPairs;
        break;
      default:
        break;
    }

    return {
      'id': id,
      'type': type.toString().split('.').last,
      'text': text,
      if (options.isNotEmpty) 'options': options,
      if (matchingPairs.isNotEmpty) 'matching_pairs': matchingPairs,
      if (imageUrl != null) 'image_url': imageUrl,
      if (correctAnswer != null) 'correctAnswer': correctAnswer,
      ...?additionalData,
    };
  }

  /// Check if a given answer is correct
  bool isAnswerCorrect(dynamic userAnswer) {
    switch (type) {
      case QuestionType.singleChoice:
        if (userAnswer == null) return false;
        // Accept either index or option text
        if (userAnswer is int) {
          return userAnswer == correctOptionIndex;
        } else if (userAnswer is String && correctOptionIndex != null) {
          final idx = options.indexOf(userAnswer);
          return idx == correctOptionIndex;
        }
        return false;
      case QuestionType.multipleChoice:
        if (userAnswer is! List || correctOptionIndices == null) return false;
        // Accept either indices or option texts
        Set<int> userIdx;
        if ((userAnswer).isNotEmpty && userAnswer.first is String) {
          userIdx = userAnswer.map((e) => options.indexOf(e as String)).toSet();
        } else {
          userIdx = userAnswer.map((e) => e as int).toSet();
        }
        if (userIdx.contains(-1)) return false; // unknown option
        final correctSet = correctOptionIndices!.toSet();
        return userIdx.length == correctSet.length &&
            userIdx.difference(correctSet).isEmpty;
      case QuestionType.trueFalse:
        return userAnswer == correctBoolAnswer;
      case QuestionType.text:
        if (correctTextAnswer == null) return false;
        return userAnswer.toString().trim().toLowerCase() ==
            correctTextAnswer!.trim().toLowerCase();
      case QuestionType.matching:
        if (correctMatchingPairs == null) return false;
        // Accept either list of pairs or map of left->right
        Map<String, String> userMap = {};
        if (userAnswer is Map) {
          userMap =
              userAnswer.map((k, v) => MapEntry(k.toString(), v.toString()));
        } else if (userAnswer is List) {
          for (final p in userAnswer) {
            if (p is Map) {
              final left = p['left']?.toString() ?? '';
              final right = p['right']?.toString() ?? '';
              userMap[left] = right;
            }
          }
        } else {
          return false;
        }
        if (userMap.length != correctMatchingPairs!.length) return false;
        for (final corr in correctMatchingPairs!) {
          final l = corr['left'] ?? '';
          final r = corr['right'] ?? '';
          if (userMap[l] != r) return false;
        }
        return true;
      default:
        return false;
    }
  }
}

/// User's submission for a test
///
/// Saved to users/{uid}/tests/{testId} in Firestore
/// Workflow: submitted → final (instructor grades) → acknowledged (student reviews & signs)
class TestSubmission {
  final String testId;
  final String userId;
  final Map<String, dynamic> answers;
  final DateTime submittedAt;
  final String status; // submitted → final → acknowledged
  final Map<String, dynamic>? reviewData;
  final Map<String, dynamic>?
      questionFeedback; // Instructor feedback for text questions
  final DateTime? studentAcknowledgedAt; // When student reviewed and signed off
  final String? instructorReviewedBy; // UID of instructor who graded

  TestSubmission({
    required this.testId,
    required this.userId,
    required this.answers,
    required this.submittedAt,
    this.status = 'submitted',
    this.reviewData,
    this.questionFeedback,
    this.studentAcknowledgedAt,
    this.instructorReviewedBy,
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
      if (questionFeedback != null) 'question_feedback': questionFeedback,
      if (studentAcknowledgedAt != null)
        'student_acknowledged_at': Timestamp.fromDate(studentAcknowledgedAt!),
      if (instructorReviewedBy != null)
        'instructor_reviewed_by': instructorReviewedBy,
    };
  }

  /// Create from Firestore document
  factory TestSubmission.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // Safely get answers, handling both direct and nested structures
    Map<String, dynamic> answers = {};
    if (data['answers'] != null) {
      final answersData = data['answers'];
      if (answersData is Map) {
        answers = Map<String, dynamic>.from(answersData);
      }
    }

    // Try both naming conventions for questionFeedback
    Map<String, dynamic>? questionFeedback;
    if (data['questionFeedback'] != null) {
      questionFeedback = Map<String, dynamic>.from(data['questionFeedback'] as Map);
    } else if (data['question_feedback'] != null) {
      questionFeedback = Map<String, dynamic>.from(data['question_feedback'] as Map);
    }

    return TestSubmission(
      testId: data['test_id'] as String,
      userId: data['user_id'] as String,
      answers: answers,
      submittedAt: (data['submitted_at'] as Timestamp).toDate(),
      status: data['status'] as String? ?? 'submitted',
      reviewData: data['review_data'] != null
          ? Map<String, dynamic>.from(data['review_data'] as Map)
          : null,
      questionFeedback: questionFeedback,
      studentAcknowledgedAt: data['student_acknowledged_at'] != null
          ? (data['student_acknowledged_at'] as Timestamp).toDate()
          : null,
      instructorReviewedBy: data['instructor_reviewed_by'] as String?,
    );
  }
}
