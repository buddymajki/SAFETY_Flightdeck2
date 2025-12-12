// File: lib/services/profile_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// 1. UserProfile Model for type safety
class UserProfile {
  final String? uid;
  final String email;
  String familyname;
  String forename;
  String? nickname;
  String? phonenumber;
  DateTime? birthday;
  String? nationality;
  String? address1;
  String? address2;
  String? address3;
  String? address4; // Country
  String emergencyContactName; // REQUIRED
  String emergencyContactPhone; // REQUIRED
  int? height;
  int? weight;
  String? glider;
  String? shvnumber;
  String? license; // 'student' or 'pilot'
  String? schoolId;

  UserProfile({
    this.uid,
    required this.email,
    this.familyname = '',
    this.forename = '',
    this.nickname,
    this.phonenumber,
    this.birthday,
    this.nationality,
    this.address1,
    this.address2,
    this.address3,
    this.address4,
    this.emergencyContactName = '',
    this.emergencyContactPhone = '',
    this.height,
    this.weight,
    this.glider,
    this.shvnumber,
    this.license,
    this.schoolId,
  });

  factory UserProfile.fromFirestore(Map<String, dynamic> data, String uid, String email) {
    return UserProfile(
      uid: uid,
      email: email,
      familyname: data['familyname'] ?? '',
      forename: data['forename'] ?? '',
      nickname: data['nickname'],
      phonenumber: data['phonenumber'],
      // Handle various birthday types (Timestamp, String)
      birthday: data['birthday'] != null 
          ? (data['birthday'] is Timestamp 
              ? (data['birthday'] as Timestamp).toDate() 
              : (data['birthday'] is String 
                  ? DateTime.tryParse(data['birthday']) 
                  : null))
          : null,
      nationality: data['nationality'],
      address1: data['address1'],
      address2: data['address2'],
      address3: data['address3'],
      address4: data['address4'],
      emergencyContactName: data['emergency_contact_name'] ?? '',
      emergencyContactPhone: data['emergency_contact_phone'] ?? '',
      height: (data['height'] is int) ? data['height'] : (data['height'] is String ? int.tryParse(data['height']) : null),
      weight: (data['weight'] is int) ? data['weight'] : (data['weight'] is String ? int.tryParse(data['weight']) : null),
      glider: data['glider'],
      shvnumber: data['shvnumber'],
      license: data['license'],
      schoolId: data['school_id'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'familyname': familyname,
      'forename': forename,
      'nickname': nickname,
      'phonenumber': phonenumber,
      'birthday': birthday?.toIso8601String(), // Store as string for simplicity
      'nationality': nationality,
      'address1': address1,
      'address2': address2,
      'address3': address3,
      'address4': address4,
      'emergency_contact_name': emergencyContactName,
      'emergency_contact_phone': emergencyContactPhone,
      'height': height,
      'weight': weight,
      'glider': glider,
      'shvnumber': shvnumber,
      'license': license,
      'school_id': schoolId,
      // NOTE: Email is NOT saved here, as it's the User Auth field
    };
  }
}

// 2. ProfileService (ChangeNotifier)
class ProfileService extends ChangeNotifier {
  static const String _profileCacheKey = 'user_settings_profile';
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  UserProfile? _userProfile;
  List<Map<String, String>> _schools = [];
  bool _isLoading = false;

  UserProfile? get userProfile => _userProfile;
  List<Map<String, String>> get schools => _schools;
  bool get isLoading => _isLoading;
  String? get currentSchoolId => _userProfile?.schoolId;

  // Constructor: No automatic loading
  ProfileService();

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  // --- Caching Helper Methods ---

  Future<void> _cacheUserSettings(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileCacheKey, json.encode(settings));
  }

