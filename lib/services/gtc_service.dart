import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class GTCService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cache GT&C data and acceptance status
  Map<String, dynamic>? _currentGTC;
  Map<String, dynamic>? _currentAcceptance;
  bool _isLoading = false;
  String? _currentSchoolId;
  String? _currentUid;

  // Getters
  Map<String, dynamic>? get currentGTC => _currentGTC;
  Map<String, dynamic>? get currentAcceptance => _currentAcceptance;
  bool get isLoading => _isLoading;
  bool get isGTCAccepted => _currentAcceptance?['gtc_accepted'] ?? false;
  String? get currentGTCVersion => _currentGTC?['gtc_version'] as String?;

  /// Fetch GT&C for a specific school
  Future<void> loadGTC(String schoolId) async {
    if (_currentSchoolId == schoolId && _currentGTC != null) {
      debugPrint('[GTCService] GT&C already cached for school: $schoolId');
      return; // Already loaded
    }

    _isLoading = true;
    notifyListeners();

    try {
      debugPrint('[GTCService] Loading GT&C for school: $schoolId');
      final doc = await _firestore.collection('schools').doc(schoolId).get();
      if (doc.exists) {
        _currentGTC = doc.data() as Map<String, dynamic>?;
        _currentSchoolId = schoolId;
        final gtcSections = (_currentGTC?['gtc_sections'] as List?)?.length ?? 0;
        debugPrint('[GTCService] Loaded GT&C with $gtcSections sections');
      } else {
        debugPrint('[GTCService] School document not found: $schoolId');
        _currentGTC = null;
      }
    } catch (e) {
      debugPrint('[GTCService] Error loading GT&C: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Check if user has accepted current GT&C for current school
  Future<void> checkGTCAcceptance(String uid, String schoolId) async {
    if (_currentUid == uid && _currentSchoolId == schoolId) {
      return; // Already checked
    }

    _currentUid = uid;
    _currentSchoolId = schoolId;

    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('gtc_acceptances')
          .doc(schoolId)
          .get();

      if (doc.exists) {
        _currentAcceptance = doc.data() as Map<String, dynamic>?;
      } else {
        _currentAcceptance = null;
      }

      // Check if acceptance version matches current GTC version
      if (_currentAcceptance != null && _currentGTC != null) {
        final acceptedVersion = _currentAcceptance?['gtc_version'] as String?;
        final currentVersion = _currentGTC?['gtc_version'] as String?;
        if (acceptedVersion != currentVersion) {
          // Version mismatch, force re-acceptance
          _currentAcceptance = null;
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error checking GTC acceptance: $e');
      _currentAcceptance = null;
    }

    notifyListeners();
  }

  /// Accept GT&C and store acceptance record
  Future<bool> acceptGTC(String uid, String schoolId) async {
    if (_currentGTC == null) return false;

    try {
      final acceptance = {
        'gtc_accepted': true,
        'gtc_accepted_at': FieldValue.serverTimestamp(),
        'gtc_version': _currentGTC?['gtc_version'] ?? '1.0',
      };

      await _firestore
          .collection('users')
          .doc(uid)
          .collection('gtc_acceptances')
          .doc(schoolId)
          .set(acceptance, SetOptions(merge: true));

      _currentAcceptance = acceptance;
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) print('Error accepting GTC: $e');
      return false;
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

      _currentAcceptance = null;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error resetting GTC acceptance: $e');
    }
  }

  /// Clear cached GT&C data
  void clearGTCCache() {
    _currentGTC = null;
    _currentAcceptance = null;
    _currentSchoolId = null;
    _currentUid = null;
    notifyListeners();
  }
}
