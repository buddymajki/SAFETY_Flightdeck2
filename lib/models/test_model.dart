// Data models for the test system
//
// This file contains all model classes for representing tests,
// questions, and user submissions.
// Tests are loaded from local assets (assets/tests/) and results
// are saved to Firebase.

import 'package:cloud_firestore/cloud_firestore.dart';

/// Trigger condition that must be met for a test to be visible/available
class TestTrigger {
  final String type; // "category_percent", "flights_count"
  final String? category; // For category_percent type
  final String operator; // ">=", "==", ">", "<=", "<"
  final num value;

  TestTrigger({
    required this.type,
    this.category,
    required this.operator,
    required this.value,
  });

  factory TestTrigger.fromJson(Map<String, dynamic> json) {
    return TestTrigger(
      type: json['type'] as String? ?? '',
      category: json['category'] as String?,
      operator: json['operator'] as String? ?? '>=',
      value: json['value'] as num? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    if (category != null) 'category': category,
    'operator': operator,
    'value': value,
  };

  /// Evaluate this trigger against dashboard stats data
  bool evaluate(Map<String, dynamic> stats) {
    num actual = 0;

    switch (type) {
      case 'category_percent':
        if (category == null) return false;
        final progress = stats['progress'] as Map<String, dynamic>?;
        final categories = progress?['categories'] as Map<String, dynamic>?;
        final cat = categories?[category] as Map<String, dynamic>?;
        actual = (cat?['percent'] as num?) ?? 0;
        break;
      case 'flights_count':
        actual = (stats['flightsCount'] as num?) ?? 0;
        break;
      default:
        return false;
    }

    return _compare(actual, value);
  }

  bool _compare(num actual, num target) {
    switch (operator) {
      case '>=':
        return actual >= target;
      case '==':
        return actual == target;
      case '>':
        return actual > target;
      case '<=':
        return actual <= target;
      case '<':
        return actual < target;
      default:
        return false;
    }
  }

  /// Human-readable description of the trigger (for UI)
  String getDescription(String lang) {
    switch (type) {
      case 'category_percent':
        final catName = category ?? '?';
        switch (lang) {
          case 'de':
            return 'Kategorie "$catName" $operator ${value.toInt()}%';
          case 'it':
            return 'Categoria "$catName" $operator ${value.toInt()}%';
          case 'fr':
            return 'Catégorie "$catName" $operator ${value.toInt()}%';
          default:
            return 'Category "$catName" $operator ${value.toInt()}%';
        }
      case 'flights_count':
        switch (lang) {
          case 'de':
            return 'Anzahl Flüge $operator ${value.toInt()}';
          case 'it':
            return 'Numero di voli $operator ${value.toInt()}';
          case 'fr':
            return 'Nombre de vols $operator ${value.toInt()}';
          default:
            return 'Flights count $operator ${value.toInt()}';
        }
      default:
        return '$type $operator $value';
    }
  }
}

/// Metadata for a test loaded from local assets (assets/tests/tests_config.json)
///
/// This is the lightweight metadata that lists available tests
/// with localized names, trigger conditions, and pass thresholds.
class TestMetadata {
  final String id;
  final String folder;
  final String jsonFile;
  final Map<String, String> names; // {en: "...", de: "..."}
  final int passThreshold; // default 80 (percent)
  final int retryDelayDays; // default 10
  final List<TestTrigger> triggers;

  TestMetadata({
    required this.id,
    required this.folder,
    required this.jsonFile,
    required this.names,
    this.passThreshold = 80,
    this.retryDelayDays = 10,
    this.triggers = const [],
  });

  /// Get localized test name
  String getName(String lang) => names[lang] ?? names['en'] ?? 'Untitled Test';

  /// Full asset path to the JSON questions file
  String get assetPath => 'assets/tests/$folder/$jsonFile';

  /// Base path for resolving relative image URLs
  String get assetBasePath => 'assets/tests/$folder';

