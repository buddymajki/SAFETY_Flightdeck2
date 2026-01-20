// File: lib/services/live_tracking_service.dart

// ignore_for_file: unused_field

import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tracked_flight.dart';
import 'profile_service.dart';

/// Service for live tracking - sends pilot position to cloud for authorities
/// 
/// Features:
/// - Sends position updates every 12 seconds (or 50m movement)
/// - Only active when pilot is in flight
/// - Includes pilot identification and credential status
/// - Automatically removes pilot from tracking when flight ends
class LiveTrackingService extends ChangeNotifier {
  static const String _enabledKey = 'live_tracking_enabled';
  
  // Throttling settings
  static const Duration minUploadInterval = Duration(seconds: 12);
  static const double minDistanceMeters = 50.0;
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // State
  bool _isEnabled = true;
  bool _isActive = false;  // Currently tracking (in flight)
  DateTime? _lastUploadTime;
  TrackPoint? _lastUploadedPosition;
  DateTime? _flightStartTime;
  String? _takeoffSiteName;
  
  // Cached profile data
  String? _uid;
  String? _shvNumber;
  String? _displayName;
  String? _licenseType;
  String? _glider;
  bool _membershipValid = false;
  bool _insuranceValid = false;
  
  // Getters
  bool get isEnabled => _isEnabled;
  bool get isActive => _isActive;
  DateTime? get lastUploadTime => _lastUploadTime;
  
  LiveTrackingService() {
    _loadSettings();
  }
  
