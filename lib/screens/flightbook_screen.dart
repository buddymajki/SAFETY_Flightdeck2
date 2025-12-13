import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/flight.dart';
import '../services/flight_service.dart';
import '../services/profile_service.dart';
import '../services/app_config_service.dart';
import '../widgets/responsive_layout.dart';

class FlightBookScreen extends StatefulWidget {
  const FlightBookScreen({super.key});

  @override
  State<FlightBookScreen> createState() => _FlightBookScreenState();
}

class _FlightBookScreenState extends State<FlightBookScreen> {
  // Localization texts
  static const Map<String, Map<String, String>> _texts = {
    'Flight_Logbook': {'en': 'Flight Logbook', 'de': 'Flugbuch'},
    'No_Flights': {'en': 'No flights recorded yet', 'de': 'Noch keine Flüge aufgezeichnet'},
    'Add_Flight': {'en': 'Add Flight', 'de': 'Flug hinzufügen'},
    'Flight_Saved': {'en': 'Flight saved', 'de': 'Flug gespeichert'},
    'Flight_Updated': {'en': 'Flight updated', 'de': 'Flug aktualisiert'},
    'Flight_Deleted': {'en': 'Flight deleted', 'de': 'Flug gelöscht'},
    'Delete_Confirm': {'en': 'Delete this flight?', 'de': 'Diesen Flug löschen?'},
    'Pending': {'en': 'Pending', 'de': 'Ausstehend'},
    'Accepted': {'en': 'Accepted', 'de': 'Akzeptiert'},
    'Date': {'en': 'Date', 'de': 'Datum'},
    'Takeoff': {'en': 'Takeoff', 'de': 'Startplatz'},
    'Landing': {'en': 'Landing', 'de': 'Landeplatz'},
    'Duration': {'en': 'Duration', 'de': 'Dauer'},
    'Type': {'en': 'Type', 'de': 'Typ'},
    'Altitude_Diff': {'en': 'Altitude Diff', 'de': 'Höhendifferenz'},
  };