  /// Create from JSON (tests_config.json entry)
  factory TestMetadata.fromJson(Map<String, dynamic> json) {
    final namesRaw = json['name'] as Map<String, dynamic>? ?? {};
    final triggersRaw = json['triggers'] as List? ?? [];

    return TestMetadata(
      id: json['id'] as String? ?? '',
      folder: json['folder'] as String? ?? '',
      jsonFile: json['jsonFile'] as String? ?? '',
      names: namesRaw.map((k, v) => MapEntry(k, v.toString())),
      passThreshold: json['passThreshold'] as int? ?? 80,
      retryDelayDays: json['retryDelayDays'] as int? ?? 10,
      triggers: triggersRaw
          .whereType<Map<String, dynamic>>()
          .map((t) => TestTrigger.fromJson(t))
          .toList(),
    );
  }

  /// Check if all triggers are met given the dashboard stats
  bool areTriggersMet(Map<String, dynamic> statsJson) {
    if (triggers.isEmpty) return true;
    return triggers.every((trigger) => trigger.evaluate(statsJson));
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'folder': folder,
      'jsonFile': jsonFile,
      'name': names,
      'passThreshold': passThreshold,
      'retryDelayDays': retryDelayDays,
      'triggers': triggers.map((t) => t.toJson()).toList(),
    };
  }
}

