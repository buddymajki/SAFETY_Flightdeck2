// File: lib/screens/dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/stats_service.dart';
import '../services/profile_service.dart';
import '../services/app_config_service.dart';
import '../services/global_data_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isChecklistChartExpanded = false;
  bool _isManeuverChartExpanded = false;
  bool _isTakeoffPlacesChartExpanded = false;

  // Card order management
  late List<String> _cardOrder;

  static const String _cardOrderKey = 'dashboard_card_order';
  static const List<String> _defaultCardOrder = ['checklist', 'maneuver', 'takeoff'];

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
  void initState() {
    super.initState();
    _cardOrder = List.from(_defaultCardOrder);
    _loadCardOrder();
  }

  Future<void> _loadCardOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_cardOrderKey);
    if (saved != null && saved.length == _defaultCardOrder.length) {
      setState(() {
        _cardOrder = saved;
      });
    }
  }

  Future<void> _saveCardOrder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_cardOrderKey, _cardOrder);
  }

  void _onCardReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _cardOrder.removeAt(oldIndex);
      _cardOrder.insert(newIndex, item);
    });
    _saveCardOrder();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statsService = context.watch<StatsService>();
    final profileService = context.watch<ProfileService>();
    final appConfig = context.watch<AppConfigService>();
    final globalData = context.watch<GlobalDataService>();
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
                const SizedBox(height: 8),

                // Main stats grid (2x2)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: _buildStatsGrid(context, stats, lang, theme),
                ),
                const SizedBox(height: 24),

                // Detailed stats row (Airtime, Cumm. Alt., Progress)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: _buildDetailedStats(context, stats, lang, theme),
                ),
                const SizedBox(height: 32),

                // Drag hint (only show when cards are collapsed)
                if (!_isChecklistChartExpanded && !_isManeuverChartExpanded && !_isTakeoffPlacesChartExpanded)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      'Long-press cards to rearrange',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                // Reorderable cards
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    onReorder: _onCardReorder,
                    proxyDecorator: (child, index, animation) {
                      return AnimatedBuilder(
                        animation: animation,
                        builder: (BuildContext context, Widget? child) {
                          final double animValue = Curves.easeInOut.transform(animation.value);
                          
                          // Trigger haptics once at the start of drag
                          if (animValue > 0 && animValue < 0.05) {
                            HapticFeedback.mediumImpact();
                          }
                          
                          final double scale = 1.0 + (0.05 * animValue); // Scale up to 105%
                          
                          return Transform.scale(
                            scale: scale,
                            child: Opacity(
                              opacity: 0.95,
                              child: Material(
                                elevation: 8 + (8 * animValue), // Increase shadow
                                borderRadius: BorderRadius.circular(15),
                                color: Colors.transparent,
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: child,
                      );
                    },
                    children: List.generate(
                      _cardOrder.length,
                      (index) => _buildReorderableCard(
                        context,
                        stats,
                        lang,
                        theme,
                        globalData,
                        _cardOrder[index],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildReorderableCard(
    BuildContext context,
    DashboardStats stats,
    String lang,
    ThemeData theme,
    GlobalDataService globalData,
    String cardId,
  ) {
    final Key key = ValueKey(cardId);

    return Column(
      key: key,
      children: [
        _buildCardByType(
          context,
          cardId,
          stats,
          lang,
          theme,
          globalData,
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildCardByType(
    BuildContext context,
    String cardId,
    DashboardStats stats,
    String lang,
    ThemeData theme,
    GlobalDataService globalData,
  ) {
    return switch (cardId) {
      'checklist' => _buildChecklistProgressCard(context, stats, lang, theme, globalData),
      'maneuver' => _buildManeuverUsageCard(context, stats, lang, theme),
      'takeoff' => _buildTopTakeoffPlacesCard(context, stats, lang, theme),
      _ => const SizedBox.shrink(),
    };
  }

  /// Build the main 2x2 stats grid
  Widget _buildStatsGrid(BuildContext context, DashboardStats stats, String lang, ThemeData theme) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 16.0,
      crossAxisSpacing: 16.0,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard(
          context,
          _t('Flights', lang),
          stats.flightsCount.toString(),
          Icons.airplanemode_on,
          Colors.green.shade700,
          theme,
        ),
        _buildStatCard(
          context,
          _t('Takeoffs', lang),
          stats.takeoffsCount.toString(),
          Icons.flight_takeoff,
          Colors.blue.shade700,
          theme,
        ),
        _buildStatCard(
          context,
          _t('Landings', lang),
          stats.landingsCount.toString(),
          Icons.flight_land,
          Colors.green.shade600,
          theme,
        ),
        _buildStatCard(
          context,
          _t('Flying_Days', lang),
          stats.flyingDays.toString(),
          Icons.calendar_today,
          Colors.blue.shade400,
          theme,
        ),
      ],
    );
  }

  /// Build individual stat card
  Widget _buildStatCard(
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
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 2,
              child: FittedBox(
                fit: BoxFit.contain,
                child: Icon(icon, color: Colors.white),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                    ),
                    Text(
                      title,
                      style: const TextStyle(color: Colors.white70, fontSize: 18),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build detailed stats row
  Widget _buildDetailedStats(BuildContext context, DashboardStats stats, String lang, ThemeData theme) {
    final hours = stats.airtimeMinutes ~/ 60;
    final mins = stats.airtimeMinutes % 60;
    final airtimeStr = '${hours}h ${mins}min';
    final altStr = '${stats.cummAltDiff} m';
    final progressStr = '${stats.progress.percentage} %';

    return Row(
      children: [
        Expanded(
          child: _buildDetailedCard(
            context,
            _t('Airtime', lang),
            airtimeStr,
            Icons.access_time,
            Colors.orange.shade700,
            theme,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildDetailedCard(
            context,
            _t('Cumm_Alt', lang),
            altStr,
            Icons.height,
            Colors.purple.shade700,
            theme,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildDetailedCard(
            context,
            _t('Progress', lang),
            progressStr,
            Icons.check_circle,
            Colors.blueGrey.shade700,
            theme,
          ),
        ),
      ],
    );
  }

  /// Build detailed card
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
          children: [
            Flexible(
              flex: 1,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 4),
            Flexible(
              flex: 2,
              child: FittedBox(
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
        child: GestureDetector(
          onTap: () {
            setState(() {
              _isChecklistChartExpanded = !_isChecklistChartExpanded;
            });
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
        child: GestureDetector(
          onTap: () {
            setState(() {
              _isManeuverChartExpanded = !_isManeuverChartExpanded;
            });
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
        child: GestureDetector(
          onTap: () {
            setState(() {
              _isTakeoffPlacesChartExpanded = !_isTakeoffPlacesChartExpanded;
            });
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