  String _t(String key, String lang) {
    return _texts[key]?[lang] ?? key;
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = context.watch<AppConfigService>();
    final lang = appConfig.currentLanguageCode;
    final profileService = context.watch<ProfileService>();
    final flightService = context.watch<FlightService>();

    return ResponsiveContainer(
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(_t('Flight_Logbook', lang)),
          centerTitle: true,
        ),
        body: _buildBody(flightService, lang, profileService),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showAddFlightModal(context, flightService, profileService, lang),
          tooltip: _t('Add_Flight', lang),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildBody(FlightService flightService, String lang, ProfileService profileService) {
    if (flightService.isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final flights = flightService.flights;
    if (flights.isEmpty) {
      return Center(
        child: Text(
          _t('No_Flights', lang),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    final licenseType = profileService.userProfile?.license;
    final isStudent = licenseType == 'student';

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: flights.length,
      itemBuilder: (context, index) {
        final flight = flights[index];
        return _buildFlightCard(
          context,
          flight,
          lang,
          isStudent,
          flightService,
          profileService,
        );
      },
    );
  }

  Widget _buildFlightCard(
    BuildContext context,
    Flight flight,
    String lang,
    bool isStudent,
    FlightService flightService,
    ProfileService profileService,
  ) {
    final theme = Theme.of(context);
    final dateFormatter = DateFormat('dd.MM.yyyy');
    final flightDate = DateTime.parse(flight.date);
    final formattedDate = dateFormatter.format(flightDate);
    final duration = '${flight.flightTimeMinutes ~/ 60}h ${flight.flightTimeMinutes % 60}m';

    // Status icon
    Widget statusIcon;
    if (isStudent) {
      if (flight.status == 'accepted') {
        statusIcon = const Icon(
          Icons.check_circle,
          color: Colors.green,
          size: 20,
        );
      } else {
        statusIcon = const Icon(
          Icons.access_time,
          color: Colors.amber,
          size: 20,
        );
      }
    } else {
      statusIcon = const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Date and Status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formattedDate,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    statusIcon,
                    const SizedBox(width: 12),
                    _buildActionButtons(
                      context,
                      flight,
                      flightService,
                      profileService,
                      lang,
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 12),

            // Flight info
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow(
                    _t('Takeoff', lang),
                    flight.takeoffName,
                    theme,
                  ),
                  const SizedBox(height: 4),
                  _infoRow(
                    _t('Landing', lang),
                    flight.landingName,
                    theme,
                  ),
                  const SizedBox(height: 4),
                  _infoRow(
                    _t('Duration', lang),
                    duration,
                    theme,
                  ),
                  const SizedBox(height: 4),
                  _infoRow(
                    _t('Altitude_Diff', lang),
                    '${flight.altitudeDifference.toStringAsFixed(0)} m',
                    theme,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    Flight flight,
    FlightService flightService,
    ProfileService profileService,
    String lang,
  ) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'edit') {
          if (flight.canEdit()) {
            _showEditFlightModal(
              context,
              flight,
              flightService,
              profileService,
              lang,
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cannot edit accepted flights'),
                backgroundColor: Colors.red,
              ),
            );
          }
        } else if (value == 'delete') {
          if (flight.canDelete()) {
            _showDeleteConfirm(context, flight, flightService, lang);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cannot delete accepted flights'),
                backgroundColor: Colors.red,
              ),
            );
          }
        } else if (value == 'details') {
          _showFlightDetails(context, flight, lang);
        }
      },
      itemBuilder: (BuildContext context) => [
        PopupMenuItem(
          value: 'details',
          child: const Row(
            children: [
              Icon(Icons.info, size: 18),
              SizedBox(width: 8),
              Text('Details'),
            ],
          ),
        ),
        if (flight.canEdit())
          PopupMenuItem(
            value: 'edit',
            child: const Row(
              children: [
                Icon(Icons.edit, size: 18),
                SizedBox(width: 8),
                Text('Edit'),
              ],
            ),
          ),
        if (flight.canDelete())
          PopupMenuItem(
            value: 'delete',
            child: const Row(
              children: [
                Icon(Icons.delete, size: 18, color: Colors.red),
                SizedBox(width: 8),
                Text('Delete', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _infoRow(String label, String value, ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.textTheme.labelSmall?.color?.withValues(alpha: 0.7),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  void _showFlightDetails(BuildContext context, Flight flight, String lang) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final dateFormatter = DateFormat('dd.MM.yyyy HH:mm');
        final flightDate = DateTime.parse(flight.date);

        return Container(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Flight Details',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _detailRow('Date', dateFormatter.format(flightDate), theme),
                _detailRow('Takeoff', flight.takeoffName, theme),
                _detailRow('Landing', flight.landingName, theme),
                _detailRow('Takeoff Alt', '${flight.takeoffAltitude.toStringAsFixed(0)} m', theme),
                _detailRow('Landing Alt', '${flight.landingAltitude.toStringAsFixed(0)} m', theme),
                _detailRow('Alt Difference', '${flight.altitudeDifference.toStringAsFixed(0)} m', theme),
                _detailRow('Duration', '${flight.flightTimeMinutes ~/ 60}h ${flight.flightTimeMinutes % 60}m', theme),
                if (flight.comment != null && flight.comment!.isNotEmpty)
                  _detailRow('Comment', flight.comment!, theme),
                _detailRow('Status', flight.status, theme),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium,
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context, Flight flight, FlightService flightService, String lang) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('Delete_Confirm', lang)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await flightService.deleteFlight(flight.id!, flight.schoolId);
                if (mounted) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(_t('Flight_Deleted', lang)),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                }
              } catch (e) {
                if (mounted) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAddFlightModal(
    BuildContext context,
    FlightService flightService,
    ProfileService profileService,
    String lang,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddEditFlightForm(
        flightService: flightService,
        profileService: profileService,
        flight: null,
        onSaved: () {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_t('Flight_Saved', lang)),
              backgroundColor: Colors.green,
            ),
          );
        },
      ),
    );
  }

  void _showEditFlightModal(
    BuildContext context,
    Flight flight,
    FlightService flightService,
    ProfileService profileService,
    String lang,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddEditFlightForm(
        flightService: flightService,
        profileService: profileService,
        flight: flight,
        onSaved: () {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_t('Flight_Updated', lang)),
              backgroundColor: Colors.green,
            ),
          );
        },
      ),
    );
  }
}