/// Full test content loaded from local JSON asset
///
/// Contains all questions in multiple languages.
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
  /// [assetBasePath] - optional prefix for resolving relative image URLs
  /// e.g. "assets/tests/1" will turn "pgschem.png" into "assets/tests/1/pgschem.png"
  factory TestContent.fromJson(Map<String, dynamic> json, {String? assetBasePath}) {
    final Map<String, List<Question>> questions = {};
    String? disclaimer;

    json.forEach((key, value) {
      if (value is List) {
        final parsedQuestions = <Question>[];
        for (final q in value) {
          if (q is Map<String, dynamic>) {
            final question = Question.fromJson(q, assetBasePath: assetBasePath);
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
  final bool isLocalImage; // true if image is a local asset
  final Map<String, dynamic>? additionalData;

  final int? correctOptionIndex;
  final List<int>? correctOptionIndices;
  final bool? correctBoolAnswer;
  final String? correctTextAnswer;
  final List<Map<String, String>>? correctMatchingPairs;

  Question({
    required this.id,
    required this.type,
    required this.text,
    this.options = const [],
    this.matchingPairs = const [],
    this.imageUrl,
    this.isLocalImage = false,
    this.additionalData,
    this.correctOptionIndex,
    this.correctOptionIndices,
    this.correctBoolAnswer,
    this.correctTextAnswer,
    this.correctMatchingPairs,
  });

  /// Parse from JSON
  ///
  /// [assetBasePath] - if provided, relative image URLs will be prefixed
  factory Question.fromJson(Map<String, dynamic> json, {String? assetBasePath}) {
    final typeStr = json['type'] as String? ?? 'unknown';
    final type = QuestionType.fromString(typeStr);

    List<String> options = [];
    if (json['options'] is List) {
      options = (json['options'] as List).map((e) => e.toString()).toList();
    }

    List<String> matchingPairs = [];
    if (json['matchingPairs'] is List) {
      final pairs = (json['matchingPairs'] as List).whereType<Map>();
      if (options.isEmpty) {
        options = pairs.map((e) => (e['left'] ?? '').toString()).toList();
      }
      matchingPairs = pairs.map((e) => (e['right'] ?? '').toString()).toList();
    } else if (json['matching_pairs'] is List) {
      matchingPairs =
          (json['matching_pairs'] as List).map((e) => e.toString()).toList();
    }

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

    // Resolve image URL
    String? imageUrl = json['image_url'] as String? ?? json['img_url'] as String?;
    bool isLocal = false;
    if (imageUrl != null && imageUrl.isNotEmpty && assetBasePath != null && !imageUrl.startsWith('http')) {
      imageUrl = '$assetBasePath/$imageUrl';
      isLocal = true;
    }

    return Question(
      id: json['id'] as String? ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      text: json['text'] as String? ?? '',
      options: options,
      matchingPairs: matchingPairs,
      imageUrl: imageUrl,
      isLocalImage: isLocal,
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
        if (userAnswer is int) {
          return userAnswer == correctOptionIndex;
        } else if (userAnswer is String && correctOptionIndex != null) {
          final idx = options.indexOf(userAnswer);
          return idx == correctOptionIndex;
        }
        return false;
      case QuestionType.multipleChoice:
        if (userAnswer is! List || correctOptionIndices == null) return false;
        Set<int> userIdx;
        if ((userAnswer).isNotEmpty && userAnswer.first is String) {
          userIdx = userAnswer.map((e) => options.indexOf(e as String)).toSet();
        } else {
          userIdx = userAnswer.map((e) => e as int).toSet();
        }
        if (userIdx.contains(-1)) return false;
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
/// Workflow:
/// - Auto-graded on submit (score calculated immediately)
/// - If score >= passThreshold: status = 'passed'
/// - If score < passThreshold: status = 'failed', retryAvailableAt set
/// - Each attempt is recorded in the attempts list
class TestSubmission {
  final String testId;
  final String userId;
  final Map<String, dynamic> answers;
  final DateTime submittedAt;
  final String status; // 'passed', 'failed', 'submitted', 'final', 'acknowledged'
  final Map<String, dynamic>? reviewData;
  final Map<String, dynamic>? questionFeedback;
  final DateTime? studentAcknowledgedAt;
  final String? instructorReviewedBy;
  final double? scorePercent;
  final bool? passed;
  final DateTime? retryAvailableAt;
  final List<Map<String, dynamic>> attempts;
  final bool reviewedOnce; // true after failed student views results for the first time

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
    this.scorePercent,
    this.passed,
    this.retryAvailableAt,
    this.attempts = const [],
    this.reviewedOnce = false,
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
      if (scorePercent != null) 'score_percent': scorePercent,
      if (passed != null) 'passed': passed,
      if (retryAvailableAt != null)
        'retry_available_at': Timestamp.fromDate(retryAvailableAt!),
      'attempts': attempts,
      'reviewed_once': reviewedOnce,
    };
  }

  /// Create from Firestore document
  factory TestSubmission.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    Map<String, dynamic> answers = {};
    if (data['answers'] != null) {
      final answersData = data['answers'];
      if (answersData is Map) {
        answers = Map<String, dynamic>.from(answersData);
      }
    }

    Map<String, dynamic>? questionFeedback;
    if (data['questionFeedback'] != null) {
      questionFeedback = Map<String, dynamic>.from(data['questionFeedback'] as Map);
    } else if (data['question_feedback'] != null) {
      questionFeedback = Map<String, dynamic>.from(data['question_feedback'] as Map);
    }

    List<Map<String, dynamic>> attempts = [];
    if (data['attempts'] is List) {
      attempts = (data['attempts'] as List)
          .whereType<Map>()
          .map((a) => Map<String, dynamic>.from(a))
          .toList();
    }

    DateTime? retryAvailableAt;
    if (data['retry_available_at'] != null) {
      final raw = data['retry_available_at'];
      if (raw is Timestamp) {
        retryAvailableAt = raw.toDate();
      }
    }

    return TestSubmission(
      testId: data['test_id'] as String? ?? doc.id,
      userId: data['user_id'] as String? ?? '',
      answers: answers,
      submittedAt: data['submitted_at'] != null
          ? (data['submitted_at'] as Timestamp).toDate()
          : DateTime.now(),
      status: data['status'] as String? ?? 'submitted',
      reviewData: data['review_data'] != null
          ? Map<String, dynamic>.from(data['review_data'] as Map)
          : null,
      questionFeedback: questionFeedback,
      studentAcknowledgedAt: data['student_acknowledged_at'] != null
          ? (data['student_acknowledged_at'] as Timestamp).toDate()
          : null,
      instructorReviewedBy: data['instructor_reviewed_by'] as String?,
      scorePercent: (data['score_percent'] as num?)?.toDouble(),
      passed: data['passed'] as bool?,
      retryAvailableAt: retryAvailableAt,
      attempts: attempts,
      reviewedOnce: data['reviewed_once'] as bool? ?? false,
    );
  }

  /// Whether the user can retry this test now
  bool get canRetryNow {
    if (passed == true) return false;
    if (retryAvailableAt == null) return true;
    return DateTime.now().isAfter(retryAvailableAt!);
  }

  /// Days remaining until retry is available
  int get daysUntilRetry {
    if (retryAvailableAt == null) return 0;
    final diff = retryAvailableAt!.difference(DateTime.now());
    if (diff.isNegative) return 0;
    return diff.inDays + (diff.inHours % 24 > 0 ? 1 : 0);
  }
}
