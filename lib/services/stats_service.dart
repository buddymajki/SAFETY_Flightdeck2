// File: lib/services/stats_service.dart

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/flight.dart';

/// Dashboard statistics model
class DashboardStats {
  final int flightsCount;
  final int takeoffsCount;
  final int landingsCount;
  final int flyingDays;
  final int airtimeMinutes;
  final int cummAltDiff;
  final ProgressStats progress;
  final Map<String, int> maneuverUsage;
  final List<TakeoffPlaceStats> topTakeoffPlaces;
  final DateTime updatedAt;

  DashboardStats({
    this.flightsCount = 0,
    this.takeoffsCount = 0,
    this.landingsCount = 0,
    this.flyingDays = 0,
    this.airtimeMinutes = 0,
    this.cummAltDiff = 0,
    required this.progress,
    this.maneuverUsage = const {},
    this.topTakeoffPlaces = const [],
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'flightsCount': flightsCount,
      'takeoffsCount': takeoffsCount,
      'landingsCount': landingsCount,
      'flyingDays': flyingDays,
      'airtimeMinutes': airtimeMinutes,
      'cummAltDiff': cummAltDiff,
      'progress': progress.toJson(),
      'maneuverUsage': maneuverUsage,
      'topTakeoffPlaces': topTakeoffPlaces.map((t) => t.toJson()).toList(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      flightsCount: json['flightsCount'] as int? ?? 0,
      takeoffsCount: json['takeoffsCount'] as int? ?? 0,
      landingsCount: json['landingsCount'] as int? ?? 0,
      flyingDays: json['flyingDays'] as int? ?? 0,
      airtimeMinutes: json['airtimeMinutes'] as int? ?? 0,
      cummAltDiff: json['cummAltDiff'] as int? ?? 0,
      progress: ProgressStats.fromJson(json['progress'] as Map<String, dynamic>? ?? {}),
      maneuverUsage: Map<String, int>.from(json['maneuverUsage'] as Map<String, dynamic>? ?? {}),
      topTakeoffPlaces: (json['topTakeoffPlaces'] as List<dynamic>?)
              ?.map((t) => TakeoffPlaceStats.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      updatedAt: DateTime.parse(json['updatedAt'] as String? ?? DateTime.now().toIso8601String()),
    );
  }
}

/// Progress statistics with category breakdown
class ProgressStats {
  final int total;
  final int checked;
  final int percentage;
  final Map<String, CategoryProgress> categories;

  ProgressStats({
    this.total = 0,
    this.checked = 0,
    this.percentage = 0,
    this.categories = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'total': total,
      'checked': checked,
      'percentage': percentage,
      'categories': categories.map((k, v) => MapEntry(k, v.toJson())),
    };
  }

  factory ProgressStats.fromJson(Map<String, dynamic> json) {
    final categoriesData = json['categories'] as Map<String, dynamic>? ?? {};
    return ProgressStats(
      total: json['total'] as int? ?? 0,
      checked: json['checked'] as int? ?? 0,
      percentage: json['percentage'] as int? ?? 0,
      categories: categoriesData.map(
        (k, v) => MapEntry(k, CategoryProgress.fromJson(v as Map<String, dynamic>)),
      ),
    );
  }
}

/// Category progress details
class CategoryProgress {
  final String label;
  final int checked;
  final int total;
  final int percent;

  CategoryProgress({
    required this.label,
    this.checked = 0,
    this.total = 0,
    this.percent = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'checked': checked,
      'total': total,
      'percent': percent,
    };
  }

  factory CategoryProgress.fromJson(Map<String, dynamic> json) {
    return CategoryProgress(
      label: json['label'] as String? ?? '',
      checked: json['checked'] as int? ?? 0,
      total: json['total'] as int? ?? 0,
      percent: json['percent'] as int? ?? 0,
    );
  }
}

/// Takeoff place statistics
class TakeoffPlaceStats {
  final String name;
  final String? id;
  final int count;

  TakeoffPlaceStats({
    required this.name,
    this.id,
    required this.count,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'id': id,
      'count': count,
    };
  }

  factory TakeoffPlaceStats.fromJson(Map<String, dynamic> json) {
    return TakeoffPlaceStats(
      name: json['name'] as String? ?? '',
      id: json['id'] as String?,
      count: json['count'] as int? ?? 0,
    );
  }
}

/// StatsService: Offline-first dashboard statistics management
/// 
/// PRIMARY DATA SOURCE: Local in-memory data from FlightService and UserDataService
/// SECONDARY BACKUP: Firestore cloud document (for multi-device sync only)
/// 
/// Stats are calculated directly from service data and persisted locally.
/// Firestore is used only for backup and cross-device synchronization.
class StatsService extends ChangeNotifier {
  static const String _statsCacheKey = 'dashboard_stats';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  DashboardStats _stats = DashboardStats(progress: ProgressStats());
  bool _isLoading = false;
  String? _currentUid;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statsSubscription;
  Completer<void>? _initializationCompleter;

  // References to data services (set externally)
  dynamic flightService;
  dynamic userDataService;
  dynamic globalDataService;

  DashboardStats get stats => _stats;
  bool get isLoading => _isLoading;
  bool get isInitialized => _currentUid != null;

  StatsService() {
    _loadDataFromCacheOnly();
  }

  // --- Cache Management ---

  Future<void> _cacheStats(DashboardStats stats) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_statsCacheKey, json.encode(stats.toJson()));
    } catch (e) {
      debugPrint('[StatsService] Cache error: $e');
    }
  }

  Future<DashboardStats?> _getStatsFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_statsCacheKey);
      if (jsonString != null) {
        final Map<String, dynamic> decoded = json.decode(jsonString);
        return DashboardStats.fromJson(decoded);
      }
    } catch (e) {
      debugPrint('[StatsService] Cache read error: $e');
    }
    return null;
  }

  Future<void> _loadDataFromCacheOnly() async {
    final cached = await _getStatsFromCache();
    if (cached != null) {
      _stats = cached;
      notifyListeners();
    }
  }

  // --- Initialization & Stream Setup ---

  Future<void> initializeData(String uid) async {
    _isLoading = true;
    _currentUid = uid;

    // Load from local cache first (instant display)
    final cached = await _getStatsFromCache();
    if (cached != null) {
      _stats = cached;
    }

    notifyListeners();

    _initializationCompleter = Completer<void>();

    // Calculate stats from local data immediately
    await recalculateStats();

    _isLoading = false;
    notifyListeners();

    if (!_initializationCompleter!.isCompleted) {
      _initializationCompleter!.complete();
    }

    // Optional: Set up background sync listener (not used for primary data)
    // This is only for detecting cloud changes made from other devices
    await _statsSubscription?.cancel();
    _statsSubscription = _firestore
        .collection('users')
        .doc(uid)
        .collection('stats')
        .doc('dashboard')
        .snapshots()
        .listen(
      (snapshot) async {
        // Only update if remote data is newer than local
        if (snapshot.exists && snapshot.data() != null) {
          final remoteStats = DashboardStats.fromJson(snapshot.data()!);
          if (remoteStats.updatedAt.isAfter(_stats.updatedAt)) {
            debugPrint('[StatsService] Remote stats are newer, updating local cache');
            _stats = remoteStats;
            await _cacheStats(remoteStats);
            notifyListeners();
          }
        }
      },
      onError: (error) {
        debugPrint('[StatsService] Background sync error (ignored): $error');
        // Errors here are non-critical since local data is primary
      },
    );
  }

  /// Wait for initial data load
  Future<void> waitForInitialData() async {
    if (_initializationCompleter == null) return;
    await _initializationCompleter!.future;
  }

  // --- Stats Calculation ---

  /// Recalculate all stats from scratch (called when data changes)
  /// 
  /// CRITICAL: This method operates purely on local in-memory data.
  /// It reads from FlightService.flights and UserDataService without any Firestore calls.
  /// Stats are persisted locally first, then synced to Firestore in background.
  Future<void> recalculateStats() async {
    final uid = _currentUid ?? _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      // Get data from in-memory services (no Firestore calls)
      final flights = flightService?.flights as List<Flight>? ?? [];
      final progressData = userDataService?.userChecklistProgress as Map<String, Map<String, dynamic>>? ?? {};
      final checklistItems = globalDataService?.allChecklistItems ?? [];

      // Calculate flight stats from in-memory data
      final flightStats = _calculateFlightStats(flights);

      // Calculate progress stats from in-memory data
      final progressStats = _calculateProgressStatsFromItems(progressData, checklistItems);

      // Create new stats object
      final newStats = DashboardStats(
        flightsCount: flightStats['flightsCount'] as int,
        takeoffsCount: flightStats['takeoffsCount'] as int,
        landingsCount: flightStats['landingsCount'] as int,
        flyingDays: flightStats['flyingDays'] as int,
        airtimeMinutes: flightStats['airtimeMinutes'] as int,
        cummAltDiff: flightStats['cummAltDiff'] as int,
        progress: progressStats,
        maneuverUsage: flightStats['maneuverUsage'] as Map<String, int>,
        topTakeoffPlaces: flightStats['topTakeoffPlaces'] as List<TakeoffPlaceStats>,
        updatedAt: DateTime.now(),
      );

      // Update local state and cache immediately (PRIMARY)
      _stats = newStats;
      await _cacheStats(newStats);
      notifyListeners();

      // Sync to Firestore in background (SECONDARY - fire and forget)
      _syncToFirestoreBackground(uid, newStats);
    } catch (e) {
      debugPrint('[StatsService] Recalculation error: $e');
    }
  }

  /// Background sync to Firestore (non-blocking)
  void _syncToFirestoreBackground(String uid, DashboardStats stats) {
    _firestore
        .collection('users')
        .doc(uid)
        .collection('stats')
        .doc('dashboard')
        .set(stats.toJson(), SetOptions(merge: true))
        .then((_) {
      debugPrint('[StatsService] Stats synced to Firestore');
    }).catchError((error) {
      debugPrint('[StatsService] Firestore sync failed (non-critical): $error');
      // Failure here is acceptable - local data remains valid
    });
  }

  /// Calculate flight-related statistics
  Map<String, dynamic> _calculateFlightStats(List<Flight> flights) {
    final Set<String> uniqueTakeoffs = {};
    final Set<String> uniqueLandings = {};
    final Set<String> uniqueDays = {};
    int totalMinutes = 0;
    int totalAltDiff = 0;
    final Map<String, int> maneuverUsage = {};
    final Map<String, int> takeoffPlaceCounts = {};

    for (final flight in flights) {
      // Takeoffs - count unique places (use ID if available, otherwise name)
      final takeoffKey = (flight.takeoffId?.isNotEmpty ?? false) 
          ? flight.takeoffId! 
          : flight.takeoffName;
      if (takeoffKey.isNotEmpty) {
        uniqueTakeoffs.add(takeoffKey);
      }

      // Landings - count unique places (use ID if available, otherwise name)
      final landingKey = (flight.landingId?.isNotEmpty ?? false)
          ? flight.landingId!
          : flight.landingName;
      if (landingKey.isNotEmpty) {
        uniqueLandings.add(landingKey);
      }

      // Flying days
      try {
        final date = DateTime.parse(flight.date);
        final dayKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        uniqueDays.add(dayKey);
      } catch (e) {
        debugPrint('[StatsService] Date parse error: $e');
      }

      // Airtime
      totalMinutes += flight.flightTimeMinutes;

      // Altitude difference
      totalAltDiff += flight.altitudeDifference.toInt();

      // Maneuver usage
      for (final maneuver in [...flight.advancedManeuvers, ...flight.schoolManeuvers]) {
        maneuverUsage[maneuver] = (maneuverUsage[maneuver] ?? 0) + 1;
      }

      // Takeoff place counts (reuse takeoffKey already calculated above)
      if (takeoffKey.isNotEmpty) {
        takeoffPlaceCounts[takeoffKey] = (takeoffPlaceCounts[takeoffKey] ?? 0) + 1;
      }
    }

    // Sort and get top takeoff places
    final sortedTakeoffPlaces = takeoffPlaceCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topTakeoffPlaces = sortedTakeoffPlaces.take(10).map((entry) {
      // Try to find the full name from flights
      final flight = flights.firstWhere(
        (f) => (f.takeoffId == entry.key || f.takeoffName == entry.key),
        orElse: () => flights.first,
      );
      return TakeoffPlaceStats(
        name: flight.takeoffName,
        id: flight.takeoffId,
        count: entry.value,
      );
    }).toList();

    return {
      'flightsCount': flights.length,
      'takeoffsCount': uniqueTakeoffs.length,
      'landingsCount': uniqueLandings.length,
      'flyingDays': uniqueDays.length,
      'airtimeMinutes': totalMinutes,
      'cummAltDiff': totalAltDiff,
      'maneuverUsage': maneuverUsage,
      'topTakeoffPlaces': topTakeoffPlaces,
    };
  }

  /// Calculate progress statistics from ChecklistItem objects (in-memory)
  ProgressStats _calculateProgressStatsFromItems(
    Map<String, Map<String, dynamic>> progressData,
    List<dynamic> checklistItems,
  ) {
    // Group items by category
    final Map<String, List<String>> itemsByCategory = {};
    final Map<String, String> categoryLabels = {};

    for (final item in checklistItems) {
      // Handle both ChecklistItem objects and maps
      final String itemId;
      final String category;
      
      if (item is Map<String, dynamic>) {
        itemId = item['id'] as String? ?? '';
        category = item['category'] as String? ?? 'uncategorized';
      } else {
        // Assume it's a ChecklistItem object
        itemId = (item as dynamic).id as String;
        category = (item as dynamic).category as String? ?? 'uncategorized';
      }

      if (itemId.isEmpty) continue;

      itemsByCategory.putIfAbsent(category, () => []).add(itemId);

      // Store label if available (fallback to category id)
      if (!categoryLabels.containsKey(category)) {
        categoryLabels[category] = category;
      }
    }

    // Calculate category progress
    final Map<String, CategoryProgress> categories = {};
    int totalChecked = 0;

    itemsByCategory.forEach((categoryId, items) {
      int checkedCount = 0;
      for (final itemId in items) {
        final itemProgress = progressData[itemId];
        bool isCompleted = false;

        if (itemProgress != null) {
          isCompleted = itemProgress['completed'] as bool? ?? false;
        }

        if (isCompleted) {
          checkedCount++;
        }
      }

      totalChecked += checkedCount;
      final total = items.length;
      final percent = total > 0 ? ((checkedCount / total) * 100).round() : 0;

      categories[categoryId] = CategoryProgress(
        label: categoryLabels[categoryId] ?? categoryId,
        checked: checkedCount,
        total: total,
        percent: percent,
      );
    });

    final totalItems = checklistItems.length;
    final overallPercent = totalItems > 0 ? ((totalChecked / totalItems) * 100).round() : 0;

    return ProgressStats(
      total: totalItems,
      checked: totalChecked,
      percentage: overallPercent,
      categories: categories,
    );
  }

  /// Trigger stats update (called after flight/checklist changes)
  Future<void> updateStats() async {
    await recalculateStats();
  }

  /// Reset service state
  Future<void> waitForInitialData() async {
    if (_initializationCompleter == null) return;
    await _initializationCompleter!.future;
  }

  void resetService() {
    _statsSubscription?.cancel();
    _stats = DashboardStats(progress: ProgressStats());
    _isLoading = false;
    _currentUid = null;
    _initializationCompleter = null;
    notifyListeners();
  }

  /// Clear cache
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_statsCacheKey);
  }

  @override
  void dispose() {
    _statsSubscription?.cancel();
    super.dispose();
  }
}
