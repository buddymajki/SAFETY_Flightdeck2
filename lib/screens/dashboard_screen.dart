// File: lib/screens/dashboard_screen.dart

import 'dart:math' as math;
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
  bool _isStartTypeChartExpanded = false;

  // Year filter state for stats (null = all years)
  int? _selectedYear;

  // Card order management
  late List<String> _cardOrder;

  static const String _cardOrderKey = 'dashboard_card_order';
  static const List<String> _defaultCardOrder = ['checklist', 'maneuver', 'starttype', 'takeoff'];

  // Localization texts
  static const Map<String, Map<String, String>> _texts = {
    'Welcome': {'en': 'Welcome', 'de': 'Willkommen', 'it': 'Benvenuto', 'fr': 'Bienvenue'},
    'Flights': {'en': 'Flights', 'de': 'Flüge', 'it': 'Voli', 'fr': 'Vols'},
    'Takeoffs': {'en': 'Takeoffs', 'de': 'Starts', 'it': 'Decolli', 'fr': 'Décollages'},
    'Landings': {'en': 'Landings', 'de': 'Landungen', 'it': 'Atterraggi', 'fr': 'Atterrissages'},
    'Flying_Days': {'en': 'Flying days', 'de': 'Flugtage', 'it': 'Giorni di volo', 'fr': 'Jours de vol'},
    'Airtime': {'en': 'Airtime', 'de': 'Flugzeit', 'it': 'Tempo di volo', 'fr': 'Temps de vol'},
    'Cumm_Alt': {'en': 'Cumm. Alt.', 'de': 'Kumm. Höhe', 'it': 'Alt. cum.', 'fr': 'Alt. cum.'},
    'Progress': {'en': 'Progress', 'de': 'Fortschritt', 'it': 'Progresso', 'fr': 'Progrès'},
    'Checklist_Progress': {'en': 'Checklist Progress by Category', 'de': 'Checklisten-Fortschritt nach Kategorie', 'it': 'Progresso checklist per categoria', 'fr': 'Progrès checklist par catégorie'},
    'Click_Expand': {'en': 'Click to expand chart.', 'de': 'Zum Erweitern klicken.', 'it': 'Clicca per espandere il grafico.', 'fr': 'Cliquez pour agrandir le graphique.'},
    'Maneuver_Usage': {'en': 'Maneuver Usage Statistics', 'de': 'Manöver-Nutzungsstatistik', 'it': 'Statistiche manovre', 'fr': 'Statistiques des manœuvres'},
    'Start_Type_Usage': {'en': 'Takeoff Type Distribution', 'de': 'Starttyp-Verteilung', 'it': 'Distribuzione tipo decollo', 'fr': 'Distribution type de décollage'},
    'Top_Takeoff_Places': {'en': 'Top Takeoff Places', 'de': 'Top Start-Orte', 'it': 'Top luoghi di decollo', 'fr': 'Top lieux de décollage'},
    'No_Data': {'en': 'No data available', 'de': 'Keine Daten verfügbar', 'it': 'Nessun dato disponibile', 'fr': 'Aucune donnée disponible'},
    'Times_Performed': {'en': 'times performed', 'de': 'mal durchgeführt', 'it': 'volte eseguita', 'fr': 'fois effectué'},
    'Flights_From': {'en': 'flights from here', 'de': 'Flüge von hier', 'it': 'voli da qui', 'fr': 'vols d\'ici'},
    'Select_Year': {'en': 'Select Year', 'de': 'Jahr auswählen', 'it': 'Seleziona anno', 'fr': 'Sélectionner l\'année'},
    'All_Years': {'en': 'All Years', 'de': 'Alle Jahre', 'it': 'Tutti gli anni', 'fr': 'Toutes les années'},
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

                // Year filter selector
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: _buildYearSelector(context, statsService, lang, theme),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: _buildStatsGrid(context, statsService, lang, theme, _selectedYear),
                ),
                const SizedBox(height: 16),

                // Detailed stats row (Airtime, Cumm. Alt., Progress)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: _buildDetailedStats(context, statsService, lang, theme, _selectedYear),
                ),
                const SizedBox(height: 32),

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

                // Drag hint (only show when cards are collapsed)
                if (!_isChecklistChartExpanded && !_isManeuverChartExpanded && !_isTakeoffPlacesChartExpanded)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
    final statsService = context.read<StatsService>();
    final profileService = context.watch<ProfileService>();
    final userLicense = profileService.userProfile?.license;
    final isPilot = userLicense != null && userLicense.toLowerCase() == 'pilot';
    
    debugPrint('[Dashboard] _buildCardByType: cardId=$cardId, userLicense=$userLicense, isPilot=$isPilot');
    
    // Hide checklist card for Pilot license
    if (cardId == 'checklist' && isPilot) {
      return const SizedBox.shrink();
    }
    
    return switch (cardId) {
      'checklist' => _buildChecklistProgressCard(context, stats, lang, theme, globalData),
      'maneuver' => _buildManeuverUsageCard(context, stats, lang, theme, globalData, statsService, _selectedYear),
      'starttype' => _buildStartTypeUsageCard(context, stats, lang, theme, globalData, statsService, _selectedYear),
      'takeoff' => _buildTopTakeoffPlacesCard(context, stats, lang, theme, statsService, _selectedYear),
      _ => const SizedBox.shrink(),
    };
  }

  /// Build year filter selector
  Widget _buildYearSelector(
    BuildContext context,
    StatsService statsService,
    String lang,
    ThemeData theme,
  ) {
    final availableYears = statsService.getAvailableYearsFromFlights();
    debugPrint('[Dashboard] Year selector - Available years: $availableYears, Selected: $_selectedYear');
    
    // If _selectedYear is not in available years and not null, reset to null
    final safeSelectedYear = (_selectedYear == null || availableYears.contains(_selectedYear))
        ? _selectedYear
        : null;
    
    // If the safe value differs from current, schedule a reset
    if (safeSelectedYear != _selectedYear) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _selectedYear = safeSelectedYear;
          });
        }
      });
    }
    
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<int?>(
            initialValue: safeSelectedYear,
            decoration: InputDecoration(
              labelText: _t('Select_Year', lang),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: [
              DropdownMenuItem<int?>(
                value: null,
                child: Text(availableYears.isEmpty 
                    ? '(${_t('No_Data', lang)})' 
                    : _t('All_Years', lang)),
              ),
              ...availableYears.map(
                (year) => DropdownMenuItem<int?>(
                  value: year,
                  child: Text(year.toString()),
                ),
              ),
            ],
            onChanged: (value) {
              debugPrint('[Dashboard] Year changed: $_selectedYear -> $value');
              setState(() {
                _selectedYear = value;
              });
            },
          ),
        ),
      ],
    );
  }

  /// Build the main 2x2 stats grid
  Widget _buildStatsGrid(
    BuildContext context,
    StatsService statsService,
    String lang,
    ThemeData theme,
    int? selectedYear,
  ) {
    final mainStats = statsService.getMainStatsForYear(selectedYear);
    
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
          (mainStats['flightsCount'] as int).toString(),
          Icons.airplanemode_on,
          Colors.green.shade700,
          theme,
        ),
        _buildStatCard(
          context,
          _t('Takeoffs', lang),
          (mainStats['takeoffsCount'] as int).toString(),
          Icons.flight_takeoff,
          Colors.blue.shade700,
          theme,
        ),
        _buildStatCard(
          context,
          _t('Landings', lang),
          (mainStats['landingsCount'] as int).toString(),
          Icons.flight_land,
          Colors.green.shade600,
          theme,
        ),
        _buildStatCard(
          context,
          _t('Flying_Days', lang),
          (mainStats['flyingDays'] as int).toString(),
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
                child: Icon(icon, color: Colors.white, size: 40),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        value,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                      ),
                    ),
                  ),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        title,
                        style: const TextStyle(color: Colors.white70, fontSize: 18),
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build detailed stats row
  Widget _buildDetailedStats(
    BuildContext context,
    StatsService statsService,
    String lang,
    ThemeData theme,
    int? selectedYear,
  ) {
    final profileService = context.watch<ProfileService>();
    final userLicense = profileService.userProfile?.license;
    final isPilot = userLicense != null && userLicense.toLowerCase() == 'pilot';
    
    debugPrint('[Dashboard] _buildDetailedStats: userLicense=$userLicense, isPilot=$isPilot');
    
    final mainStats = statsService.getMainStatsForYear(selectedYear);
    final progress = statsService.getProgressForYear(selectedYear);
    
    final airtimeMinutes = mainStats['airtimeMinutes'] as int;
    final hours = airtimeMinutes ~/ 60;
    final mins = airtimeMinutes % 60;
    final airtimeStr = '${hours}h ${mins}min';
    final altStr = '${mainStats['cummAltDiff']} m';
    final progressStr = '${progress.percentage} %';

    // If Pilot, show only Airtime and Cumm. Alt. as stat cards in a 2-column grid (same as main stats grid)
    if (isPilot) {
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
            _t('Airtime', lang),
            airtimeStr,
            Icons.access_time, // clock icon
            Colors.orange.shade700,
            theme,
          ),
          _buildStatCard(
            context,
            _t('Cumm_Alt', lang),
            altStr,
            Icons.import_export, // up-down arrow icon
            Colors.purple.shade700,
            theme,
          ),
        ],
      );
    }

    // If Student, show all three cards in a 3-column grid
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 16.0,
      crossAxisSpacing: 16.0,
      childAspectRatio: 1.0,
      children: [
        _buildDetailedCard(
          context,
          _t('Airtime', lang),
          airtimeStr,
          Icons.access_time,
          Colors.orange.shade700,
          theme,
        ),
        _buildDetailedCard(
          context,
          _t('Cumm_Alt', lang),
          altStr,
          Icons.height,
          Colors.purple.shade700,
          theme,
        ),
        _buildDetailedCard(
          context,
          _t('Progress', lang),
          progressStr,
          Icons.check_circle,
          Colors.blueGrey.shade700,
          theme,
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
      child: Padding(
        padding: const EdgeInsets.all(12.0),
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
    GlobalDataService globalData,
    StatsService statsService,
    int? selectedYear,
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
                _buildManeuverChart(context, lang, theme, globalData, statsService, selectedYear),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Build maneuver usage bar chart with labels
  Widget _buildManeuverChart(
    BuildContext context,
    String lang,
    ThemeData theme,
    GlobalDataService globalData,
    StatsService statsService,
    int? selectedYear,
  ) {
    final maneuverUsage = statsService.getManeuverUsageForYear(selectedYear);

    if (maneuverUsage.isEmpty) {
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

    // Get maneuver labels from global data
    final maneuverList = globalData.globalManeuvers ?? [];
    final maneuverMap = {
      for (var m in maneuverList)
        if (m.containsKey('id'))
          m['id'] as String: m
    };
    
    // Sort by usage count
    final sortedManeuvers = maneuverUsage.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final maxCount = sortedManeuvers.first.value;

    return Column(
      children: sortedManeuvers.map((entry) {
        final percentage = entry.value / maxCount;
        
        // Get maneuver label from global data, fallback to ID if not found
        String displayLabel = entry.key;
        if (maneuverMap.containsKey(entry.key)) {
          final maneuverData = maneuverMap[entry.key] as Map<String, dynamic>;
          if (maneuverData.containsKey('labels')) {
            final labels = maneuverData['labels'];
            if (labels is Map<String, dynamic> && labels.containsKey(lang)) {
              displayLabel = labels[lang] as String;
            }
          }
        }
        
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
                      displayLabel,
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

  /// Build Start Type Usage Card (Pie Chart)
  Widget _buildStartTypeUsageCard(
    BuildContext context,
    DashboardStats stats,
    String lang,
    ThemeData theme,
    GlobalDataService globalData,
    StatsService statsService,
    int? selectedYear,
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
              _isStartTypeChartExpanded = !_isStartTypeChartExpanded;
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
                      _t('Start_Type_Usage', lang),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    _isStartTypeChartExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: theme.colorScheme.onSurface,
                    size: 28,
                  ),
                ],
              ),
              if (!_isStartTypeChartExpanded) ...[
                const SizedBox(height: 4),
                Text(
                  _t('Click_Expand', lang),
                  style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14),
                ),
              ],
              if (_isStartTypeChartExpanded) ...[
                const SizedBox(height: 20),
                _buildStartTypeChart(context, lang, theme, globalData, statsService, selectedYear),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Build start type usage pie chart
  Widget _buildStartTypeChart(
    BuildContext context,
    String lang,
    ThemeData theme,
    GlobalDataService globalData,
    StatsService statsService,
    int? selectedYear,
  ) {
    final startTypeUsage = statsService.getStartTypeUsageForYear(selectedYear);

    if (startTypeUsage.isEmpty) {
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

    // Get start type labels from global data
    final startTypeList = globalData.globalStarttypes ?? [];
    final startTypeMap = {
      for (var st in startTypeList)
        if (st.containsKey('id'))
          st['id'] as String: st
    };

    // Sort by count
    final sortedStartTypes = startTypeUsage.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final totalCount = sortedStartTypes.fold<int>(0, (sum, entry) => sum + entry.value);

    // Define colors for pie chart
    final colors = [Colors.blue.shade400, Colors.orange.shade400];

    return Column(
      children: [
        // Simple pie chart representation with two sections
        SizedBox(
          width: double.infinity,
          height: 200,
          child: CustomPaint(
            painter: SimplePieChartPainter(
              data: sortedStartTypes.map((e) => e.value.toDouble()).toList(),
              colors: colors,
              total: totalCount.toDouble(),
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Legend with counts
        Column(
          children: sortedStartTypes.asMap().entries.map((indexEntry) {
            final index = indexEntry.key;
            final entry = indexEntry.value;
            
            // Get start type label
            String displayLabel = entry.key;
            if (startTypeMap.containsKey(entry.key)) {
              final startTypeData = startTypeMap[entry.key] as Map<String, dynamic>;
              if (startTypeData.containsKey('labels')) {
                final labels = startTypeData['labels'];
                if (labels is Map<String, dynamic> && labels.containsKey(lang)) {
                  displayLabel = labels[lang] as String;
                }
              }
            }
            
            final percentage = (entry.value / totalCount * 100).toStringAsFixed(1);
            
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: colors[index % colors.length],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        displayLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${entry.value} ($percentage%)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// Build Top Takeoff Places Card
  Widget _buildTopTakeoffPlacesCard(
    BuildContext context,
    DashboardStats stats,
    String lang,
    ThemeData theme,
    StatsService statsService,
    int? selectedYear,
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
                _buildTakeoffPlacesChart(context, lang, theme, statsService, selectedYear),
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
    String lang,
    ThemeData theme,
    StatsService statsService,
    int? selectedYear,
  ) {
    final topTakeoffPlaces = statsService.getTopTakeoffPlacesForYear(selectedYear);

    if (topTakeoffPlaces.isEmpty) {
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
    final topPlaces = topTakeoffPlaces.take(5).toList();
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

/// Simple pie chart painter for visualizing start type distribution
class SimplePieChartPainter extends CustomPainter {
  final List<double> data;
  final List<Color> colors;
  final double total;

  SimplePieChartPainter({
    required this.data,
    required this.colors,
    required this.total,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || total == 0) return;

    final paint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF1a1a2e); // Dark background color
    
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 15;

    var startAngle = -math.pi / 2; // Start at top

    for (int i = 0; i < data.length; i++) {
      final sweepAngle = (data[i] / total) * 2 * math.pi;
      paint.color = colors[i % colors.length];

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );
      
      // Draw stroke to separate slices
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        strokePaint,
      );

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(SimplePieChartPainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.colors != colors;
  }
}