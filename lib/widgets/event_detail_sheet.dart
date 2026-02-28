// File: lib/widgets/event_detail_sheet.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../models/calendar_event.dart';
import '../services/calendar_service.dart';
import '../services/app_config_service.dart';
import '../services/profile_service.dart';

// ─────────────────── Localization ───────────────────
const Map<String, Map<String, String>> _detailTexts = {
  'event_details': {'en': 'Event Details', 'de': 'Event Details', 'it': 'Dettagli evento', 'fr': 'Détails de l\'événement'},
  'when': {'en': 'When', 'de': 'Wann', 'it': 'Quando', 'fr': 'Quand'},
  'where': {'en': 'Where', 'de': 'Wo', 'it': 'Dove', 'fr': 'Où'},
  'description': {'en': 'Description', 'de': 'Beschreibung', 'it': 'Descrizione', 'fr': 'Description'},
  'navigate': {'en': 'Navigate', 'de': 'Navigieren', 'it': 'Naviga', 'fr': 'Naviguer'},
  'sign_up': {'en': 'Sign Up', 'de': 'Anmelden', 'it': 'Iscriviti', 'fr': 'S\'inscrire'},
  'cancel_registration': {'en': 'Cancel Registration', 'de': 'Abmelden', 'it': 'Cancella iscrizione', 'fr': 'Annuler l\'inscription'},
  'registered': {'en': 'You are registered!', 'de': 'Du bist angemeldet!', 'it': 'Sei iscritto!', 'fr': 'Vous êtes inscrit !'},
  'participants': {'en': 'Participants', 'de': 'Teilnehmer', 'it': 'Partecipanti', 'fr': 'Participants'},
  'no_participants': {'en': 'No one signed up yet', 'de': 'Noch niemand angemeldet', 'it': 'Nessun iscritto', 'fr': 'Personne inscrit'},
  'event_passed': {'en': 'This event has passed', 'de': 'Dieses Event ist vorbei', 'it': 'Questo evento è passato', 'fr': 'Cet événement est passé'},
  'signing_up': {'en': 'Signing up...', 'de': 'Anmeldung...', 'it': 'Iscrizione...', 'fr': 'Inscription...'},
  'cancelling': {'en': 'Cancelling...', 'de': 'Abmeldung...', 'it': 'Cancellazione...', 'fr': 'Annulation...'},
};

String _t(String key, String lang) {
  return _detailTexts[key]?[lang] ?? _detailTexts[key]?['en'] ?? key;
}

class EventDetailSheet extends StatefulWidget {
  final CalendarEvent event;

  const EventDetailSheet({super.key, required this.event});

  @override
  State<EventDetailSheet> createState() => _EventDetailSheetState();
}

