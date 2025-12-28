// File: lib/screens/dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:reorderables/reorderables.dart';

import '../models/dashboard_card_config.dart';
import '../services/stats_service.dart';
import '../services/profile_service.dart';
import '../services/app_config_service.dart';
import '../services/global_data_service.dart';
import '../services/dashboard_config_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isChecklistChartExpanded = false;
  bool _isManeuverChartExpanded = false;
  bool _isTakeoffPlacesChartExpanded = false;

  // Localization texts
  static const Map<String, Map<String, String>> _texts = {
    'Welcome': {'en': 'Welcome', 'de': 'Willkommen'},
    'Flights': {'en': 'Flights', 'de': 'Flüge'},
    'Takeoffs': {'en': 'Takeoffs', 'de': 'Starts'},
    'Landings': {'en': 'Landings', 'de': 'Landungen'},
    'Flying_Days': {'en': 'Flying days', 'de': 'Flugtage'},
    'Airtime': {'en': 'Airtime', 'de': 'Flugzeit'},
    'Cumm_Alt': {'en': 'Cumm. Alt.', 'de': 'Kumm. Höhe'},
    'Progress': {'en': 'Progress', 'de': 'Fortschritt'},
    'Checklist_Progress': {'en': 'Checklist Progress by Category', 'de': 'Checklisten-Fortschritt nach Kategorie'},
    'Click_Expand': {'en': 'Click to expand chart.', 'de': 'Zum Erweitern klicken.'},
    'Maneuver_Usage': {'en': 'Maneuver Usage Statistics', 'de': 'Manöver-Nutzungsstatistik'},
    'Top_Takeoff_Places': {'en': 'Top Takeoff Places', 'de': 'Top Start-Orte'},
    'No_Data': {'en': 'No data available', 'de': 'Keine Daten verfügbar'},
    'Times_Performed': {'en': 'times performed', 'de': 'mal durchgeführt'},
    'Flights_From': {'en': 'flights from here', 'de': 'Flüge von hier'},
  };

  String _t(String key, String lang) {
    return _texts[key]?[lang] ?? _texts[key]?['en'] ?? key;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statsService = context.watch<StatsService>();
    final profileService = context.watch<ProfileService>();
    final appConfig = context.watch<AppConfigService>();
    final globalData = context.watch<GlobalDataService>();
    final dashboardConfig = context.watch<DashboardConfigService>();
    final lang = appConfig.currentLanguageCode;

    final stats = statsService.stats;
    final nickname = profileService.userProfile?.nickname ?? 'Anonymous';

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: statsService.isLoading
          ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
          : ListView(
              children: [
                // Welcome message
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Center(
                    child: Text(
                      '${_t('Welcome', lang)}, $nickname',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Smart grid for all dashboard cards
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: _buildSmartCardGrid(
                    context,
                    stats,
                    lang,
                    theme,
                    globalData,
                    dashboardConfig,
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  /// Build a smart grid with 2x2 stats, 1x3 details, and expandable cards
  Widget _buildSmartCardGrid(
    BuildContext context,
    DashboardStats stats,
    String lang,
    ThemeData theme,
    GlobalDataService globalData,
    DashboardConfigService dashboardConfig,
  ) {
    final allCards = dashboardConfig.cards;
    if (allCards.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // Separate cards into three zones
    final group1 = ['flights', 'takeoffs', 'landings', 'flying_days'];
    final group2 = ['airtime', 'cumm_alt', 'progress'];
    final group3 = ['checklist', 'maneuver', 'takeoff'];

    final zone1Cards = allCards.where((c) => group1.contains(c.id)).toList();
    final zone2Cards = allCards.where((c) => group2.contains(c.id)).toList();
    final zone3Cards = allCards.where((c) => group3.contains(c.id)).toList();

    final hasExpandedCard = _isChecklistChartExpanded || _isManeuverChartExpanded || _isTakeoffPlacesChartExpanded;

    return PrimaryScrollController(
      controller: ScrollController(),
      child: Column(
        children: [
          // 2x2 Grid (stat cards)
          _buildZoneGrid(
          cards: zone1Cards,
          stats: stats,
          lang: lang,
          theme: theme,
          globalData: globalData,
          columnsPerRow: 2,
          onReorder: (oldIdx, newIdx) {
            if (!hasExpandedCard && oldIdx != newIdx) {
              setState(() {
                final item = zone1Cards.removeAt(oldIdx);
                zone1Cards.insert(newIdx, item);
                // Sync back to allCards maintaining order
                _syncCardOrder(allCards, zone1Cards + zone2Cards + zone3Cards);
                dashboardConfig.saveCardConfiguration();
              });
            }
          },
        ),
        const SizedBox(height: 16),

        // 1x3 Grid (detail cards)
        _buildZoneGrid(
          cards: zone2Cards,
          stats: stats,
          lang: lang,
          theme: theme,
          globalData: globalData,
          columnsPerRow: 3,
          onReorder: (oldIdx, newIdx) {
            if (!hasExpandedCard && oldIdx != newIdx) {
              setState(() {
                final item = zone2Cards.removeAt(oldIdx);
                zone2Cards.insert(newIdx, item);
                _syncCardOrder(allCards, zone1Cards + zone2Cards + zone3Cards);
                dashboardConfig.saveCardConfiguration();
              });
            }
          },
        ),
        const SizedBox(height: 16),

        // Expandable cards (full width, reorder only among themselves)
        _buildExpandableZone(
          cards: zone3Cards,
          stats: stats,
          lang: lang,
          theme: theme,
          globalData: globalData,
          hasExpandedCard: hasExpandedCard,
          onReorder: (oldIdx, newIdx) {
            if (!hasExpandedCard && oldIdx != newIdx) {
              setState(() {
                final item = zone3Cards.removeAt(oldIdx);
                zone3Cards.insert(newIdx, item);
                _syncCardOrder(allCards, zone1Cards + zone2Cards + zone3Cards);
                dashboardConfig.saveCardConfiguration();
              });
            }
          },
        ),
      ],
      ),
    );
  }

  /// Helper to sync reordered zones back to allCards
  void _syncCardOrder(
    List<DashboardCardConfig> allCards,
    List<DashboardCardConfig> reorderedCards,
  ) {
    allCards.clear();
    allCards.addAll(reorderedCards);
  }

  /// Build a grid zone (2x2 or 1x3) with proper grid snapping
  Widget _buildZoneGrid({
    required List<DashboardCardConfig> cards,
    required DashboardStats stats,
    required String lang,
    required ThemeData theme,
    required GlobalDataService globalData,
    required int columnsPerRow,
    required Function(int, int) onReorder,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = 12.0;
        final totalSpacing = spacing * (columnsPerRow - 1);
        final cardWidth = (constraints.maxWidth - totalSpacing) / columnsPerRow;
        final cardHeight = columnsPerRow == 2 ? 140.0 : 120.0;

        return ReorderableWrap(
          spacing: spacing,
          runSpacing: spacing,
          padding: EdgeInsets.zero,
          needsLongPressDraggable: true,
          onReorder: onReorder,
          children: [
            for (var i = 0; i < cards.length; i++)
              SizedBox(
                key: ValueKey(cards[i].id),
                width: cardWidth,
                height: cardHeight,
                child: _buildCardByType(
                  context: context,
                  cardId: cards[i].id,
                  stats: stats,
                  lang: lang,
                  theme: theme,
                  globalData: globalData,
                  isSmall: columnsPerRow == 3, // true for 1x3 grid
                ),
              ),
          ],
        );
      },
    );
  }

  /// Build expandable cards zone (full width, reorder only among themselves)
  Widget _buildExpandableZone({
    required List<DashboardCardConfig> cards,
    required DashboardStats stats,
    required String lang,
    required ThemeData theme,
    required GlobalDataService globalData,
    required bool hasExpandedCard,
    required Function(int, int) onReorder,
  }) {
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      onReorder: onReorder,
      children: [
        for (var i = 0; i < cards.length; i++)
          Container(
            key: ValueKey(cards[i].id),
            margin: const EdgeInsets.only(bottom: 12),
            child: ReorderableDragStartListener(
              index: i,
              enabled: !hasExpandedCard,
              child: _buildCardByType(
                context: context,
                cardId: cards[i].id,
                stats: stats,
                lang: lang,
                theme: theme,
                globalData: globalData,
                isSmall: false,
              ),
            ),
          ),
      ],
    );
  }

  /// Build card widget by type
  Widget _buildCardByType({
    required BuildContext context,
    required String cardId,
    required DashboardStats stats,
    required String lang,
    required ThemeData theme,
    required GlobalDataService globalData,
    bool isSmall = false,
  }) {
    return switch (cardId) {
      'flights' => isSmall
          ? _buildDetailedCard(context, _t('Flights', lang), '${stats.flightsCount}', Icons.flight, Colors.blue.shade700, theme)
          : _buildLargeStatsCard(context, _t('Flights', lang), '${stats.flightsCount}', Icons.flight, Colors.blue.shade700, theme),
      'takeoffs' => isSmall
          ? _buildDetailedCard(context, _t('Takeoffs', lang), '${stats.takeoffsCount}', Icons.flight_takeoff, Colors.orange.shade700, theme)
          : _buildLargeStatsCard(context, _t('Takeoffs', lang), '${stats.takeoffsCount}', Icons.flight_takeoff, Colors.orange.shade700, theme),
      'landings' => isSmall
          ? _buildDetailedCard(context, _t('Landings', lang), '${stats.landingsCount}', Icons.flight_land, Colors.green.shade700, theme)
          : _buildLargeStatsCard(context, _t('Landings', lang), '${stats.landingsCount}', Icons.flight_land, Colors.green.shade700, theme),
      'flying_days' => isSmall
          ? _buildDetailedCard(context, _t('Flying_Days', lang), '${stats.flyingDays}', Icons.calendar_today, Colors.purple.shade700, theme)
          : _buildLargeStatsCard(context, _t('Flying_Days', lang), '${stats.flyingDays}', Icons.calendar_today, Colors.purple.shade700, theme),
      'airtime' => _buildDetailedCard(context, _t('Airtime', lang), _formatAirtime(stats.airtimeMinutes), Icons.access_time, Colors.orange.shade700, theme),
      'cumm_alt' => _buildDetailedCard(context, _t('Cumm_Alt', lang), '${stats.cummAltDiff} m', Icons.height, Colors.purple.shade700, theme),
      'progress' => _buildDetailedCard(context, _t('Progress', lang), '${stats.progress.percentage} %', Icons.check_circle, Colors.blueGrey.shade700, theme),
      'checklist' => _buildChecklistProgressCard(context, stats, lang, theme, globalData),
      'maneuver' => _buildManeuverUsageCard(context, stats, lang, theme),
      'takeoff' => _buildTopTakeoffPlacesCard(context, stats, lang, theme),
      _ => const SizedBox.shrink(),
    };
  }

  String _formatAirtime(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '${hours}h ${mins}min';
  }

  /// Build large stat card (2x2 grid) - icon LEFT, stat RIGHT
  Widget _buildLargeStatsCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
    ThemeData theme,
  ) {
    return Card(
      elevation: 4,
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Container(
        height: 120,
        padding: const EdgeInsets.all(12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icon on left
            Icon(icon, color: Colors.white, size: 48),
            const SizedBox(width: 16),
            // Stat and text on right
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    textAlign: TextAlign.left,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build detailed card (for flexible layout)
  Widget _buildDetailedCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
    ThemeData theme,
  ) {
    return Card(
      elevation: 4,
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Container(
        padding: const EdgeInsets.all(12.0),
        height: 100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build Checklist Progress by Category Card
  Widget _buildChecklistProgressCard(
    BuildContext context,
    DashboardStats stats,
    String lang,
    ThemeData theme,
    GlobalDataService globalData,
  ) {
    return Card(
      elevation: 8,
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  _isChecklistChartExpanded = !_isChecklistChartExpanded;
                });
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _t('Checklist_Progress', lang),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    _isChecklistChartExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: theme.colorScheme.onSurface,
                    size: 28,
                  ),
                ],
              ),
            ),
            if (!_isChecklistChartExpanded) ...[
              const SizedBox(height: 4),
              Text(
                _t('Click_Expand', lang),
                style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14),
              ),
            ],
            if (_isChecklistChartExpanded) ...[
              const SizedBox(height: 20),
              _buildProgressChart(context, stats, globalData, theme),
              const SizedBox(height: 20),
              _buildProgressLegend(context, stats, globalData, lang, theme),
            ],
          ],
        ),
      ),
    );
  }

  /// Build progress chart
  Widget _buildProgressChart(
    BuildContext context,
    DashboardStats stats,
    GlobalDataService globalData,
    ThemeData theme,
  ) {
    const double chartHeight = 150.0;
    const double textHeight = 20.0;

    final categoryColors = <Color>[
      Colors.blue.shade400,
      Colors.cyan.shade400,
      Colors.orange.shade400,
      Colors.pink.shade400,
      Colors.purple.shade400,
      Colors.lightGreen.shade400,
      Colors.green.shade400,
      Colors.red.shade400,
    ];

    final data = <Map<String, dynamic>>[];
    int colorIndex = 0;

    for (final categoryId in GlobalDataService.categoryOrder) {
      final categoryProgress = stats.progress.categories[categoryId];
      if (categoryProgress != null) {
        data.add({
          'id': categoryId,
          'percent': categoryProgress.percent,
          'color': categoryColors[colorIndex % categoryColors.length],
        });
        colorIndex++;
      }
    }

    if (data.isEmpty) {
      return SizedBox(
        height: chartHeight,
        child: Center(
          child: Text(
            'No data available',
            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
        ),
      );
    }

    return SizedBox(
      height: chartHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: data.map((item) {
          final double percentage = (item['percent'] as int) / 100.0;
          final Color color = item['color'] as Color;

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '${item['percent']}%',
                    style: TextStyle(fontSize: 10, color: color),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: (chartHeight - textHeight) * percentage,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Build progress legend
  Widget _buildProgressLegend(
    BuildContext context,
    DashboardStats stats,
    GlobalDataService globalData,
    String lang,
    ThemeData theme,
  ) {
    final categoryColors = <Color>[
      Colors.blue.shade400,
      Colors.cyan.shade400,
      Colors.orange.shade400,
      Colors.pink.shade400,
      Colors.purple.shade400,
      Colors.lightGreen.shade400,
      Colors.green.shade400,
      Colors.red.shade400,
    ];

    final data = <Map<String, dynamic>>[];
    int colorIndex = 0;

    for (final categoryId in GlobalDataService.categoryOrder) {
      final categoryProgress = stats.progress.categories[categoryId];
      if (categoryProgress != null) {
        final label = globalData.getCategoryTitle(categoryId, lang);
        data.add({
          'id': categoryId,
          'label': label,
          'color': categoryColors[colorIndex % categoryColors.length],
        });
        colorIndex++;
      }
    }

    return Wrap(
      spacing: 12.0,
      runSpacing: 8.0,
      children: data.map((item) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              color: item['color'] as Color,
            ),
            const SizedBox(width: 6),
            Text(
              item['label'] as String,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  /// Build Maneuver Usage Card
  Widget _buildManeuverUsageCard(
    BuildContext context,
    DashboardStats stats,
    String lang,
    ThemeData theme,
  ) {
    return Card(
      elevation: 8,
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  _isManeuverChartExpanded = !_isManeuverChartExpanded;
                });
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _t('Maneuver_Usage', lang),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    _isManeuverChartExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: theme.colorScheme.onSurface,
                    size: 28,
                  ),
                ],
              ),
            ),
            if (!_isManeuverChartExpanded) ...[
              const SizedBox(height: 4),
              Text(
                _t('Click_Expand', lang),
                style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14),
              ),
            ],
            if (_isManeuverChartExpanded) ...[
              const SizedBox(height: 20),
              _buildManeuverChart(context, stats, lang, theme),
            ],
          ],
        ),
      ),
    );
  }

  /// Build maneuver usage bar chart
  Widget _buildManeuverChart(
    BuildContext context,
    DashboardStats stats,
    String lang,
    ThemeData theme,
  ) {
    if (stats.maneuverUsage.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text(
            _t('No_Data', lang),
            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
        ),
      );
    }

    // Sort by usage count
    final sortedManeuvers = stats.maneuverUsage.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final maxCount = sortedManeuvers.first.value;

    return Column(
      children: sortedManeuvers.map((entry) {
        final percentage = entry.value / maxCount;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      entry.key,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    '${entry.value} ${_t('Times_Performed', lang)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: percentage,
                backgroundColor: theme.colorScheme.surface,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade400),
                minHeight: 8,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// Build Top Takeoff Places Card
  Widget _buildTopTakeoffPlacesCard(
    BuildContext context,
    DashboardStats stats,
    String lang,
    ThemeData theme,
  ) {
    return Card(
      elevation: 8,
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  _isTakeoffPlacesChartExpanded = !_isTakeoffPlacesChartExpanded;
                });
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _t('Top_Takeoff_Places', lang),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    _isTakeoffPlacesChartExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: theme.colorScheme.onSurface,
                    size: 28,
                  ),
                ],
              ),
            ),
            if (!_isTakeoffPlacesChartExpanded) ...[
              const SizedBox(height: 4),
              Text(
                _t('Click_Expand', lang),
                style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14),
              ),
            ],
            if (_isTakeoffPlacesChartExpanded) ...[
              const SizedBox(height: 20),
              _buildTakeoffPlacesChart(context, stats, lang, theme),
            ],
          ],
        ),
      ),
    );
  }

  /// Build takeoff places bar chart
  Widget _buildTakeoffPlacesChart(
    BuildContext context,
    DashboardStats stats,
    String lang,
    ThemeData theme,
  ) {
    if (stats.topTakeoffPlaces.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text(
            _t('No_Data', lang),
            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
        ),
      );
    }

    // Show top 5 by default
    final topPlaces = stats.topTakeoffPlaces.take(5).toList();
    final maxCount = topPlaces.first.count;

    return Column(
      children: topPlaces.map((place) {
        final percentage = place.count / maxCount;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      place.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${place.count} ${_t('Flights_From', lang)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: percentage,
                backgroundColor: theme.colorScheme.surface,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade400),
                minHeight: 8,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
