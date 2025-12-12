// File: lib/services/profile_service.dart

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 1. UserProfile Model for type safety
class UserProfile {
  final String? uid;
  final String email;
  String familyname;
  String forename;
  String? nickname;
  String? phonenumber;
  DateTime? birthday; // Marad Dart DateTime
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
      // JAVÍTÁS: Mindig a Timestamp formátumot várjuk FireStore-ból
      birthday: data['birthday'] != null
          ? (data['birthday'] is Timestamp
              ? (data['birthday'] as Timestamp).toDate()
              : null)
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

  // Segédmetódus a Stringek nullázására
  String? _toNullIfEmpty(String? s) => (s == null || s.isEmpty) ? null : s;

  Map<String, dynamic> toFirestore() {
    // Stringek nullázása és Timestamp konverzió a FireStore-nak
    return {
      'familyname': _toNullIfEmpty(familyname),
      'forename': _toNullIfEmpty(forename),
      'nickname': _toNullIfEmpty(nickname),
      'phonenumber': _toNullIfEmpty(phonenumber),
      // JAVÍTÁS: Timestamp formátum
      'birthday': birthday != null ? Timestamp.fromDate(birthday!) : null,
      'nationality': _toNullIfEmpty(nationality),
      'address1': _toNullIfEmpty(address1),
      'address2': _toNullIfEmpty(address2),
      'address3': _toNullIfEmpty(address3),
      'address4': _toNullIfEmpty(address4),
      'emergency_contact_name': _toNullIfEmpty(emergencyContactName),
      'emergency_contact_phone': _toNullIfEmpty(emergencyContactPhone),
      'height': height,
      'weight': weight,
      'glider': _toNullIfEmpty(glider),
      'shvnumber': _toNullIfEmpty(shvnumber),
      'license': _toNullIfEmpty(license),
      'school_id': _toNullIfEmpty(schoolId),
    };
  }

  /// Generate a patch containing only fields that differ from oldProfile
  Map<String, dynamic> getPatch(UserProfile oldProfile) {
    final newMap = toFirestore();
    final oldMap = oldProfile.toFirestore();
    final patch = <String, dynamic>{};

    for (final key in newMap.keys) {
      final newValue = newMap[key];
      final oldValue = oldMap[key];

      // Speciális Timestamp összehasonlítás a birthday mezőre
      if (key == 'birthday' && newValue is Timestamp && oldValue is Timestamp) {
        // Csak akkor jelöli meg, ha a millisecondsek eltérnek
        if (newValue.millisecondsSinceEpoch != oldValue.millisecondsSinceEpoch) {
          patch[key] = newValue;
        }
      } 
      // Általános összehasonlítás: minden más (String, int, null, bool)
      else if (newValue != oldValue) {
        patch[key] = newValue;
      }
    }

    debugPrint("ProfileService Patch: $patch");
    return patch;
  }
}

// 2. ProfileService (ChangeNotifier)
class ProfileService extends ChangeNotifier {
  static const String _profileCacheKey = 'user_settings_profile';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  UserProfile? _userProfile;
  UserProfile? _originalProfile; // Track baseline for patch generation
  List<Map<String, String>> _schools = [];
  bool _isLoading = false;
  final ValueNotifier<int> _syncSuccessNotifier = ValueNotifier<int>(0);
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSubscription;

  UserProfile? get userProfile => _userProfile;
  List<Map<String, String>> get schools => _schools;
  bool get isLoading => _isLoading;
  String? get currentSchoolId => _userProfile?.schoolId;
  ValueNotifier<int> get syncSuccessNotifier => _syncSuccessNotifier;

  // Constructor: kick off cache load immediately for fast startup
  ProfileService() {
    // Keep fast cache hydration for startup; stream will overwrite with fresh data
    _loadDataFromCacheOnly();
  }

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

  // --- Optimized cache-aside: load cached profile without auth dependency ---
  Future<void> _loadDataFromCacheOnly() async {
    final cachedData = await _getUsersSettingsFromCache();
    if (cachedData == null) return;

    final cachedEmail = cachedData['email'] as String? ?? '';
    final cachedUid = cachedData['uid'] as String? ?? '';
    _userProfile = UserProfile.fromFirestore(cachedData, cachedUid, cachedEmail);
  }

  // --- Profile Data Handling (Stream-based) ---

