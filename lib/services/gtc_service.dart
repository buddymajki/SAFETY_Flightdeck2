import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class GTCService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cache GT&C data and acceptance status
  final Map<String, Map<String, dynamic>> _gtcBySchool = {};
  final Map<String, Map<String, dynamic>> _acceptanceBySchool = {};
  final Set<String> _loadingSchools = {};
  Map<String, dynamic>? _currentGTC;
  Map<String, dynamic>? _currentAcceptance;
  bool _isLoading = false;
  //String? _currentSchoolId;
  String? _currentUid;

  // Getters
  Map<String, dynamic>? get currentGTC => _currentGTC;
  Map<String, dynamic>? get currentAcceptance => _currentAcceptance;
  bool get isLoading => _isLoading;
  bool get isGTCAccepted => _currentAcceptance?['gtc_accepted'] ?? false;
  String? get currentGTCVersion => _currentGTC?['gtc_version'] as String?;

  Map<String, dynamic>? getGTCForSchool(String schoolId) => _gtcBySchool[schoolId];
  Map<String, dynamic>? getAcceptanceForSchool(String schoolId) => _acceptanceBySchool[schoolId];
  bool isGTCAcceptedForSchool(String schoolId) => _acceptanceBySchool[schoolId]?['gtc_accepted'] ?? false;
  bool isLoadingForSchool(String schoolId) => _loadingSchools.contains(schoolId);
  List<String> get acceptedSchoolIds => _acceptanceBySchool.entries
      .where((entry) => entry.value['gtc_accepted'] == true)
      .map((entry) => entry.key)
      .toList();

  /// Fetch GT&C for a specific school from Firestore URL
  Future<void> loadGTC(String schoolId) async {
    if (_gtcBySchool.containsKey(schoolId)) {
      debugPrint('[GTCService] GT&C already cached for school: $schoolId');
      return; // Already loaded
    }

    _loadingSchools.add(schoolId);
    _isLoading = true;
    notifyListeners();

    try {
      debugPrint('[GTCService] Loading GT&C URL for school: $schoolId');
      
      // Step 1: Get the gtc_url from Firestore
      final schoolDoc = await _firestore.collection('schools').doc(schoolId).get();
      if (!schoolDoc.exists) {
        debugPrint('[GTCService] School document not found: $schoolId');
        _gtcBySchool.remove(schoolId);
        return;
      }

      final schoolData = schoolDoc.data();
      if (schoolData == null) {
        debugPrint('[GTCService] School data is null: $schoolId');
        _gtcBySchool.remove(schoolId);
        return;
      }

      final gtcUrl = schoolData['gtc_url'] as String?;
      if (gtcUrl == null || gtcUrl.isEmpty) {
        debugPrint('[GTCService] No gtc_url found for school: $schoolId');
        _gtcBySchool.remove(schoolId);
        return;
      }

      debugPrint('[GTCService] Fetching GT&C JSON from URL: $gtcUrl');
      
      // Step 2: Fetch the JSON from Firebase Storage URL
      final response = await http.get(Uri.parse(gtcUrl));
      if (response.statusCode != 200) {
        debugPrint('[GTCService] Failed to fetch GT&C JSON: ${response.statusCode}');
        debugPrint('[GTCService] Response headers: ${response.headers}');
        debugPrint('[GTCService] Response body (first 200 chars): ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
        _gtcBySchool.remove(schoolId);
        return;
      }

      // Step 3: Parse the JSON
      final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
      final gtcData = {
        'gtc_data': jsonData,
        'gtc_url': gtcUrl,
        'gtc_version': schoolData['gtc_version'] ?? '1.0',
        'school_name': schoolData['name'] ?? 'Unknown School',
      };
      _gtcBySchool[schoolId] = gtcData;
      _currentGTC = gtcData;
      //_currentSchoolId = schoolId;
      
      debugPrint('[GTCService] Successfully loaded GT&C with version: ${_currentGTC?['gtc_version']}');
    } catch (e) {
      debugPrint('[GTCService] Error loading GT&C: $e');
      _gtcBySchool.remove(schoolId);
    } finally {
      _loadingSchools.remove(schoolId);
      _isLoading = _loadingSchools.isNotEmpty;
      notifyListeners();
    }
  }

  /// Check if user has accepted current GT&C for current school
  Future<void> checkGTCAcceptance(String uid, String schoolId) async {
    if (_currentUid == uid && _acceptanceBySchool.containsKey(schoolId)) {
      //_currentSchoolId = schoolId;
      _currentAcceptance = _acceptanceBySchool[schoolId];
      return; // Already checked
    }

    _currentUid = uid;
    //_currentSchoolId = schoolId;

    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('gtc_acceptances')
          .doc(schoolId)
          .get();

      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          _acceptanceBySchool[schoolId] = data;
          _currentAcceptance = data;
        } else {
          _acceptanceBySchool.remove(schoolId);
          _currentAcceptance = null;
        }
      } else {
        _acceptanceBySchool.remove(schoolId);
        _currentAcceptance = null;
      }

      // Once accepted, always valid - no version re-check needed
      // The original acceptance timestamp is legally defensible
    } catch (e) {
      if (kDebugMode) print('Error checking GTC acceptance: $e');
      _currentAcceptance = null;
    }

    notifyListeners();
  }

  /// Accept GT&C and store acceptance record
  Future<bool> acceptGTC(String uid, String schoolId) async {
    final gtcData = _gtcBySchool[schoolId] ?? _currentGTC;
    if (gtcData == null) return false;

    try {
      final now = DateTime.now();
      final acceptance = {
        'gtc_accepted': true,
        'gtc_accepted_at': FieldValue.serverTimestamp(),
        'gtc_version': gtcData['gtc_version'] ?? '1.0',
      };

      await _firestore
          .collection('users')
          .doc(uid)
          .collection('gtc_acceptances')
          .doc(schoolId)
          .set(acceptance, SetOptions(merge: true));

      // Set local acceptance with current DateTime immediately (server timestamp will sync later)
      final localAcceptance = {
        'gtc_accepted': true,
        'gtc_accepted_at': now,
        'gtc_version': gtcData['gtc_version'] ?? '1.0',
      };
      _acceptanceBySchool[schoolId] = localAcceptance;
      _currentAcceptance = localAcceptance;
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) print('Error accepting GTC: $e');
      return false;
    }
  }

  /// Load all acceptance records for a user (across schools)
  Future<List<String>> loadUserAcceptances(String uid) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('gtc_acceptances')
          .get();

      for (final doc in snapshot.docs) {
        _acceptanceBySchool[doc.id] = doc.data();
      }

      _currentUid = uid;
      notifyListeners();
      return acceptedSchoolIds;
    } catch (e) {
      if (kDebugMode) print('Error loading GTC acceptances: $e');
      return acceptedSchoolIds;
    }
  }

  /// Reset GTC acceptance for a user/school (useful when GT&C updates)
  Future<void> resetGTCAcceptance(String uid, String schoolId) async {
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('gtc_acceptances')
          .doc(schoolId)
          .update({'gtc_accepted': false});

      _acceptanceBySchool.remove(schoolId);
      _currentAcceptance = null;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error resetting GTC acceptance: $e');
    }
  }

  /// Clear cached GT&C data
  void clearGTCCache() {
    _gtcBySchool.clear();
    _acceptanceBySchool.clear();
    _loadingSchools.clear();
    _currentGTC = null;
    _currentAcceptance = null;
    //_currentSchoolId = null;
    _currentUid = null;
    notifyListeners();
  }
}