  /// Load settings from SharedPreferences
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool(_enabledKey) ?? true;
      notifyListeners();
    } catch (e) {
      log('[LiveTrackingService] Error loading settings: $e');
    }
  }
  
  /// Save settings to SharedPreferences
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, _isEnabled);
    } catch (e) {
      log('[LiveTrackingService] Error saving settings: $e');
    }
  }
  
  /// Enable/disable live tracking
  Future<void> setEnabled(bool enabled) async {
    if (_isEnabled == enabled) return;
    _isEnabled = enabled;
    await _saveSettings();
    
    // If disabling while active, stop tracking
    if (!enabled && _isActive) {
      await stopTracking();
    }
    
    notifyListeners();
    log('[LiveTrackingService] Live tracking ${enabled ? 'enabled' : 'disabled'}');
  }
  
  /// Toggle live tracking
  Future<void> toggleEnabled() async {
    await setEnabled(!_isEnabled);
  }
  
  /// Initialize with user profile data
  /// Call this when user logs in or profile changes
  void updateProfile(UserProfile? profile) {
    if (profile == null) {
      log('[LiveTrackingService] Profile update: NULL profile received');
      _uid = null;
      _shvNumber = null;
      _displayName = null;
      _licenseType = null;
      _glider = null;
      return;
    }
    
    _uid = profile.uid;
    _shvNumber = profile.shvnumber;
    _displayName = profile.nickname ?? 
        '${profile.forename} ${profile.familyname}'.trim();
    _licenseType = profile.license;
    _glider = profile.glider;
    
    // Fetch membership and insurance status from Firestore
    _loadMembershipAndInsuranceStatus();
    
    log('[LiveTrackingService] ✓ Profile updated:');
    log('    UID: $_uid');
    log('    Name: $_displayName');
    log('    SHV: $_shvNumber');
    log('    License: $_licenseType');
    log('    Membership: $_membershipValid, Insurance: $_insuranceValid');
  }
  
  /// Fetch membership and insurance validity from Firestore
  Future<void> _loadMembershipAndInsuranceStatus() async {
    if (_uid == null) {
      print('📋 [LiveTracking] UID is null, cannot fetch membership/insurance status');
      _membershipValid = false;
      _insuranceValid = false;
      return;
    }
    
    try {
      print('📋 [LiveTracking] Fetching membership/insurance status from users/$_uid/');
      final doc = await _firestore.collection('users').doc(_uid).get();
      
      if (!doc.exists) {
        print('⚠️ [LiveTracking] User document not found in Firestore');
        _membershipValid = false;
        _insuranceValid = false;
        return;
      }
      
      final data = doc.data();
      _membershipValid = data?['membershipValid'] ?? false;
      _insuranceValid = data?['insuranceValid'] ?? false;
      
      print('✅ [LiveTracking] Membership/Insurance loaded:');
      print('   Membership: $_membershipValid');
      print('   Insurance: $_insuranceValid');
      log('[LiveTrackingService] Membership: $_membershipValid, Insurance: $_insuranceValid');
    } catch (e) {
      print('❌ [LiveTracking] Error fetching membership/insurance: $e');
      log('[LiveTrackingService] Error loading membership/insurance: $e');
      _membershipValid = false;
      _insuranceValid = false;
    }
  }
  
  /// Start live tracking (called when flight starts)
  Future<void> startTracking({
    String? takeoffSiteName,
  }) async {
    print('🛫 [LiveTracking] ========================================');
    print('🛫 [LiveTracking] startTracking called');
    print('🛫 [LiveTracking] Enabled: $_isEnabled');
    print('🛫 [LiveTracking] Currently active: $_isActive');
    
    if (!_isEnabled) {
      print('❌ [LiveTracking] Live tracking is DISABLED in settings');
      log('[LiveTrackingService] Live tracking disabled, not starting');
      return;
    }
    
    final user = _auth.currentUser;
    if (user == null) {
      print('❌ [LiveTracking] No authenticated user');
      log('[LiveTrackingService] ✗ No authenticated user, cannot start tracking');
      return;
    }
    
    _uid = user.uid;
    _isActive = true;
    _flightStartTime = DateTime.now();
    _takeoffSiteName = takeoffSiteName;
    _lastUploadTime = null;
    _lastUploadedPosition = null;
    
    print('✅ [LiveTracking] LIVE TRACKING STARTED!');
    print('✅ [LiveTracking] UID: $_uid');
    print('✅ [LiveTracking] Name: $_displayName');
    print('✅ [LiveTracking] Takeoff: $takeoffSiteName');
    print('🛫 [LiveTracking] ========================================');
    
    notifyListeners();
    log('[LiveTrackingService] ✓ Started live tracking from $takeoffSiteName (UID: $_uid, Profile: $_displayName)');
  }
  
  /// Stop live tracking (called when flight ends)
  Future<void> stopTracking() async {
    print('🛬 [LiveTracking] stopTracking called - active: $_isActive');
    
    if (!_isActive) {
      print('🛬 [LiveTracking] Not active, skipping');
      return;
    }

    _isActive = false;

    // Mark as not in flight (instead of deleting)
    print('🛬 [LiveTracking] Calling _markAsLanded...');
    await _markAsLanded();

    _flightStartTime = null;
    _takeoffSiteName = null;
    _lastUploadTime = null;
    _lastUploadedPosition = null;

    notifyListeners();
    print('🛬 [LiveTracking] Stopped live tracking - marked as landed');
    log('[LiveTrackingService] Stopped live tracking');
  }
  
  /// Mark pilot as landed (set inFlight = false)
  /// This keeps the document for history/statistics
  Future<void> _markAsLanded() async {
    print('🛬 [LiveTracking] _markAsLanded called, UID: $_uid');
    
    if (_uid == null) {
      print('🛬 [LiveTracking] UID is null, cannot mark as landed');
      return;
    }

    try {
      print('🛬 [LiveTracking] Updating Firestore document...');
      await _firestore.collection('live_tracking').doc(_uid).update({
        'inFlight': false,
        'landingTime': FieldValue.serverTimestamp(),
      });
      print('✅ [LiveTracking] ✓ Successfully marked as landed in Firestore');
      log('[LiveTrackingService] Marked as landed');
    } catch (e) {
      print('❌ [LiveTracking] ✗ Error marking as landed: $e');
    }
  }
  
  /// Process a position update
  /// Call this from FlightTrackingService.processPosition()
  Future<void> processPosition(TrackPoint position) async {
    // Debug: Always log when this is called
    print('🔵 [LiveTracking] processPosition called - enabled: $_isEnabled, active: $_isActive');
    
    if (!_isEnabled || !_isActive) {
      if (!_isActive) {
        // Silently skip if not active (expected behavior)
        return;
      }
      print('🔴 [LiveTracking] Skipping - enabled: $_isEnabled, active: $_isActive');
      return;
    }
    
    // TEMPORARY: Remove throttling - send EVERY position for debugging
    print('🟢 [LiveTracking] Sending position NOW (throttling disabled for debugging)');
    await _uploadPosition(position);
  }
  
  
  /// Upload position to Firestore
  Future<void> _uploadPosition(TrackPoint position) async {
    print('📍 [LiveTracking] _uploadPosition called');
    
    if (_uid == null) {
      print('❌ [LiveTracking] No UID, cannot upload position');
      log('[LiveTrackingService] No UID, cannot upload position');
      return;
    }
    
    print('📍 [LiveTracking] UID: $_uid');
    print('📍 [LiveTracking] Position: lat=${position.latitude}, lon=${position.longitude}, alt=${position.altitude}');
    
    try {
      final docRef = _firestore.collection('live_tracking').doc(_uid);
      
      final data = {
        'uid': _uid,
        'shvNumber': _shvNumber ?? '',
        'displayName': _displayName ?? 'Unknown',
        'membershipValid': _membershipValid,
        'insuranceValid': _insuranceValid,
        'licenseType': _licenseType ?? 'unknown',
        'latitude': position.latitude,
        'longitude': position.longitude,
        'altitude': position.altitude,
        'heading': position.heading,
        'speed': position.speed,
        'lastUpdate': FieldValue.serverTimestamp(),
        'flightStartTime': _flightStartTime != null 
            ? Timestamp.fromDate(_flightStartTime!) 
            : FieldValue.serverTimestamp(),
        'glider': _glider,
        'takeoffSite': _takeoffSiteName,
        'inFlight': true,  // IMPORTANT: Used to filter active flights in admin app
      };
      
      print('📤 [LiveTracking] Attempting to write to Firestore...');
      print('📤 [LiveTracking] Collection: live_tracking, Doc ID: $_uid');
      print('📤 [LiveTracking] Data: $data');
      
      await docRef.set(data, SetOptions(merge: false));
      
      _lastUploadTime = DateTime.now();
      _lastUploadedPosition = position;
      
      print('✅ [LiveTracking] SUCCESS! Position uploaded to Firestore');
      log('[LiveTrackingService] ✓ Position uploaded: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}, ${position.altitude.toStringAsFixed(0)}m');
    } catch (e, st) {
      print('❌ [LiveTracking] ERROR uploading position: $e');
      print('❌ [LiveTracking] Stack trace: $st');
      log('[LiveTrackingService] ✗ Error uploading position: $e');
      log('[LiveTrackingService] Stack trace: $st');
    }
  }
  
  /// Remove pilot from live tracking collection
  Future<void> _removeFromTracking() async {
    if (_uid == null) return;
    
    try {
      await _firestore.collection('live_tracking').doc(_uid).delete();
      log('[LiveTrackingService] Removed from live tracking');
    } catch (e) {
      log('[LiveTrackingService] Error removing from tracking: $e');
    }
  }
  
  
  
  /// Get current tracking status for UI display
  Map<String, dynamic> getStatus() {
    return {
      'enabled': _isEnabled,
      'active': _isActive,
      'lastUpload': _lastUploadTime?.toIso8601String(),
      'flightStart': _flightStartTime?.toIso8601String(),
      'takeoffSite': _takeoffSiteName,
    };
  }
  
  @override
  void dispose() {
    // Clean up: remove from tracking if still active
    if (_isActive) {
      _removeFromTracking();
    }
    super.dispose();
  }
}