// --- Add/Edit Flight Form ---

class _AddEditFlightForm extends StatefulWidget {
  final FlightService flightService;
  final ProfileService profileService;
  final Flight? flight; // null for new, non-null for edit
  final VoidCallback onSaved;

  const _AddEditFlightForm({
    required this.flightService,
    required this.profileService,
    required this.flight,
    required this.onSaved,
  });

  @override
  State<_AddEditFlightForm> createState() => _AddEditFlightFormState();
}

class _AddEditFlightFormState extends State<_AddEditFlightForm> {
  late TextEditingController _dateController;
  late TextEditingController _takeoffController;
  late TextEditingController _landingController;
  late TextEditingController _takeoffAltitudeController;
  late TextEditingController _landingAltitudeController;
  late TextEditingController _commentController;

  int _hours = 0;
  int _minutes = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    if (widget.flight != null) {
      final flight = widget.flight!;
      final date = DateTime.parse(flight.date);

      _dateController = TextEditingController(
        text: DateFormat('dd.MM.yyyy').format(date),
      );
      _takeoffController = TextEditingController(text: flight.takeoffName);
      _landingController = TextEditingController(text: flight.landingName);
      _takeoffAltitudeController = TextEditingController(
        text: flight.takeoffAltitude.toStringAsFixed(0),
      );
      _landingAltitudeController = TextEditingController(
        text: flight.landingAltitude.toStringAsFixed(0),
      );
      _commentController = TextEditingController(text: flight.comment);

      _hours = flight.flightTimeMinutes ~/ 60;
      _minutes = flight.flightTimeMinutes % 60;
    } else {
      _dateController = TextEditingController(
        text: DateFormat('dd.MM.yyyy').format(DateTime.now()),
      );
      _takeoffController = TextEditingController();
      _landingController = TextEditingController();
      _takeoffAltitudeController = TextEditingController(text: '1000');
      _landingAltitudeController = TextEditingController(text: '500');
      _commentController = TextEditingController();

      _hours = 1;
      _minutes = 30;
    }
  }

  @override
  void dispose() {
    _dateController.dispose();
    _takeoffController.dispose();
    _landingController.dispose();
    _takeoffAltitudeController.dispose();
    _landingAltitudeController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  bool get _isFormValid {
    return _dateController.text.isNotEmpty &&
        _takeoffController.text.isNotEmpty &&
        _landingController.text.isNotEmpty &&
        _takeoffAltitudeController.text.isNotEmpty &&
        _landingAltitudeController.text.isNotEmpty &&
        (_hours > 0 || _minutes > 0);
  }

  Future<void> _saveFlight() async {
    if (!_isFormValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all required fields'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final dateStr = _dateController.text;
      final dateParts = dateStr.split('.');
      final parsedDate = DateTime(
        int.parse(dateParts[2]),
        int.parse(dateParts[1]),
        int.parse(dateParts[0]),
      );

      final takeoffAlt = double.parse(_takeoffAltitudeController.text);
      final landingAlt = double.parse(_landingAltitudeController.text);
      final altDiff = takeoffAlt - landingAlt;

      final profile = widget.profileService.userProfile!;
      final schoolId = profile.schoolId ?? '';

      final flight = Flight(
        id: widget.flight?.id,
        studentUid: widget.flight?.studentUid ?? '',
        schoolId: schoolId,
        date: parsedDate.toIso8601String(),
        takeoffName: _takeoffController.text.trim(),
        takeoffId: null,
        takeoffAltitude: takeoffAlt,
        landingName: _landingController.text.trim(),
        landingId: null,
        landingAltitude: landingAlt,
        altitudeDifference: altDiff,
        flightTimeMinutes: (_hours * 60) + _minutes,
        comment: _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
        flightTypeId: null,
        advancedManeuvers: const [],
        schoolManeuvers: const [],
        licenseType: profile.license ?? 'student',
        status: widget.flight?.status ?? 'pending',
      );

      if (widget.flight == null) {
        // Add new flight
        await widget.flightService.addFlight(flight);
      } else {
        // Update existing flight
        await widget.flightService.updateFlight(flight);
      }

      if (mounted) {
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _dateController.text = DateFormat('dd.MM.yyyy').format(picked);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.flight != null;
    final canEditDateAndLocation = !isEdit || widget.flight!.canEdit();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isEdit ? 'Edit Flight' : 'Add New Flight',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Date
            TextField(
              controller: _dateController,
              readOnly: true,
              onTap: canEditDateAndLocation ? _selectDate : null,
              decoration: InputDecoration(
                labelText: 'Date *',
                prefixIcon: const Icon(Icons.calendar_today),
                border: const OutlineInputBorder(),
                enabled: canEditDateAndLocation,
              ),
            ),
            const SizedBox(height: 12),

            // Takeoff
            TextField(
              controller: _takeoffController,
              readOnly: !canEditDateAndLocation,
              decoration: InputDecoration(
                labelText: 'Takeoff Location *',
                prefixIcon: const Icon(Icons.flight_takeoff),
                border: const OutlineInputBorder(),
                enabled: canEditDateAndLocation,
              ),
            ),
            const SizedBox(height: 12),

            // Takeoff Altitude
            TextField(
              controller: _takeoffAltitudeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Takeoff Altitude (m) *',
                prefixIcon: Icon(Icons.height),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            // Landing
            TextField(
              controller: _landingController,
              readOnly: !canEditDateAndLocation,
              decoration: InputDecoration(
                labelText: 'Landing Location *',
                prefixIcon: const Icon(Icons.flight_land),
                border: const OutlineInputBorder(),
                enabled: canEditDateAndLocation,
              ),
            ),
            const SizedBox(height: 12),

            // Landing Altitude
            TextField(
              controller: _landingAltitudeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Landing Altitude (m) *',
                prefixIcon: Icon(Icons.height),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            // Flight Time
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Hours *'),
                      const SizedBox(height: 8),
                      TextField(
                        readOnly: true,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          suffixIcon: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                height: 20,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  onPressed: () => setState(() => _hours++),
                                  icon: const Icon(Icons.arrow_drop_up, size: 20),
                                ),
                              ),
                              SizedBox(
                                height: 20,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  onPressed: _hours > 0 ? () => setState(() => _hours--) : null,
                                  icon: const Icon(Icons.arrow_drop_down, size: 20),
                                ),
                              ),
                            ],
                          ),
                        ),
                        controller: TextEditingController(text: _hours.toString()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Minutes *'),
                      const SizedBox(height: 8),
                      TextField(
                        readOnly: true,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          suffixIcon: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                height: 20,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  onPressed: () => setState(() => _minutes = (_minutes + 5) % 60),
                                  icon: const Icon(Icons.arrow_drop_up, size: 20),
                                ),
                              ),
                              SizedBox(
                                height: 20,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  onPressed: () => setState(() => _minutes = (_minutes - 5 + 60) % 60),
                                  icon: const Icon(Icons.arrow_drop_down, size: 20),
                                ),
                              ),
                            ],
                          ),
                        ),
                        controller: TextEditingController(text: _minutes.toString()),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Comment
            TextField(
              controller: _commentController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Comment',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),

            // Save button
            ElevatedButton(
              onPressed: _isLoading ? null : _saveFlight,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(isEdit ? 'Update Flight' : 'Save Flight'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
