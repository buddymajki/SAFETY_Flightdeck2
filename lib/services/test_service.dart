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
      
      final querySnapshot = await _firestore
          .collection('globalTests')
          .get();

      _availableTests = querySnapshot.docs
          .map((doc) => TestMetadata.fromFirestore(doc))
          .where((test) => test.testUrl.isNotEmpty) // Only include tests with URLs
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
      
      final response = await http.get(Uri.parse(testUrl));
      
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
      
      final submission = TestSubmission(
        testId: testId,
        userId: userId,
        answers: answers,
        submittedAt: DateTime.now(),
        status: 'submitted',
      );

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('tests')
          .doc(testId)
          .set(submission.toFirestore(), SetOptions(merge: true));

      debugPrint('[TestService] Test submitted successfully');
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

      return TestSubmission.fromFirestore(doc);
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
}
