// Service for managing tests - loading from local assets, grading, and submissions
//
// This service handles all test-related operations:
// - Loading test metadata from local assets (assets/tests/tests_config.json)
// - Loading test questions from local JSON files (assets/tests/{folder}/{file}.json)
// - Auto-grading test answers with pass threshold (default 80%)
// - Managing retry logic (10-day cooldown on failure)
// - Saving submissions to Firestore (users/{uid}/tests/{testId})
//
// Uses ChangeNotifier for state management to integrate with Provider.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import '../models/test_model.dart';

class TestService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // State
  List<TestMetadata> _availableTests = [];
  bool _isLoading = false;
  String? _error;
  Map<String, TestSubmission> _cachedSubmissions = {}; // Cache for quick lookup
  String? _lastCachedUserId;

  // Getters
  List<TestMetadata> get availableTests => _availableTests;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Load all available tests from local assets (assets/tests/tests_config.json)
  ///
  /// This loads test metadata including names, triggers, thresholds.
  /// The actual question content is loaded separately when a test is opened.
  Future<void> loadAvailableTests() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      debugPrint('[TestService] Loading test config from local assets');

      final configString = await rootBundle.loadString('assets/tests/tests_config.json');
      final configJson = jsonDecode(configString) as Map<String, dynamic>;
      final testsList = configJson['tests'] as List? ?? [];

      _availableTests = testsList
          .whereType<Map<String, dynamic>>()
          .map((t) => TestMetadata.fromJson(t))
          .where((test) => test.jsonFile.isNotEmpty)
          .toList();

      debugPrint('[TestService] Loaded ${_availableTests.length} tests from assets');
      _error = null;
    } catch (e) {
      debugPrint('[TestService] Error loading tests: $e');
      _error = 'Failed to load tests: $e';
      _availableTests = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load full test content from local asset JSON file
  ///
  /// Loads questions from assets/tests/{folder}/{jsonFile}
  /// Images referenced in questions are resolved to local asset paths.
  Future<TestContent> loadTestContent(TestMetadata test) async {
    try {
      debugPrint('[TestService] Loading test content from: ${test.assetPath}');

      final jsonString = await rootBundle.loadString(test.assetPath);
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      final testContent = TestContent.fromJson(
        jsonData,
        assetBasePath: test.assetBasePath,
      );

      debugPrint('[TestService] Successfully loaded test content');
      return testContent;
    } catch (e) {
      debugPrint('[TestService] Error loading test content: $e');
      rethrow;
    }
  }

  /// Auto-grade test answers and submit to Firestore
  ///
  /// Automatically evaluates all answers, calculates score percentage,
  /// determines pass/fail, and saves to Firebase.
  ///
  /// Returns a map with grading results:
  /// {
  ///   'scorePercent': double,
  ///   'passed': bool,
  ///   'correct': int,
  ///   'total': int,
  ///   'perQuestion': {qid: true/false/null},
  ///   'retryAvailableAt': DateTime? (only if failed),
  /// }
  Future<Map<String, dynamic>> submitAndGradeTest({
    required String userId,
    required TestMetadata test,
    required TestContent content,
    required Map<String, dynamic> answers,
  }) async {
    try {
      debugPrint('[TestService] Grading and submitting test: ${test.id} for user: $userId');

      // Auto-grade
      final gradeResult = _evaluateAnswers(content, answers);
      final total = gradeResult['total'] as int;
      final correct = gradeResult['autoCorrect'] as int;
      final perQuestion = gradeResult['perQuestion'] as Map<String, dynamic>;
      final scorePercent = total > 0 ? (correct / total * 100) : 0.0;
      final passed = scorePercent >= test.passThreshold;

      // Load existing submission to get attempt history
      final existing = await getSubmission(userId, test.id);
      final existingAttempts = existing?.attempts ?? [];

      // Build new attempt record
      final newAttempt = {
        'date': DateTime.now().toIso8601String(),
        'score_percent': scorePercent,
        'correct': correct,
        'total': total,
        'passed': passed,
      };

      final allAttempts = [...existingAttempts, newAttempt];

      // Calculate retry date if failed
      DateTime? retryAvailableAt;
      if (!passed) {
        retryAvailableAt = DateTime.now().add(Duration(days: test.retryDelayDays));
      }

      final status = passed ? 'passed' : 'failed';

      final submission = TestSubmission(
        testId: test.id,
        userId: userId,
        answers: answers,
        submittedAt: DateTime.now(),
        status: status,
        reviewData: gradeResult,
        scorePercent: scorePercent.toDouble(),
        passed: passed,
        retryAvailableAt: retryAvailableAt,
        attempts: allAttempts,
      );

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('tests')
          .doc(test.id)
          .set(submission.toFirestore(), SetOptions(merge: false));

      debugPrint('[TestService] Test submitted: score=$scorePercent%, passed=$passed, attempts=${allAttempts.length}');

      return {
        'scorePercent': scorePercent,
        'passed': passed,
        'correct': correct,
        'total': total,
        'perQuestion': perQuestion,
        'retryAvailableAt': retryAvailableAt,
        'attempts': allAttempts,
      };
    } catch (e) {
      debugPrint('[TestService] Error submitting test: $e');
      rethrow;
    }
  }

  /// Load user's test submissions (for viewing past tests)
  Future<List<TestSubmission>> loadUserSubmissions(String userId) async {
    try {
      debugPrint('[TestService] Loading submissions for user: $userId');

      final querySnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('tests')
          .orderBy('submitted_at', descending: true)
          .get();

      final submissions = querySnapshot.docs
          .map((doc) => TestSubmission.fromFirestore(doc))
          .toList();

      // Cache the submissions for quick lookup
      _cachedSubmissions = {for (final sub in submissions) sub.testId: sub};
      _lastCachedUserId = userId;

      debugPrint('[TestService] Loaded ${submissions.length} submissions');
      return submissions;
    } catch (e) {
      debugPrint('[TestService] Error loading submissions: $e');
      rethrow;
    }
  }

  /// Check if user has already submitted a specific test
  Future<bool> hasUserSubmittedTest(String userId, String testId) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('tests')
          .doc(testId)
          .get();

      return doc.exists;
    } catch (e) {
      debugPrint('[TestService] Error checking test submission: $e');
      return false;
    }
  }

  /// Get a specific test submission
  Future<TestSubmission?> getSubmission(String userId, String testId) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('tests')
          .doc(testId)
          .get();

      if (!doc.exists) return null;

      final submission = TestSubmission.fromFirestore(doc);
      debugPrint('[TestService] getSubmission: status=${submission.status}, passed=${submission.passed}, score=${submission.scorePercent}');
      return submission;
    } catch (e) {
      debugPrint('[TestService] Error getting submission: $e');
      return null;
    }
  }

  /// Check if there are any tests available for the user to attempt
  ///
  /// Returns true if:
  /// - At least one test has triggers met AND (no submission OR can retry now)
  /// This is used for the notification badge.
  Future<bool> hasAvailableTestsForUser({
    required String userId,
    required Map<String, dynamic> statsJson,
  }) async {
    for (final test in _availableTests) {
      final triggersMet = test.areTriggersMet(statsJson);
      if (!triggersMet) continue; // Triggers not met, skip

      // Check if user has attempted this test
      final submission = await getSubmission(userId, test.id);
      
      if (submission == null) {
        // Never attempted and triggers met -> actionable
        return true;
      } else if (submission.passed == false && submission.canRetryNow) {
        // Failed but can retry now -> actionable
        return true;
      }
      // Otherwise: passed (done), failed but can't retry (wait), so not actionable
    }
    return false;
  }

  /// Get cached submission (synchronous, for quick UI checks)
  /// Returns null if not in cache or user changed
  TestSubmission? getCachedSubmission(String userId, String testId) {
    if (_lastCachedUserId != userId) return null;
    return _cachedSubmissions[testId];
  }

  /// Check if user has any available tests to attempt (using cached submissions)
  ///
  /// Returns true if at least one test has:
  /// - Triggers met AND (no cached submission OR (failed AND can retry now))
  bool hasAvailableTestsSync({
    required String userId,
    required Map<String, dynamic> statsJson,
  }) {
    for (final test in _availableTests) {
      final triggersMet = test.areTriggersMet(statsJson);
      if (!triggersMet) continue;

      final submission = getCachedSubmission(userId, test.id);
      
      if (submission == null) {
        // Not in cache: either never attempted or cache not loaded
        // To be conservative, only return true if cache is loaded for this user
        if (_lastCachedUserId == userId) {
          // Cache is loaded and test not in cache = never attempted
          return true;
        }
      } else if (submission.passed == false && submission.canRetryNow) {
        // Failed but can retry now
        return true;
      }
    }
    return false;
  }

  /// Check if user can retry a failed test
  ///
  /// Returns true if:
  /// - No submission exists (first attempt)
  /// - Previous attempt was failed AND retry cooldown has passed
  /// Returns false if:
  /// - Test is already passed
  /// - Retry cooldown hasn't expired
  Future<bool> canRetryTest(String userId, String testId) async {
    final submission = await getSubmission(userId, testId);
    if (submission == null) return true; // First attempt
    if (submission.passed == true) return false; // Already passed
    return submission.canRetryNow;
  }

  /// Mark that a failed student has reviewed their results once
  /// After this, they cannot view the answers again until they retry.
  Future<void> markReviewedOnce({
    required String userId,
    required String testId,
  }) async {
    try {
      debugPrint('[TestService] Marking test $testId as reviewed once');
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('tests')
          .doc(testId)
          .update({'reviewed_once': true});
    } catch (e) {
      debugPrint('[TestService] Error marking reviewed once: $e');
    }
  }

  /// Save a test result summary to the school collection for scalability
  ///
  /// Writes to: schools/{schoolId}/test_results/{testId}__{userId}
  /// This gives the school a quick-access view of all students' results.
  Future<void> saveSchoolTestResult({
    required String schoolId,
    required String userId,
    required String testId,
    required bool passed,
    required double scorePercent,
    required int attemptCount,
    required DateTime submittedAt,
  }) async {
    try {
      debugPrint('[TestService] Saving school test result: school=$schoolId, test=$testId, user=$userId');
      final docId = '${testId}__$userId';
      await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('test_results')
          .doc(docId)
          .set({
        'test_id': testId,
        'user_id': userId,
        'passed': passed,
        'score_percent': scorePercent,
        'attempts': attemptCount,
        'submitted_at': Timestamp.fromDate(submittedAt),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('[TestService] School test result saved');
    } catch (e) {
      debugPrint('[TestService] Error saving school test result: $e');
      // Non-critical — don't rethrow
    }
  }

  /// Clear cached test list
  void clearCache() {
    _availableTests = [];
    _error = null;
    notifyListeners();
  }

  /// Acknowledge test review and sign off
  Future<void> acknowledgeTestReview({
    required String userId,
    required String testId,
  }) async {
    try {
      debugPrint('[TestService] Acknowledging test review: $testId');

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('tests')
          .doc(testId)
          .update({
        'status': 'acknowledged',
        'student_acknowledged_at': FieldValue.serverTimestamp(),
      });

      debugPrint('[TestService] Test acknowledged successfully');
    } catch (e) {
      debugPrint('[TestService] Error acknowledging test: $e');
      rethrow;
    }
  }

  /// Evaluate answers against content, returning a grading summary
  Map<String, dynamic> _evaluateAnswers(
      TestContent content, Map<String, dynamic> answers) {
    // Find the language version with best question overlap
    List<Question> questions = content.questions.values.first;
    int bestMatches = -1;
    for (final list in content.questions.values) {
      final match = list.where((q) => answers.containsKey(q.id)).length;
      if (match > bestMatches) {
        bestMatches = match;
        questions = list;
      }
    }

    int total = 0;
    int autoCorrect = 0;
    bool needsManual = false;
    final Map<String, dynamic> per = {};

    for (final q in questions) {
      // Skip text/disclaimer questions from auto-grading count
      if (q.type == QuestionType.text) {
        needsManual = true;
        per[q.id] = null;
        continue;
      }

      total++;
      final ans = answers[q.id];
      final ok = q.isAnswerCorrect(ans);
      per[q.id] = ok;
      if (ok) autoCorrect++;
    }

    return {
      'total': total,
      'autoCorrect': autoCorrect,
      'needsManualReview': needsManual,
      'perQuestion': per,
    };
  }
}