  // Load all necessary global data (schools)
  Future<void> _loadSchools() async {
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
  /// Public initialization method called by ProxyProvider when user logs in
  Future<bool> initializeData(String uid) async {
    _isLoading = true;
    notifyListeners();

    await _profileSubscription?.cancel();

    final profileCompleter = Completer<bool>();
    final schoolsCompleter = Completer<void>();
    bool firstEvent = true;

    _profileSubscription = _firestore.collection('users').doc(uid).snapshots().listen(
      (snapshot) async {
        final email = _auth.currentUser?.email ?? _userProfile?.email ?? '';

        if (snapshot.exists && snapshot.data() != null) {
          final Map<String, dynamic> firestoreData = {
            ...snapshot.data()!,
            'email': email,
            'uid': uid,
          };
          _userProfile = UserProfile.fromFirestore(firestoreData, uid, email);
          _originalProfile = UserProfile.fromFirestore(firestoreData, uid, email);
          
          await _cacheUserSettings(_userProfile!.toFirestore()); 
          
          // !!! ELTÁVOLÍTVA: A szinkronizációs értesítés itt már NEM történik meg !!!
          // _syncSuccessNotifier.value = _syncSuccessNotifier.value + 1; 
          
          if (!profileCompleter.isCompleted) profileCompleter.complete(true);
        } else {
          _userProfile ??= UserProfile(uid: uid, email: email);
          _originalProfile ??= UserProfile(uid: uid, email: email);
          if (!profileCompleter.isCompleted) profileCompleter.complete(false);
        }

        if (firstEvent) {
          firstEvent = false;
        }
        notifyListeners();
      },
      onError: (e) {
        debugPrint("ProfileService: STREAM ERROR loading user profile: $e");
        if (!profileCompleter.isCompleted) profileCompleter.complete(false);
        if (firstEvent) {
          firstEvent = false;
        }
      },
    );

    _loadSchools().then((_) {
      if (!schoolsCompleter.isCompleted) schoolsCompleter.complete();
    }).catchError((e) {
      debugPrint("ProfileService: Error loading schools in initializeData: $e");
      if (!schoolsCompleter.isCompleted) schoolsCompleter.complete();
    });

    final profileResult = await profileCompleter.future;
    await schoolsCompleter.future;

    _isLoading = false;
    notifyListeners();
    return profileResult;
  }

  /// Reset service state when user logs out
  Future<void> resetService() async {
    await _profileSubscription?.cancel();
    _userProfile = null;
    _originalProfile = null;
    _schools = [];
    _isLoading = false;
    await clearCache();
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

    final firestorePatch = _originalProfile != null
        ? updatedProfile.getPatch(_originalProfile!)
        : updatedProfile.toFirestore();

    if (firestorePatch.isEmpty) {
      debugPrint("ProfileService: No changes detected, skipping Firestore write.");
      return;
    }

    _userProfile = updatedProfile;
    notifyListeners();

    final Map<String, dynamic> cachePayload = updatedProfile.toFirestore();
    cachePayload['email'] = updatedProfile.email;
    cachePayload['uid'] = updatedProfile.uid;


    try {
      // Optimistic cache write (a teljes adatot mentjük a cache-be)
      await _cacheUserSettings(cachePayload);

      // Írás a FireStore-ba csak a patch-csel
      await _firestore.collection('users').doc(user.uid).set(
        firestorePatch,
        SetOptions(merge: true),
      );

      // Sikeres írás után frissítjük a baseline-t
      _originalProfile = UserProfile.fromFirestore(
        {...cachePayload},
        updatedProfile.uid ?? '',
        updatedProfile.email,
      );
    } catch (e) {
      debugPrint("ProfileService: Error updating profile: $e");
      rethrow;
    }
  }

  // --- Profile Completeness Guard Logic ---

  bool isProfileComplete() {
    if (_userProfile == null || _isLoading) return false;

    // Az összes kötelező mező ellenőrzése
    return _userProfile!.familyname.isNotEmpty &&
           _userProfile!.forename.isNotEmpty &&
           _userProfile!.emergencyContactName.isNotEmpty &&
           _userProfile!.emergencyContactPhone.isNotEmpty &&
           _userProfile!.phonenumber != null && _userProfile!.phonenumber!.isNotEmpty &&
           _userProfile!.address1 != null && _userProfile!.address1!.isNotEmpty;
  }

  // --- Password Change ---

  Future<void> changePassword(String oldPassword, String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not authenticated.");

    final cred = EmailAuthProvider.credential(email: user.email!, password: oldPassword);

    await user.reauthenticateWithCredential(cred);
    await user.updatePassword(newPassword);
  }

  Future<void> reloadData(String uid) async {
    await initializeData(uid);
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    _syncSuccessNotifier.value = 0;
    _syncSuccessNotifier.dispose();
    super.dispose();
  }
}