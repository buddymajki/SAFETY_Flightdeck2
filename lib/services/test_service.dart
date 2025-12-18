/// Service for managing tests - loading metadata, content, and submissions
///
/// This service handles all test-related operations:
/// - Loading test metadata from Firestore (globalTests/)
/// - Fetching test content from JSON URLs
/// - Submitting user answers to Firestore (users/{uid}/tests/{testId})
///
/// Uses ChangeNotifier for state management to integrate with Provider.

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/test_model.dart';

class TestService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // State
  List<TestMetadata> _availableTests = [];
  bool _isLoading = false;
  String? _error;

  // Getters
  List<TestMetadata> get availableTests => _availableTests;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Load all available tests from Firestore globalTests/ collection
  ///
  /// This only loads metadata (test_en, test_url), not the full test content.
  /// This keeps Firestore reads minimal and efficient.
  Future<void> loadAvailableTests() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      debugPrint('[TestService] Loading available tests from Firestore');

      final querySnapshot = await _firestore.collection('globalTests').get();

      _availableTests = querySnapshot.docs
          .map((doc) => TestMetadata.fromFirestore(doc))
          .where(
              (test) => test.testUrl.isNotEmpty) // Only include tests with URLs
          .toList();

      debugPrint('[TestService] Loaded ${_availableTests.length} tests');
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

  /// Load full test content from JSON URL
  ///
  /// This downloads the test questions from the provided URL.
  /// The JSON should contain questions in multiple languages.
  ///
  /// Example JSON structure:
  /// ```json
  /// {
  ///   "en": [
  ///     {
  ///       "id": "q1",
  ///       "type": "single_choice",
  ///       "text": "What is 2+2?",
  ///       "options": ["3", "4", "5"]
  ///     }
  ///   ],
  ///   "de": [...]
  /// }
  /// ```
  Future<TestContent> loadTestContent(String testUrl) async {
    try {
      debugPrint('[TestService] Loading test content from: $testUrl');

      // Ensure Firebase Storage URLs have proper format for direct access
      String finalUrl = testUrl;
      
      // If it's a Firebase Storage URL without alt=media, add it
      if (testUrl.contains('firebasestorage.googleapis.com') && !testUrl.contains('alt=media')) {
        finalUrl = '$testUrl${testUrl.contains('?') ? '&' : '?'}alt=media';
      }

      final response = await http.get(Uri.parse(finalUrl)).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('Request timeout'),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to load test: HTTP ${response.statusCode}');
      }

      final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
      final testContent = TestContent.fromJson(jsonData);

      debugPrint('[TestService] Successfully loaded test content');
      return testContent;
    } catch (e) {
      debugPrint('[TestService] Error loading test content: $e');
      rethrow;
    }
  }

  /// Submit user's test answers to Firestore
  ///
  /// Saves to: users/{userId}/tests/{testId}
  ///
  /// The submission includes:
  /// - All user answers
  /// - Submission timestamp
  /// - Status (default: "submitted")
  ///
  /// This allows for future instructor review and signatures.
  Future<void> submitTest({
    required String userId,
    required String testId,
    required Map<String, dynamic> answers,
  }) async {
    try {
      debugPrint('[TestService] Submitting test: $testId for user: $userId');

      // Try to load content to auto-grade
      Map<String, dynamic>? reviewData;
      String status = 'final';
      try {
        // Find test URL from cache
        final meta = _availableTests.firstWhere((t) => t.id == testId,
            orElse: () => TestMetadata(id: testId, testEn: '', testUrl: ''));
        if (meta.testUrl.isNotEmpty) {
          final content = await loadTestContent(meta.testUrl);
          reviewData = _evaluateAnswers(content, answers);
          final needsManual =
              (reviewData['needsManualReview'] as bool?) ?? false;
          status = needsManual ? 'submitted' : 'final';
        } else {
          status = 'submitted';
        }
      } catch (_) {
        // On any error, keep as submitted for manual review
        status = 'submitted';
      }

      final submission = TestSubmission(
        testId: testId,
        userId: userId,
        answers: answers,
        submittedAt: DateTime.now(),
        status: status,
        reviewData: reviewData,
      );

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('tests')
          .doc(testId)
          .set(submission.toFirestore(), SetOptions(merge: true));

      debugPrint(
          '[TestService] Test submitted successfully (status: ' + status + ')');
    } catch (e) {
      debugPrint('[TestService] Error submitting test: $e');
      rethrow;
    }
  }

  /// Load user's test submissions (for future use - viewing past tests)
  ///
  /// Returns all tests submitted by the user.
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

      debugPrint('[TestService] Loaded ${submissions.length} submissions');
      return submissions;
    } catch (e) {
      debugPrint('[TestService] Error loading submissions: $e');
      rethrow;
    }
  }

  /// Check if user has already submitted a specific test
  ///
  /// Returns true if the test has been submitted, false otherwise.
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
  ///
  /// Returns null if not found.
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
      print('[TestService] getSubmission result: questionFeedback keys = ${submission.questionFeedback?.keys.toList()}');
      return submission;
    } catch (e) {
      debugPrint('[TestService] Error getting submission: $e');
      return null;
    }
  }

  /// Clear cached test list (useful for refresh)
  void clearCache() {
    _availableTests = [];
    _error = null;
    notifyListeners();
  }

  /// Acknowledge test review and sign off
  ///
  /// Called when student reviews graded test and confirms understanding.
  /// Updates status to "acknowledged" and records timestamp.
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

  /// Evaluate answers against content, returning a review summary
  /// Structure:
  /// {
  ///   total: int,
  ///   autoCorrect: int,
  ///   needsManualReview: bool,
  ///   perQuestion: { qid: true/false/null }
  /// }
  Map<String, dynamic> _evaluateAnswers(
      TestContent content, Map<String, dynamic> answers) {
    // Merge all questions across the chosen language isn't known here.
    // We evaluate across every language list and pick the first language
    // that contains the majority of question ids present in answers.
    List<Question> questions = content.questions.values.first;
    // Try to find language with best overlap
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
      total++;
      final ans = answers[q.id];
      if (q.type == QuestionType.text) {
        // Needs instructor review
        needsManual = true;
        per[q.id] = null;
        continue;
      }
      final ok = q.isAnswerCorrect(ans);
      per[q.id] = ok;
      if (ok == true) autoCorrect++;
    }

    return {
      'total': total,
      'autoCorrect': autoCorrect,
      'needsManualReview': needsManual,
      'perQuestion': per,
    };
  }
}
