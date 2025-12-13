import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/flight.dart';
import '../services/flight_service.dart';
import '../services/profile_service.dart';
import '../services/app_config_service.dart';
import '../services/global_data_service.dart';
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

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: flights.length,
      itemBuilder: (context, index) {
        final flight = flights[index];
        final rowNumber = flights.length - index; // #1 is oldest
        return _buildFlightCard(
          context,
          flight,
          rowNumber,
          lang,
          flightService,
          profileService,
        );
      },
    );
  }

  Widget _buildFlightCard(
    BuildContext context,
    Flight flight,
    int rowNumber,
    String lang,
    FlightService flightService,
    ProfileService profileService,
  ) {
    final theme = Theme.of(context);
    final dateFormatter = DateFormat('dd.MM.yyyy');
    final flightDate = DateTime.parse(flight.date);
    final formattedDate = dateFormatter.format(flightDate);
    final duration = '${flight.flightTimeMinutes ~/ 60}h ${flight.flightTimeMinutes % 60}m';

    // Status icon - show only if flight was logged as Student (case-sensitive)
    Widget statusIcon = const SizedBox.shrink();
    if (flight.licenseType == 'Student') {
      statusIcon = flight.status == 'accepted'
          ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
          : const Icon(Icons.access_time, color: Colors.amber, size: 20);
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: #number  TAKEOFF → LANDING   [STATUS_ICON]
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '#$rowNumber  ${flight.takeoffName} → ${flight.landingName}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    statusIcon,
                    if (flight.licenseType == 'Student') const SizedBox(width: 8),
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
            const Divider(height: 16, thickness: 1),

            // Flight date and info
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow(
                    _t('Date', lang),
                    formattedDate,
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
                await flightService.deleteFlight(flight.id!);
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
  String? _selectedFlightTypeId;
  Set<String> _selectedManeuvers = {};
  List<Map<String, dynamic>> _availableLocations = [];
  List<Map<String, dynamic>> _filteredTakeoffLocations = [];
  List<Map<String, dynamic>> _filteredLandingLocations = [];
  bool _takeoffFromDropdown = false; // Track if takeoff was selected from dropdown
  bool _landingFromDropdown = false; // Track if landing was selected from dropdown

  @override
  void initState() {
    super.initState();
    _initControllers();
    _loadGlobalData();
  }

  void _loadGlobalData() {
    final globalService = context.read<GlobalDataService>();
    if (globalService.isInitialized) {
      _loadLocations();
    }
  }

  void _loadLocations() {
    final globalService = context.read<GlobalDataService>();
    final profile = widget.profileService.userProfile;
    final schoolId = profile?.schoolId;

    // Get all locations
    _availableLocations = globalService.globalLocations ?? [];

    // Filter by school if student
    if (profile?.license == 'student' && schoolId != null && schoolId.isNotEmpty) {
      _filteredTakeoffLocations = _availableLocations
          .where((loc) =>
              (loc['type'] == 'takeoff') &&
              (loc['schools'] as List?)?.contains(schoolId) == true)
          .toList();
      _filteredLandingLocations = _availableLocations
          .where((loc) =>
              (loc['type'] == 'landing') &&
              (loc['schools'] as List?)?.contains(schoolId) == true)
          .toList();
    } else {
      // Non-students see all locations
      _filteredTakeoffLocations = _availableLocations.where((loc) => loc['type'] == 'takeoff').toList();
      _filteredLandingLocations = _availableLocations.where((loc) => loc['type'] == 'landing').toList();
    }
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
      _selectedFlightTypeId = flight.flightTypeId;
      _selectedManeuvers = Set.from(flight.advancedManeuvers);

      _hours = flight.flightTimeMinutes ~/ 60;
      _minutes = flight.flightTimeMinutes % 60;
      _takeoffFromDropdown = false;
      _landingFromDropdown = false;
    } else {
      _dateController = TextEditingController(
        text: DateFormat('dd.MM.yyyy').format(DateTime.now()),
      );
      _takeoffController = TextEditingController();
      _landingController = TextEditingController();
      _takeoffAltitudeController = TextEditingController(text: '1000');
      _landingAltitudeController = TextEditingController(text: '500');
      _commentController = TextEditingController();
      _selectedFlightTypeId = null;
      _selectedManeuvers = {};
      _takeoffFromDropdown = false;
      _landingFromDropdown = false;

      _hours = 0;
      _minutes = 10;
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
        flightTypeId: _selectedFlightTypeId,
        advancedManeuvers: _selectedManeuvers.toList(),
        schoolManeuvers: const [],
        licenseType: profile.license ?? 'student',
        status: widget.flight?.status ?? 'pending',
        createdAt: widget.flight?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
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

  Widget _buildFlightTypeDropdown() {
    final globalService = context.read<GlobalDataService>();
    final appConfig = context.watch<AppConfigService>();
    final lang = appConfig.currentLanguageCode;
    final flightTypes = globalService.globalFlighttypes ?? [];

    // Create dropdown menu items
    final items = flightTypes.map((type) {
      // Use localized type field (type_en, type_de, etc.) with fallback to type_en
      final typeKey = 'type_$lang';
      final typeLabel = (type[typeKey] as String?) ?? (type['type_en'] as String?) ?? 'Unknown';
      return DropdownMenuItem<String>(
        value: type['id'],
        child: Text(typeLabel),
      );
    }).toList();

    // Ensure the selected value is in the items list, or reset to null
    String? currentValue = _selectedFlightTypeId;
    if (currentValue != null && !items.any((item) => item.value == currentValue)) {
      currentValue = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Flight Type'),
        const SizedBox(height: 8),
        DropdownButton<String>(
          isExpanded: true,
          hint: const Text('Select flight type'),
          value: currentValue,
          onChanged: (String? newValue) {
            setState(() {
              _selectedFlightTypeId = newValue;
              _selectedManeuvers.clear(); // Clear maneuvers when type changes
            });
          },
          items: items,
        ),
      ],
    );
  }

  Widget _buildManeuversSelection() {
    final globalService = context.read<GlobalDataService>();
    final appConfig = context.watch<AppConfigService>();
    final lang = appConfig.currentLanguageCode;
    final flightTypes = globalService.globalFlighttypes ?? [];

    // Get maneuvers from the selected flight type
    if (_selectedFlightTypeId == null) {
      return const SizedBox.shrink();
    }

    final selectedFlightType = flightTypes.firstWhere(
      (type) => type['id'] == _selectedFlightTypeId,
      orElse: () => <String, dynamic>{},
    );

    if (selectedFlightType.isEmpty) {
      return const SizedBox.shrink();
    }

    // Get localized maneuvers array (maneuvers_en, maneuvers_de, etc.)
    final maneuvereKey = 'maneuvers_$lang';
    List<dynamic> maneuversList =
        (selectedFlightType[maneuvereKey] as List<dynamic>?) ??
        (selectedFlightType['maneuvers_en'] as List<dynamic>?) ??
        [];

    // If no maneuvers available for this flight type, don't show the field
    if (maneuversList.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Maneuvers (Optional)'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: maneuversList.map((maneuver) {
            // Maneuvers are stored as strings in the array
            final maneuverName = maneuver.toString();
            final isSelected = _selectedManeuvers.contains(maneuverName);
            return FilterChip(
              label: Text(maneuverName),
              selected: isSelected,
              onSelected: (bool selected) {
                setState(() {
                  if (selected) {
                    _selectedManeuvers.add(maneuverName);
                  } else {
                    _selectedManeuvers.remove(maneuverName);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
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
              onChanged: (value) {
                // If user manually edits, mark as not from dropdown
                if (_takeoffFromDropdown && value.isNotEmpty) {
                  setState(() => _takeoffFromDropdown = false);
                }
              },
              decoration: InputDecoration(
                labelText: 'Takeoff Location *',
                prefixIcon: const Icon(Icons.flight_takeoff),
                border: const OutlineInputBorder(),
                enabled: canEditDateAndLocation,
              ),
            ),
            const SizedBox(height: 8),

            // Takeoff Location Dropdown (if locations available)
            if (_filteredTakeoffLocations.isNotEmpty && canEditDateAndLocation)
              DropdownButton<String>(
                isExpanded: true,
                hint: const Text('Or select from school locations'),
                value: null,
                onChanged: (String? locationId) {
                  if (locationId != null) {
                    final location = _filteredTakeoffLocations
                        .firstWhere((loc) => loc['id'] == locationId);
                    setState(() {
                      _takeoffController.text = location['name'] ?? '';
                      _takeoffAltitudeController.text =
                          (location['altitude']?.toString() ?? '1000');
                      _takeoffFromDropdown = true; // Mark as from dropdown
                    });
                  }
                },
                items: _filteredTakeoffLocations.map((location) {
                  return DropdownMenuItem<String>(
                    value: location['id'],
                    child: Text(location['name'] ?? 'Unknown'),
                  );
                }).toList(),
              ),
            const SizedBox(height: 12),

            // Takeoff Altitude
            TextField(
              controller: _takeoffAltitudeController,
              readOnly: _takeoffFromDropdown && canEditDateAndLocation,
              enabled: !(_takeoffFromDropdown && canEditDateAndLocation),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                labelText: 'Takeoff Altitude (m) *',
                prefixIcon: const Icon(Icons.height),
                border: const OutlineInputBorder(),
                enabled: canEditDateAndLocation,
                helperText: _takeoffFromDropdown ? 'Auto-filled from location' : null,
              ),
            ),
            const SizedBox(height: 12),

            // Landing
            TextField(
              controller: _landingController,
              readOnly: !canEditDateAndLocation,
              onChanged: (value) {
                // If user manually edits, mark as not from dropdown
                if (_landingFromDropdown && value.isNotEmpty) {
                  setState(() => _landingFromDropdown = false);
                }
              },
              decoration: InputDecoration(
                labelText: 'Landing Location *',
                prefixIcon: const Icon(Icons.flight_land),
                border: const OutlineInputBorder(),
                enabled: canEditDateAndLocation,
              ),
            ),
            const SizedBox(height: 8),

            // Landing Location Dropdown (if locations available)
            if (_filteredLandingLocations.isNotEmpty && canEditDateAndLocation)
              DropdownButton<String>(
                isExpanded: true,
                hint: const Text('Or select from school locations'),
                value: null,
                onChanged: (String? locationId) {
                  if (locationId != null) {
                    final location = _filteredLandingLocations
                        .firstWhere((loc) => loc['id'] == locationId);
                    setState(() {
                      _landingController.text = location['name'] ?? '';
                      _landingAltitudeController.text =
                          (location['altitude']?.toString() ?? '500');
                      _landingFromDropdown = true; // Mark as from dropdown
                    });
                  }
                },
                items: _filteredLandingLocations.map((location) {
                  return DropdownMenuItem<String>(
                    value: location['id'],
                    child: Text(location['name'] ?? 'Unknown'),
                  );
                }).toList(),
              ),
            const SizedBox(height: 12),

            // Landing Altitude
            TextField(
              controller: _landingAltitudeController,
              readOnly: _landingFromDropdown && canEditDateAndLocation,
              enabled: !(_landingFromDropdown && canEditDateAndLocation),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                labelText: 'Landing Altitude (m) *',
                prefixIcon: const Icon(Icons.height),
                border: const OutlineInputBorder(),
                enabled: canEditDateAndLocation,
                helperText: _landingFromDropdown ? 'Auto-filled from location' : null,
              ),
            ),
            const SizedBox(height: 12),

            // Flight Time (Hours & Minutes) - Improved modern picker
            Row(
              children: [
                // Hours
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Hours (0-10) *'),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              onPressed: _hours > 0 ? () => setState(() => _hours--) : null,
                              icon: const Icon(Icons.remove),
                            ),
                            Text(
                              _hours.toString(),
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            IconButton(
                              onPressed: _hours < 10 ? () => setState(() => _hours++) : null,
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Minutes
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Minutes (0-59) *'),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              onPressed: _minutes > 0 ? () => setState(() => _minutes--) : null,
                              icon: const Icon(Icons.remove),
                            ),
                            Text(
                              _minutes.toString().padLeft(2, '0'),
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            IconButton(
                              onPressed: _minutes < 59 ? () => setState(() => _minutes++) : null,
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Flight Type Dropdown
            _buildFlightTypeDropdown(),
            const SizedBox(height: 12),

            // Maneuvers Selection
            if (_selectedFlightTypeId != null) _buildManeuversSelection(),
            if (_selectedFlightTypeId != null) const SizedBox(height: 12),

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
