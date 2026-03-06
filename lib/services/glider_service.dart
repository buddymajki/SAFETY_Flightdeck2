// File: lib/services/glider_service.dart

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_glider.dart';

/// Manages:
/// 1. Global glider catalog (from 'gliders' collection) - read-only
/// 2. User's own gliders (from 'users/{uid}/gliders' subcollection) - CRUD
class GliderService extends ChangeNotifier {
  static const String _globalGlidersCacheKey = 'global_gliders_cache';
  static const String _userGlidersCacheKey = 'user_gliders_cache';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Global glider catalog
  List<Map<String, dynamic>> _globalGliders = [];
  List<String> _brands = [];

  // User's own gliders
  List<UserGlider> _userGliders = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _userGlidersSubscription;

  bool _isLoading = false;
  String? _currentUid;

  // Getters
  List<Map<String, dynamic>> get globalGliders => List.unmodifiable(_globalGliders);
  List<String> get brands => List.unmodifiable(_brands);
  List<UserGlider> get userGliders => List.unmodifiable(_userGliders);
  bool get isLoading => _isLoading;

  GliderService() {
    _loadFromCacheOnly();
  }

  /// Get gliders filtered by brand
  List<Map<String, dynamic>> getGlidersByBrand(String brand) {
    return _globalGliders.where((g) => g['brand'] == brand).toList();
  }

  // --- Cache Management ---

  Future<void> _loadFromCacheOnly() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load global gliders cache
      final globalJson = prefs.getString(_globalGlidersCacheKey);
      if (globalJson != null) {
        final List<dynamic> decoded = json.decode(globalJson);
        _globalGliders = decoded.cast<Map<String, dynamic>>();
        _extractBrands();
        notifyListeners();
      }

      // Load user gliders cache
      final userJson = prefs.getString(_userGlidersCacheKey);
      if (userJson != null) {
        final List<dynamic> decoded = json.decode(userJson);
        _userGliders = decoded
            .map((item) => UserGlider.fromCache(item as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('[GliderService] Cache load error: $e');
    }
  }

  Future<void> _cacheGlobalGliders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_globalGlidersCacheKey, json.encode(_globalGliders));
    } catch (e) {
      debugPrint('[GliderService] Global cache write error: $e');
    }
  }

  Future<void> _cacheUserGliders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheable = _userGliders.map((g) => g.toCache()).toList();
      await prefs.setString(_userGlidersCacheKey, json.encode(cacheable));
    } catch (e) {
      debugPrint('[GliderService] User gliders cache write error: $e');
    }
  }

  void _extractBrands() {
    final brandSet = <String>{};
    for (final g in _globalGliders) {
      final brand = g['brand'] as String? ?? '';
      if (brand.isNotEmpty) brandSet.add(brand);
    }
    _brands = brandSet.toList()..sort();
  }

  // --- Initialization ---

  Future<void> initializeData(String uid) async {
    // Avoid redundant initialization
    if (_currentUid == uid) return;
    _currentUid = uid;
    _isLoading = true;
    notifyListeners();

    // Load global glider catalog
    await _loadGlobalGliders();

    // Subscribe to user's gliders
    await _userGlidersSubscription?.cancel();
    _userGlidersSubscription = _firestore
        .collection('users')
        .doc(uid)
        .collection('gliders')
        .snapshots()
        .listen(
      (snapshot) async {
        _userGliders = snapshot.docs
            .map((doc) => UserGlider.fromFirestore(doc.data(), doc.id))
            .toList();
        await _cacheUserGliders();
        notifyListeners();
      },
      onError: (e) {
        debugPrint('[GliderService] User gliders stream error: $e');
      },
    );

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadGlobalGliders() async {
    try {
      final snapshot = await _firestore.collection('gliders').get(
        const GetOptions(source: Source.serverAndCache),
      );
      _globalGliders = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
      _extractBrands();
      await _cacheGlobalGliders();
      notifyListeners();
    } catch (e) {
      debugPrint('[GliderService] Error loading global gliders: $e');
    }
  }

  // --- User Glider CRUD ---

  /// Add a glider to the user's collection
  Future<void> addUserGlider(UserGlider glider) async {
    if (_currentUid == null) return;
    await _firestore
        .collection('users')
        .doc(_currentUid)
        .collection('gliders')
        .add(glider.toFirestore());
    // The stream listener will automatically update _userGliders from Firestore
  }

  /// Remove a glider from the user's collection
  Future<void> removeUserGlider(String gliderId) async {
    if (_currentUid == null) return;
    await _firestore
        .collection('users')
        .doc(_currentUid)
        .collection('gliders')
        .doc(gliderId)
        .delete();
  }

  /// Reset service on logout
  Future<void> resetService() async {
    await _userGlidersSubscription?.cancel();
    _userGliders = [];
    _currentUid = null;
    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _userGlidersSubscription?.cancel();
    super.dispose();
  }
}
