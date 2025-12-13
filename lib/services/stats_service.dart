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
class StatsService extends ChangeNotifier {
  static const String _statsCacheKey = 'dashboard_stats';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  DashboardStats _stats = DashboardStats(progress: ProgressStats());
  bool _isLoading = false;
  String? _currentUid;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statsSubscription;
  Completer<void>? _initializationCompleter;

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

    notifyListeners();

    _initializationCompleter = Completer<void>();

    await _statsSubscription?.cancel();

    _statsSubscription = _firestore
        .collection('users')
        .doc(uid)
        .collection('stats')
        .doc('dashboard')
        .snapshots()
        .listen(
      (snapshot) async {
        if (snapshot.exists && snapshot.data() != null) {
          final stats = DashboardStats.fromJson(snapshot.data()!);
          _stats = stats;
          await _cacheStats(stats);
        } else {
          // No stats document yet, calculate initial stats
          await recalculateStats();
        }

        _isLoading = false;
        notifyListeners();

        if (!_initializationCompleter!.isCompleted) {
          _initializationCompleter!.complete();
        }
      },
      onError: (error) {
        debugPrint('[StatsService] Stream error: $error');
        _isLoading = false;
        notifyListeners();
        if (!_initializationCompleter!.isCompleted) {
          _initializationCompleter!.complete();
        }
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
  Future<void> recalculateStats() async {
    final uid = _currentUid ?? _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      // Fetch all required data
      final flightsSnapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('flightlog')
          .get(GetOptions(source: Source.cache));

      final progressSnapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('checklistprogress')
          .doc('progress')
          .get(GetOptions(source: Source.cache));

      final globalChecklistsSnapshot = await _firestore
          .collection('globalChecklists')
          .get(GetOptions(source: Source.cache));

      // Parse flights
      final flights = flightsSnapshot.docs
          .map((doc) => Flight.fromFirestore(doc.data(), doc.id, uid))
          .toList();

      // Calculate flight stats
      final flightStats = _calculateFlightStats(flights);

      // Calculate progress stats
      final progressData = progressSnapshot.data() ?? {};
      final checklistItems = globalChecklistsSnapshot.docs;
      final progressStats = _calculateProgressStats(progressData, checklistItems);

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

      // Update local state and cache immediately
      _stats = newStats;
      await _cacheStats(newStats);
      notifyListeners();

      // Update Firestore in background
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('stats')
          .doc('dashboard')
          .set(newStats.toJson(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('[StatsService] Recalculation error: $e');
    }
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
      // Takeoffs
      if (flight.takeoffId != null && flight.takeoffId!.isNotEmpty) {
        uniqueTakeoffs.add(flight.takeoffId!);
      }

      // Landings
      if (flight.landingId != null && flight.landingId!.isNotEmpty) {
        uniqueLandings.add(flight.landingId!);
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

      // Takeoff place counts
      final takeoffKey = flight.takeoffId ?? flight.takeoffName;
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

  /// Calculate progress statistics with category breakdown
  ProgressStats _calculateProgressStats(
    Map<String, dynamic> progressData,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> checklistItems,
  ) {
    // Group items by category
    final Map<String, List<String>> itemsByCategory = {};
    final Map<String, String> categoryLabels = {};

    for (final doc in checklistItems) {
      final data = doc.data();
      final category = data['category'] as String? ?? 'uncategorized';
      final itemId = doc.id;

      itemsByCategory.putIfAbsent(category, () => []).add(itemId);

      // Store label if available (fallback to category id)
      if (!categoryLabels.containsKey(category)) {
        categoryLabels[category] = data['category_label'] as String? ?? category;
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

        if (itemProgress is bool) {
          isCompleted = itemProgress;
        } else if (itemProgress is Map<String, dynamic>) {
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
