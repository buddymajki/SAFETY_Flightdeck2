/// Dashboard card configuration model
class DashboardCardConfig {
  final String id;
  final String nameKey; // Key for localization
  final int flexSize; // 1 = full width, 2 = half, 3 = third, etc.
  bool isVisible;
  int order;

  DashboardCardConfig({
    required this.id,
    required this.nameKey,
    required this.flexSize,
    this.isVisible = true,
    required this.order,
  });

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nameKey': nameKey,
      'flexSize': flexSize,
      'isVisible': isVisible,
      'order': order,
    };
  }

  /// Create from JSON
  factory DashboardCardConfig.fromJson(Map<String, dynamic> json) {
    return DashboardCardConfig(
      id: json['id'] as String,
      nameKey: json['nameKey'] as String,
      flexSize: json['flexSize'] as int,
      isVisible: json['isVisible'] as bool? ?? true,
      order: json['order'] as int,
    );
  }

  /// Create a copy with optional modifications
  DashboardCardConfig copyWith({
    String? id,
    String? nameKey,
    int? flexSize,
    bool? isVisible,
    int? order,
  }) {
    return DashboardCardConfig(
      id: id ?? this.id,
      nameKey: nameKey ?? this.nameKey,
      flexSize: flexSize ?? this.flexSize,
      isVisible: isVisible ?? this.isVisible,
      order: order ?? this.order,
    );
  }
}

/// Predefined dashboard cards
class DashboardCards {
  // Stats cards (2-column layout = flex 2)
  static final flights = DashboardCardConfig(
    id: 'flights',
    nameKey: 'Flights',
    flexSize: 2,
    order: 0,
  );

  static final takeoffs = DashboardCardConfig(
    id: 'takeoffs',
    nameKey: 'Takeoffs',
    flexSize: 2,
    order: 1,
  );

  static final landings = DashboardCardConfig(
    id: 'landings',
    nameKey: 'Landings',
    flexSize: 2,
    order: 2,
  );

  static final flyingDays = DashboardCardConfig(
    id: 'flying_days',
    nameKey: 'Flying_Days',
    flexSize: 2,
    order: 3,
  );

  static final airtime = DashboardCardConfig(
    id: 'airtime',
    nameKey: 'Airtime',
    flexSize: 3,
    order: 4,
  );

  static final cummAlt = DashboardCardConfig(
    id: 'cumm_alt',
    nameKey: 'Cumm_Alt',
    flexSize: 3,
    order: 5,
  );

  static final progress = DashboardCardConfig(
    id: 'progress',
    nameKey: 'Progress',
    flexSize: 3,
    order: 6,
  );

  // Expandable cards (full width = flex 1)
  static final checklistProgress = DashboardCardConfig(
    id: 'checklist',
    nameKey: 'Checklist_Progress',
    flexSize: 1,
    order: 7,
  );

  static final maneuverUsage = DashboardCardConfig(
    id: 'maneuver',
    nameKey: 'Maneuver_Usage',
    flexSize: 1,
    order: 8,
  );

  static final topTakeoffPlaces = DashboardCardConfig(
    id: 'takeoff',
    nameKey: 'Top_Takeoff_Places',
    flexSize: 1,
    order: 9,
  );

  /// Get all available cards in default order
  static List<DashboardCardConfig> getAllCards() {
    return [
      flights,
      takeoffs,
      landings,
      flyingDays,
      airtime,
      cummAlt,
      progress,
      checklistProgress,
      maneuverUsage,
      topTakeoffPlaces,
    ];
  }

  /// Get card by ID
  static DashboardCardConfig? getCardById(String id) {
    return getAllCards().firstWhere(
      (card) => card.id == id,
      orElse: () => throw Exception('Card not found: $id'),
    );
  }
}
