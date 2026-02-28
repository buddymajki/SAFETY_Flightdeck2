// File: lib/screens/calendar_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../config/app_theme.dart';
import '../models/calendar_event.dart';
import '../services/calendar_service.dart';
import '../services/app_config_service.dart';
import '../services/profile_service.dart';
import '../widgets/event_detail_sheet.dart';

// ─────────────────── Localization ───────────────────
const Map<String, Map<String, String>> _calTexts = {
  'title': {'en': 'Calendar', 'de': 'Kalender', 'it': 'Calendario', 'fr': 'Calendrier'},
  'upcoming': {'en': 'Upcoming Events', 'de': 'Kommende Events', 'it': 'Prossimi eventi', 'fr': 'Événements à venir'},
  'no_events': {
    'en': 'No upcoming events',
    'de': 'Keine kommenden Events',
    'it': 'Nessun evento in programma',
    'fr': 'Aucun événement à venir',
  },
  'no_events_day': {
    'en': 'No events on this day',
    'de': 'Keine Events an diesem Tag',
    'it': 'Nessun evento in questo giorno',
    'fr': 'Aucun événement ce jour',
  },
  'registered': {'en': 'Registered', 'de': 'Angemeldet', 'it': 'Iscritto', 'fr': 'Inscrit'},
  'sign_up': {'en': 'Sign up', 'de': 'Anmelden', 'it': 'Iscriviti', 'fr': 'S\'inscrire'},
  'participants': {'en': 'participants', 'de': 'Teilnehmer', 'it': 'partecipanti', 'fr': 'participants'},
  'today': {'en': 'Today', 'de': 'Heute', 'it': 'Oggi', 'fr': 'Aujourd\'hui'},
  'tomorrow': {'en': 'Tomorrow', 'de': 'Morgen', 'it': 'Domani', 'fr': 'Demain'},
  'loading': {'en': 'Loading events...', 'de': 'Events laden...', 'it': 'Caricamento eventi...', 'fr': 'Chargement des événements...'},
  'no_school': {
    'en': 'Please set your school in Profile first',
    'de': 'Bitte zuerst die Schule im Profil festlegen',
    'it': 'Imposta prima la tua scuola nel Profilo',
    'fr': 'Veuillez d\'abord définir votre école dans le Profil',
  },
};

String _t(String key, String lang) {
  return _calTexts[key]?[lang] ?? _calTexts[key]?['en'] ?? key;
}