  Future<Map<String, dynamic>?> _getUsersSettingsFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_profileCacheKey);
    if (jsonString != null) {
      try {
        return json.decode(jsonString) as Map<String, dynamic>;
      } catch (e) {
        print("ProfileService: Error decoding cache: $e");
        return null;
      }
    }
    return null;
  }

  // --- Profile Data Handling (with Caching) ---
  
  Future<void> _loadUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) {
      _userProfile = null;
      notifyListeners();
      return;
    }

    final String userEmail = user.email!;
    final String userId = user.uid;

    // 1. Try to load from local cache first (instant loading)
    final cachedData = await _getUsersSettingsFromCache();
    if (cachedData != null) {
      _userProfile = UserProfile.fromFirestore(cachedData, userId, userEmail);
      notifyListeners(); // Update UI immediately with cached data
    } else {
      // Initialize with minimum data if no cache exists
      _userProfile = UserProfile(uid: userId, email: userEmail);
      notifyListeners(); 
    }

    // 2. Refresh data from Firestore (network operation)
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      
      if (userDoc.exists && userDoc.data() != null) {
        final Map<String, dynamic> firestoreData = userDoc.data()!;
        _userProfile = UserProfile.fromFirestore(firestoreData, userId, userEmail);
        
        // Cache the fresh data
        await _cacheUserSettings(firestoreData);
      }
      // If doc doesn't exist, we keep the basic profile initialized in step 1.

    } catch (e) {
      print("ProfileService: NETWORK ERROR loading user profile from Firebase: $e");
      // If network fails, we rely on the data loaded in step 1 (cached or basic init).
    } finally {
      // Ensure listeners are notified again if data was updated from Firestore
      notifyListeners(); 
    }
  }

  // Load all necessary global data (schools)
  Future<void> _loadSchools() async {
    // Schools list can also benefit from caching for instant offline access
    try {
      final snapshot = await _firestore.collection('schools').get(const GetOptions(source: Source.serverAndCache));
      _schools = snapshot.docs.map((doc) {
        return {
          'id': doc.id,
          'name': doc.data()['name'] as String? ?? 'Unknown School',
        };
      }).toList();
    } catch (e) {
      print("ProfileService: Error loading schools: $e");
      _schools = [];
    }
  }

  // Main loading method
  Future<void> _loadAllData() async {
    _setLoading(true);
    // Load profile and schools in parallel
    await Future.wait([
      _loadUserProfile(),
      _loadSchools(),
    ]);
    _setLoading(false);
  }

  /// Public initialization method called by ProxyProvider when user logs in
  Future<void> initializeData(String uid) async {
    _setLoading(true);
    try {
      // CRITICAL: Clear any stale cache before loading fresh data
      // This ensures that when a user signs back in, we don't use cached data from a previous session
      await clearCache();
      
      await Future.wait([
        _loadUserProfile(),
        _loadSchools(),
      ]);
    } finally {
      _setLoading(false);
    }
  }

  /// Reset service state when user logs out
  void resetService() {
    _userProfile = null;
    _schools = [];
    _isLoading = false;
    notifyListeners();
  }

  /// Clear cache from SharedPreferences
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileCacheKey);
  }

  // Update profile data in Firestore and cache
  Future<void> updateProfile(UserProfile updatedProfile) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not authenticated.");

    _userProfile = updatedProfile;
    // NOTE: This intentionally sets the user profile locally immediately for better UX
    notifyListeners(); 

    final Map<String, dynamic> firestorePayload = updatedProfile.toFirestore();

    try {
      await _firestore.collection('users').doc(user.uid).set(
        firestorePayload, 
        SetOptions(merge: true)
      );
      // Update cache immediately after successful Firestore write
      await _cacheUserSettings(firestorePayload);
      
    } catch (e) {
      print("ProfileService: Error updating profile: $e");
      // If save fails, we rely on the UI to display an error and potentially handle revert logic.
      rethrow;
    }
  }

  // --- Profile Completeness Guard Logic ---

  bool isProfileComplete() {
    if (_userProfile == null || _isLoading) return false;
    
    // Check all required fields as per your requirements
    return _userProfile!.familyname.isNotEmpty &&
           _userProfile!.forename.isNotEmpty &&
           _userProfile!.emergencyContactName.isNotEmpty &&
           _userProfile!.emergencyContactPhone.isNotEmpty &&
           _userProfile!.phonenumber != null && 
           _userProfile!.phonenumber!.isNotEmpty &&
           _userProfile!.address1 != null && 
           _userProfile!.address1!.isNotEmpty; // Address1 is considered required now
  }

  // --- Password Change ---
  
  Future<void> changePassword(String oldPassword, String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not authenticated.");

    final cred = EmailAuthProvider.credential(email: user.email!, password: oldPassword);
    
    // Re-authenticate user before changing password
    await user.reauthenticateWithCredential(cred);
    await user.updatePassword(newPassword);
  }
  
  Future<void> reloadData() => _loadAllData();
}