class _EventDetailSheetState extends State<EventDetailSheet> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppConfigService>().displayLanguageCode;
    final calendarService = context.watch<CalendarService>();
    final profileService = context.watch<ProfileService>();
    final profile = profileService.userProfile;
    final isRegistered = calendarService.isRegistered(widget.event.id);
    final registrations = calendarService.getRegistrations(widget.event.id);
    final regCount = registrations.length;
    final isPast = widget.event.isPast;
    final event = widget.event;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.cardBackground,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade600,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  children: [
                    // Title
                    Text(
                      event.title,
                      style: const TextStyle(
                        color: AppTheme.textColor,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Date & Time section
                    _DetailRow(
                      icon: Icons.access_time_rounded,
                      iconColor: AppTheme.primaryColor,
                      label: _t('when', lang),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatFullDate(event.startTime, lang),
                            style: const TextStyle(color: AppTheme.textColor, fontSize: 15, fontWeight: FontWeight.w500),
                          ),
                          if (event.endTime != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              '${DateFormat('HH:mm').format(event.startTime)} – ${DateFormat('HH:mm').format(event.endTime!)}',
                              style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                            ),
                          ],
                          if (event.durationText.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              event.durationText,
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Location section
                    if (event.location.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _DetailRow(
                        icon: Icons.location_on_rounded,
                        iconColor: Colors.orangeAccent,
                        label: _t('where', lang),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.location,
                              style: const TextStyle(color: AppTheme.textColor, fontSize: 15),
                            ),
                            const SizedBox(height: 8),
                            // Navigate button
                            SizedBox(
                              height: 36,
                              child: OutlinedButton.icon(
                                onPressed: () => _openMaps(event.location),
                                icon: const Icon(Icons.navigation_rounded, size: 16),
                                label: Text(_t('navigate', lang), style: const TextStyle(fontSize: 13)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.orangeAccent,
                                  side: const BorderSide(color: Colors.orangeAccent),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Description section
                    if (event.description.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _DetailRow(
                        icon: Icons.description_rounded,
                        iconColor: Colors.blueAccent,
                        label: _t('description', lang),
                        child: Text(
                          event.description,
                          style: TextStyle(color: Colors.grey.shade300, fontSize: 14, height: 1.5),
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),
                    Divider(color: Colors.grey.shade700),
                    const SizedBox(height: 12),

                    // Participants section
                    Row(
                      children: [
                        const Icon(Icons.group, color: AppTheme.primaryColor, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '${_t('participants', lang)} ($regCount)',
                          style: const TextStyle(
                            color: AppTheme.textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (registrations.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 28),
                        child: Text(
                          _t('no_participants', lang),
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                        ),
                      )
                    else
                      ...registrations.map((reg) => Padding(
                            padding: const EdgeInsets.only(left: 28, bottom: 6),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.3),
                                  child: Text(
                                    reg.name.isNotEmpty ? reg.name[0].toUpperCase() : '?',
                                    style: const TextStyle(color: AppTheme.primaryColor, fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    reg.name,
                                    style: const TextStyle(color: AppTheme.textColor, fontSize: 14),
                                  ),
                                ),
                                if (reg.uid == profile?.uid)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text('You', style: TextStyle(color: Colors.green, fontSize: 11)),
                                  ),
                              ],
                            ),
                          )),

                    const SizedBox(height: 24),

                    // Registration button
                    if (isPast)
                      _buildPastEventBanner(lang)
                    else if (isRegistered)
                      _buildRegisteredSection(context, calendarService, lang, profile)
                    else
                      _buildSignUpButton(context, calendarService, lang, profile),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPastEventBanner(String lang) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.history, color: Colors.grey, size: 18),
          const SizedBox(width: 8),
          Text(_t('event_passed', lang), style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildRegisteredSection(BuildContext context, CalendarService service, String lang, UserProfile? profile) {
    return Column(
      children: [
        // Success banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              Text(
                _t('registered', lang),
                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Cancel button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _loading ? null : () => _handleUnregister(context, service),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(
              _loading ? _t('cancelling', lang) : _t('cancel_registration', lang),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignUpButton(BuildContext context, CalendarService service, String lang, UserProfile? profile) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _loading ? null : () => _handleRegister(context, service, profile),
        icon: _loading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.how_to_reg),
        label: Text(
          _loading ? _t('signing_up', lang) : _t('sign_up', lang),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: 4,
        ),
      ),
    );
  }

  Future<void> _handleRegister(BuildContext context, CalendarService service, UserProfile? profile) async {
    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final name = '${profile?.forename ?? ''} ${profile?.familyname ?? ''}'.trim();
      await service.register(
        widget.event.id,
        name: name.isNotEmpty ? name : (profile?.email ?? 'Unknown'),
        email: profile?.email ?? '',
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleUnregister(BuildContext context, CalendarService service) async {
    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await service.unregister(widget.event.id);
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openMaps(String location) async {
    final encoded = Uri.encodeComponent(location);
    // Try Google Maps first, falls back to any map app
    final googleMapsUrl = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encoded');
    try {
      if (!await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication)) {
        // Fallback: geo: intent (works on Android)
        final geoUri = Uri.parse('geo:0,0?q=$encoded');
        await launchUrl(geoUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[EventDetail] Error launching maps: $e');
    }
  }

  String _formatFullDate(DateTime dt, String lang) {
    final locale = _toLocale(lang);
    return DateFormat('EEEE, d MMMM yyyy', locale).format(dt);
  }

  String _toLocale(String lang) {
    switch (lang) {
      case 'de': return 'de_DE';
      case 'it': return 'it_IT';
      case 'fr': return 'fr_FR';
      default: return 'en_US';
    }
  }
}

// ─────────────────── Reusable Detail Row ───────────────────

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Widget child;

  const _DetailRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              child,
            ],
          ),
        ),
      ],
    );
  }
}