// ─────────────────── Screen ───────────────────

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> with SingleTickerProviderStateMixin {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedDay = DateTime.now();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppConfigService>().displayLanguageCode;
    final calendarService = context.watch<CalendarService>();
    final profileService = context.watch<ProfileService>();
    final theme = Theme.of(context);
    final schoolId = profileService.userProfile?.mainSchoolId;

    // No school set
    if (schoolId == null || schoolId.isEmpty) {
      return _buildEmptyState(theme, _t('no_school', lang), Icons.school_outlined);
    }

    // Not initialized yet
    if (!calendarService.isInitialized) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_t('loading', lang), style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          // Tab bar: Calendar / List
          Container(
            color: AppTheme.navBarColor,
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppTheme.primaryColor,
              labelColor: AppTheme.primaryColor,
              unselectedLabelColor: Colors.grey.shade400,
              tabs: [
                Tab(icon: const Icon(Icons.calendar_month), text: _t('title', lang)),
                Tab(icon: const Icon(Icons.list_alt), text: _t('upcoming', lang)),
              ],
            ),
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCalendarView(context, calendarService, lang, theme),
                _buildListView(context, calendarService, lang, theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────── Calendar View ───────────────────

  Widget _buildCalendarView(
    BuildContext context,
    CalendarService service,
    String lang,
    ThemeData theme,
  ) {
    final selectedEvents = _selectedDay != null ? service.eventsForDay(_selectedDay!) : <CalendarEvent>[];

    return Column(
      children: [
        // Calendar widget
        TableCalendar<CalendarEvent>(
          firstDay: DateTime.now().subtract(const Duration(days: 30)),
          lastDay: DateTime.now().add(const Duration(days: 365)),
          focusedDay: _focusedDay,
          calendarFormat: _calendarFormat,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          startingDayOfWeek: StartingDayOfWeek.monday,
          locale: _calendarLocale(lang),

          // Events loader for markers
          eventLoader: (day) => service.eventsForDay(day),

          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            });
          },
          onFormatChanged: (format) {
            setState(() => _calendarFormat = format);
          },
          onPageChanged: (focusedDay) {
            _focusedDay = focusedDay;
          },

          // Styling
          calendarStyle: CalendarStyle(
            outsideDaysVisible: false,
            todayDecoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            selectedDecoration: const BoxDecoration(
              color: AppTheme.primaryColor,
              shape: BoxShape.circle,
            ),
            markerDecoration: const BoxDecoration(
              color: Colors.orangeAccent,
              shape: BoxShape.circle,
            ),
            markerSize: 6,
            markersMaxCount: 3,
            defaultTextStyle: const TextStyle(color: AppTheme.textColor),
            weekendTextStyle: TextStyle(color: Colors.grey.shade400),
            todayTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            selectedTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          headerStyle: HeaderStyle(
            formatButtonVisible: true,
            titleCentered: true,
            titleTextStyle: const TextStyle(color: AppTheme.textColor, fontSize: 16, fontWeight: FontWeight.w600),
            leftChevronIcon: const Icon(Icons.chevron_left, color: AppTheme.textColor),
            rightChevronIcon: const Icon(Icons.chevron_right, color: AppTheme.textColor),
            formatButtonDecoration: BoxDecoration(
              border: Border.all(color: AppTheme.primaryColor),
              borderRadius: BorderRadius.circular(14),
            ),
            formatButtonTextStyle: const TextStyle(color: AppTheme.primaryColor, fontSize: 13),
          ),
          daysOfWeekStyle: DaysOfWeekStyle(
            weekdayStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            weekendStyle: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ),

        const SizedBox(height: 8),

        // Events list for selected day
        Expanded(
          child: selectedEvents.isEmpty
              ? Center(
                  child: Text(
                    _t('no_events_day', lang),
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: selectedEvents.length,
                  itemBuilder: (context, index) {
                    return _EventCard(
                      event: selectedEvents[index],
                      lang: lang,
                      onTap: () => _showEventDetail(context, selectedEvents[index]),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ─────────────────── List View ───────────────────

  Widget _buildListView(
    BuildContext context,
    CalendarService service,
    String lang,
    ThemeData theme,
  ) {
    final upcoming = service.upcomingEvents;

    if (upcoming.isEmpty) {
      return _buildEmptyState(theme, _t('no_events', lang), Icons.event_busy);
    }

    // Group events by date
    final grouped = <DateTime, List<CalendarEvent>>{};
    for (final event in upcoming) {
      final dayKey = DateTime(event.startTime.year, event.startTime.month, event.startTime.day);
      grouped.putIfAbsent(dayKey, () => []).add(event);
    }

    final sortedDays = grouped.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: sortedDays.length,
      itemBuilder: (context, index) {
        final day = sortedDays[index];
        final dayEvents = grouped[day]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date header
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8, left: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _isToday(day)
                          ? AppTheme.primaryColor
                          : AppTheme.cardBackground,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _formatDateHeader(day, lang),
                      style: TextStyle(
                        color: _isToday(day) ? Colors.white : Colors.grey.shade300,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Event cards for this day
            ...dayEvents.map((event) => _EventCard(
                  event: event,
                  lang: lang,
                  onTap: () => _showEventDetail(context, event),
                )),
          ],
        );
      },
    );
  }

  // ─────────────────── Helpers ───────────────────

  void _showEventDetail(BuildContext context, CalendarEvent event) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EventDetailSheet(event: event),
    );
  }

  Widget _buildEmptyState(ThemeData theme, String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Colors.grey.shade600),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: Colors.grey.shade500, fontSize: 15)),
        ],
      ),
    );
  }

  bool _isToday(DateTime day) {
    final now = DateTime.now();
    return day.year == now.year && day.month == now.month && day.day == now.day;
  }

  bool _isTomorrow(DateTime day) {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return day.year == tomorrow.year && day.month == tomorrow.month && day.day == tomorrow.day;
  }

  String _formatDateHeader(DateTime day, String lang) {
    if (_isToday(day)) return _t('today', lang);
    if (_isTomorrow(day)) return _t('tomorrow', lang);
    // e.g. "Mon, 3 Mar 2026"
    return DateFormat('EEE, d MMM yyyy', _calendarLocale(lang)).format(day);
  }

  String _calendarLocale(String lang) {
    switch (lang) {
      case 'de':
        return 'de_DE';
      case 'it':
        return 'it_IT';
      case 'fr':
        return 'fr_FR';
      default:
        return 'en_US';
    }
  }
}

// ─────────────────── Event Card Widget ───────────────────

class _EventCard extends StatelessWidget {
  final CalendarEvent event;
  final String lang;
  final VoidCallback onTap;

  const _EventCard({
    required this.event,
    required this.lang,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final calendarService = context.watch<CalendarService>();
    final isRegistered = calendarService.isRegistered(event.id);
    final regCount = calendarService.registrationCount(event.id);
    final timeFormat = DateFormat('HH:mm');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Time column
                Container(
                  width: 56,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Text(
                        timeFormat.format(event.startTime),
                        style: const TextStyle(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      if (event.endTime != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          timeFormat.format(event.endTime!),
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: const TextStyle(
                          color: AppTheme.textColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (event.location.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.location_on, size: 14, color: Colors.grey.shade400),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                event.location,
                                style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (regCount > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.group, size: 14, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text(
                              '$regCount ${_t('participants', lang)}',
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Registration badge
                if (isRegistered)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 14, color: Colors.green),
                        SizedBox(width: 4),
                        Text('✓', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                else
                  const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
