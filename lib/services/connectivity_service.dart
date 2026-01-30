// File: lib/services/connectivity_service.dart

import 'dart:async';
import 'dart:developer';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Callback type for connectivity change listeners
typedef ConnectivityCallback = void Function(bool isOnline);

/// Service for monitoring network connectivity
/// 
/// This service provides:
/// - Real-time connectivity status monitoring
/// - Callbacks when connectivity is restored (useful for syncing offline data)
/// - A simple API for checking current connectivity status
/// 
/// Usage:
/// ```dart
/// final connectivityService = ConnectivityService();
/// await connectivityService.initialize();
/// 
/// // Check current status
/// if (connectivityService.isOnline) {
///   // Do online operation
/// }
/// 
/// // Listen for connectivity restoration
/// connectivityService.addOnConnectivityRestoredCallback(() {
///   // Sync offline data
/// });
/// ```
class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._internal();
  
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  
  bool _isOnline = true; // Assume online initially
  bool _isInitialized = false;
  
  // Callbacks for when connectivity is restored
  final List<ConnectivityCallback> _connectivityCallbacks = [];
  
  factory ConnectivityService() {
    return _instance;
  }
  
  ConnectivityService._internal();
  
  // Getters
  bool get isOnline => _isOnline;
  bool get isOffline => !_isOnline;
  bool get isInitialized => _isInitialized;
  
  /// Initialize the connectivity service
  /// Call this at app startup
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Check initial connectivity status
      final results = await _connectivity.checkConnectivity();
      _updateConnectivityStatus(results);
      
      // Listen for connectivity changes
      _subscription = _connectivity.onConnectivityChanged.listen(
        _handleConnectivityChange,
        onError: (error) {
          log('[ConnectivityService] Stream error: $error');
        },
      );
      
      _isInitialized = true;
      log('[ConnectivityService] ✓ Initialized - Online: $_isOnline');
    } catch (e) {
      log('[ConnectivityService] ✗ Error initializing: $e');
      // Default to online if we can't check
      _isOnline = true;
      _isInitialized = true;
    }
  }
  
  /// Handle connectivity change events
  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final wasOnline = _isOnline;
    _updateConnectivityStatus(results);
    
    debugPrint('🌐 [Connectivity] Status changed: wasOnline=$wasOnline, isNowOnline=$_isOnline');
    
    // Check if connectivity was restored
    if (!wasOnline && _isOnline) {
      log('[ConnectivityService] ✓ Connectivity RESTORED!');
      debugPrint('🌐 [Connectivity] ✅ CONNECTIVITY RESTORED - Notifying ${_connectivityCallbacks.length} listeners');
      _notifyConnectivityRestored();
    } else if (wasOnline && !_isOnline) {
      log('[ConnectivityService] ✗ Connectivity LOST');
      debugPrint('🌐 [Connectivity] ❌ CONNECTIVITY LOST');
    }
    
    notifyListeners();
  }
  
  /// Update the connectivity status based on results
  void _updateConnectivityStatus(List<ConnectivityResult> results) {
    // Consider online if we have any connection that's not 'none'
    _isOnline = results.isNotEmpty && 
                !results.every((r) => r == ConnectivityResult.none);
  }
  
  /// Notify all registered callbacks that connectivity was restored
  void _notifyConnectivityRestored() {
    for (final callback in _connectivityCallbacks) {
      try {
        callback(true);
      } catch (e) {
        log('[ConnectivityService] Error in callback: $e');
      }
    }
  }
  
  /// Register a callback to be called when connectivity is restored
  /// Returns a function to unregister the callback
  VoidCallback addOnConnectivityChangedCallback(ConnectivityCallback callback) {
    _connectivityCallbacks.add(callback);
    return () => _connectivityCallbacks.remove(callback);
  }
  
  /// Remove a specific callback
  void removeCallback(ConnectivityCallback callback) {
    _connectivityCallbacks.remove(callback);
  }
  
  /// Check connectivity and return true if online
  /// This does an active check, not just returning cached status
  Future<bool> checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _updateConnectivityStatus(results);
      return _isOnline;
    } catch (e) {
      log('[ConnectivityService] Error checking connectivity: $e');
      return _isOnline; // Return cached status on error
    }
  }
  
  /// Force a sync attempt notification to all listeners
  /// Useful for manual retry buttons
  void triggerManualSync() {
    if (_isOnline) {
      debugPrint('🌐 [Connectivity] Manual sync triggered');
      _notifyConnectivityRestored();
    }
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    _connectivityCallbacks.clear();
    super.dispose();
  }
}
