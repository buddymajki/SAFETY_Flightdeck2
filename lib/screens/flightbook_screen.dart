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
    'Flight_Logbook': {'en': 'Flight Logbook', 'de': 'Flugbuch', 'it': 'Libro di Volo', 'fr': 'Carnet de Vol'},
    'No_Flights': {'en': 'No flights recorded yet', 'de': 'Noch keine Flüge aufgezeichnet', 'it': 'Nessun volo registrato', 'fr': 'Aucun vol enregistré'},
    'Add_Flight': {'en': 'Add Flight', 'de': 'Flug hinzufügen', 'it': 'Aggiungi volo', 'fr': 'Ajouter un vol'},
    'Flight_Saved': {'en': 'Flight saved', 'de': 'Flug gespeichert', 'it': 'Volo salvato', 'fr': 'Vol enregistré'},
    'Flight_Updated': {'en': 'Flight updated', 'de': 'Flug aktualisiert', 'it': 'Volo aggiornato', 'fr': 'Vol mis à jour'},
    'Flight_Deleted': {'en': 'Flight deleted', 'de': 'Flug gelöscht', 'it': 'Volo eliminato', 'fr': 'Vol supprimé'},
    'Delete_Confirm': {'en': 'Delete this flight?', 'de': 'Diesen Flug löschen?', 'it': 'Eliminare questo volo?', 'fr': 'Supprimer ce vol ?'},
    'Pending': {'en': 'Pending', 'de': 'Ausstehend', 'it': 'In attesa', 'fr': 'En attente'},
    'Accepted': {'en': 'Accepted', 'de': 'Akzeptiert', 'it': 'Accettato', 'fr': 'Accepté'},
    'Date': {'en': 'Date', 'de': 'Datum', 'it': 'Data', 'fr': 'Date'},
    'Takeoff': {'en': 'Takeoff', 'de': 'Startplatz', 'it': 'Decollo', 'fr': 'Décollage'},
    'Landing': {'en': 'Landing', 'de': 'Landeplatz', 'it': 'Atterraggio', 'fr': 'Atterrissage'},
    'Duration': {'en': 'Duration', 'de': 'Dauer', 'it': 'Durata', 'fr': 'Durée'},
    'Type': {'en': 'Type', 'de': 'Typ', 'it': 'Tipo', 'fr': 'Type'},
    'Altitude_Diff': {'en': 'Altitude Diff', 'de': 'Höhendifferenz', 'it': 'Diff. altitudine', 'fr': 'Diff. altitude'},
    'School': {'en': 'School', 'de': 'Schule', 'it': 'Scuola', 'fr': 'École'},
    'Select_School': {'en': 'Select school', 'de': 'Schule auswählen', 'it': 'Seleziona scuola', 'fr': 'Sélectionner l\'école'},
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
      padding: const EdgeInsets.only(top: 8, bottom: 80),
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
        final dateFormatter = DateFormat('dd.MM.yyyy');
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
                Table(
                  columnWidths: const {
                    0: IntrinsicColumnWidth(),
                    1: FlexColumnWidth(),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    _tableRow('Date', dateFormatter.format(flightDate), theme),
                    _tableRow('Takeoff', flight.takeoffName, theme),
                    _tableRow('Landing', flight.landingName, theme),
                    _tableRow('Takeoff Alt', '${flight.takeoffAltitude.toStringAsFixed(0)} m', theme),
                    _tableRow('Landing Alt', '${flight.landingAltitude.toStringAsFixed(0)} m', theme),
                    _tableRow('Alt Difference', '${flight.altitudeDifference.toStringAsFixed(0)} m', theme),
                    _tableRow('Duration', '${flight.flightTimeMinutes ~/ 60}h ${flight.flightTimeMinutes % 60}m', theme),
                    if (flight.comment != null && flight.comment!.isNotEmpty)
                      _tableRow('Comment', flight.comment!, theme, wrap: true),
                    _tableRow('Status', flight.status, theme),
                  ].whereType<TableRow>().toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  TableRow _tableRow(String label, String value, ThemeData theme, {bool wrap = false}) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            label,
            style: theme.textTheme.labelMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8).copyWith(left: 24), // Increased left padding for gap
          child: wrap
              ? Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                  softWrap: true,
                )
              : Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                ),
        ),
      ],
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
      builder: (context) => AddEditFlightForm(
        flightService: flightService,
        profileService: profileService,
        flight: null,
        gpsTracked: false,
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
      builder: (context) => AddEditFlightForm(
        flightService: flightService,
        profileService: profileService,
        flight: flight,
        gpsTracked: flight.gpsTracked,
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

class AddEditFlightForm extends StatefulWidget {
  final FlightService flightService;
  final ProfileService profileService;
  final Flight? flight; // null for new, non-null for edit
  final bool gpsTracked; // whether this flight was GPS tracked (locks flight time if true)
  final bool isNewFromGps; // whether this is a new flight created from GPS (has pre-filled data but is not an edit)
  final VoidCallback onSaved;

  const AddEditFlightForm({super.key, 
    required this.flightService,
    required this.profileService,
    required this.flight,
    required this.gpsTracked,
    required this.onSaved,
    this.isNewFromGps = false,
  });

  @override
  State<AddEditFlightForm> createState() => _AddEditFlightFormState();
}

class _AddEditFlightFormState extends State<AddEditFlightForm> {
  // Translation dictionary for the form
  static const Map<String, Map<String, String>> _formTexts = {
    'Edit_Flight': {'en': 'Edit Flight', 'de': 'Flug bearbeiten', 'it': 'Modifica volo', 'fr': 'Modifier le vol'},
    'Add_New_Flight': {'en': 'Add New Flight', 'de': 'Neuen Flug hinzufügen', 'it': 'Aggiungi nuovo volo', 'fr': 'Ajouter un nouveau vol'},
    'Date': {'en': 'Date *', 'de': 'Datum *', 'it': 'Data *', 'fr': 'Date *'},
    'Takeoff_Location': {'en': 'Takeoff Location *', 'de': 'Startplatz *', 'it': 'Luogo di decollo *', 'fr': 'Lieu de décollage *'},
    'Or_Select': {'en': 'Or select from school locations', 'de': 'Oder aus Schulpunkten auswählen', 'it': 'O seleziona dai punti della scuola', 'fr': 'Ou sélectionner parmi les sites de l\'école'},
    'Type_Or_Select': {'en': 'Start typing or tap to select', 'de': 'Tippen oder antippen zum Auswählen', 'it': 'Inizia a digitare o tocca per selezionare', 'fr': 'Commencez à taper ou appuyez pour sélectionner'},
    'Takeoff_Altitude': {'en': 'Alt (m) *', 'de': 'Höhe (m) *', 'it': 'Alt (m) *', 'fr': 'Alt (m) *'},
    'Auto_Filled': {'en': 'Auto-filled from location', 'de': 'Automatisch aus Standort gefüllt', 'it': 'Compilato automaticamente dalla posizione', 'fr': 'Rempli automatiquement depuis la position'},
    'Landing_Location': {'en': 'Landing Location *', 'de': 'Landeplatz *', 'it': 'Luogo di atterraggio *', 'fr': 'Lieu d\'atterrissage *'},
    'Landing_Altitude': {'en': 'Alt (m) *', 'de': 'Höhe (m) *', 'it': 'Alt (m) *', 'fr': 'Alt (m) *'},
    'Hours': {'en': 'Hours (0-10) *', 'de': 'Stunden (0-10) *', 'it': 'Ore (0-10) *', 'fr': 'Heures (0-10) *'},
    'Minutes': {'en': 'Minutes (0-59) *', 'de': 'Minuten (0-59) *', 'it': 'Minuti (0-59) *', 'fr': 'Minutes (0-59) *'},
    'Flight_Type': {'en': 'Flight Type', 'de': 'Flugtyp', 'it': 'Tipo di volo', 'fr': 'Type de vol'},
    'Select_Flight_Type': {'en': 'Select flight type', 'de': 'Flugtyp auswählen', 'it': 'Seleziona tipo di volo', 'fr': 'Sélectionner le type de vol'},
    'Maneuvers': {'en': 'Maneuvers', 'de': 'Kunststücke', 'it': 'Manovre', 'fr': 'Manœuvres'},
    'Select_Maneuvers': {'en': 'Select maneuvers performed', 'de': 'Durchgeführte Kunststücke auswählen', 'it': 'Seleziona manovre eseguite', 'fr': 'Sélectionner les manœuvres effectuées'},
    'Add_Maneuvers': {'en': 'Add Maneuver(s)', 'de': 'Kunststück(e) hinzufügen', 'it': 'Aggiungi manovra/e', 'fr': 'Ajouter manœuvre(s)'},
    'Start_Type': {'en': 'Start Type', 'de': 'Startart', 'it': 'Tipo di partenza', 'fr': 'Type de départ'},
    'Select_Start_Type': {'en': 'Select start type', 'de': 'Startart auswählen', 'it': 'Seleziona tipo di partenza', 'fr': 'Sélectionner le type de départ'},
    'Comment': {'en': 'Comment', 'de': 'Kommentar', 'it': 'Commento', 'fr': 'Commentaire'},
    'Save': {'en': 'Save', 'de': 'Speichern', 'it': 'Salva', 'fr': 'Enregistrer'},
    'Cancel': {'en': 'Cancel', 'de': 'Abbrechen', 'it': 'Annulla', 'fr': 'Annuler'},
    'Close': {'en': 'Close', 'de': 'Schließen', 'it': 'Chiudi', 'fr': 'Fermer'},
    'Validation_Error': {'en': 'Please fill in all required fields', 'de': 'Bitte füllen Sie alle erforderlichen Felder aus', 'it': 'Compilare tutti i campi obbligatori', 'fr': 'Veuillez remplir tous les champs obligatoires'},
    'School_This_Flight': {'en': 'School (this flight)', 'de': 'Schule (für diesen Flug)', 'it': 'Scuola (per questo volo)', 'fr': 'École (pour ce vol)'},
    'Save_GPS_Flight': {'en': 'Save Flight', 'de': 'Flug speichern', 'it': 'Salva volo', 'fr': 'Enregistrer le vol'},
  };

  String _t(String key, String lang) {
    return _formTexts[key]?[lang] ?? key;
  }

  /// Normalize special characters for better search matching
  /// Converts: ü→ue, ä→ae, ö→oe, ß→ss, etc. (two-letter variant)
  String _normalizeForSearch(String text) {
    return text
        .replaceAll('ü', 'ue')
        .replaceAll('ö', 'oe')
        .replaceAll('ä', 'ae')
        .replaceAll('ß', 'ss')
        .replaceAll('Ü', 'UE')
        .replaceAll('Ö', 'OE')
        .replaceAll('Ä', 'AE')
        .toLowerCase();
  }

  /// Normalize special characters to single letters
  /// Converts: ü→u, ä→a, ö→o, ß→s, etc.
  String _normalizeForSearchSimple(String text) {
    return text
        .replaceAll('ü', 'u')
        .replaceAll('ö', 'o')
        .replaceAll('ä', 'a')
        .replaceAll('ß', 's')
        .replaceAll('Ü', 'u')
        .replaceAll('Ö', 'o')
        .replaceAll('Ä', 'a')
        .toLowerCase();
  }

  /// Check if location matches search query
  /// Searches across all words and handles special characters (both ü→ue and ü→u variants)
  bool _locationMatchesQuery(String locationName, String query) {
    if (query.isEmpty) return true;
    
    // Normalize in both ways: ü→ue and ü→u
    final normalizedLocationFull = _normalizeForSearch(locationName);
    final normalizedLocationSimple = _normalizeForSearchSimple(locationName);
    
    final normalizedQueryFull = _normalizeForSearch(query);
    final normalizedQuerySimple = _normalizeForSearchSimple(query);
    
    // Check against full normalization (ü→ue)
    final wordsFull = normalizedLocationFull.split(RegExp(r'[^a-z0-9]+'));
    for (final word in wordsFull) {
      if (word.contains(normalizedQueryFull)) {
        return true;
      }
    }
    
    // Check against simple normalization (ü→u)
    final wordsSimple = normalizedLocationSimple.split(RegExp(r'[^a-z0-9]+'));
    for (final word in wordsSimple) {
      if (word.contains(normalizedQuerySimple)) {
        return true;
      }
    }
    
    return false;
  }

  late TextEditingController _dateController;
  late TextEditingController _takeoffController;
  late TextEditingController _landingController;
  late TextEditingController _takeoffAltitudeController;
  late TextEditingController _landingAltitudeController;
  late TextEditingController _commentController;

  DateTime? _selectedDate; // Store the full date with year
  int _hours = 0;
  int _minutes = 0;
  bool _isLoading = false;
  String? _selectedStartTypeId;
  String? _selectedFlightTypeId;
  Set<String> _selectedManeuvers = {};
  List<Map<String, dynamic>> _availableLocations = [];
  List<Map<String, dynamic>> _filteredTakeoffLocations = [];
  List<Map<String, dynamic>> _filteredLandingLocations = [];
  bool _takeoffFromDropdown = false; // Track if takeoff was selected from dropdown
  bool _landingFromDropdown = false; // Track if landing was selected from dropdown

  // Track previous profile state to detect changes
  String? _previousMainSchoolId;
  String? _previousLicense;
  String? _selectedFormSchoolId; // school chosen for this flight (can differ for guest flights)

  @override
  void initState() {
    super.initState();
    _initControllers();
    _loadGlobalData();
    _initializeProfileTracking();
  }

  /// Initialize profile tracking with current values
  void _initializeProfileTracking() {
    final profile = widget.profileService.userProfile;
    _previousMainSchoolId = profile?.mainSchoolId;
    _previousLicense = profile?.license;

    // Default selected school for the form: existing flight's school override, else user's main
    _selectedFormSchoolId = widget.flight?.thisFlightSchoolId
        ?? widget.flight?.mainSchoolId
        ?? profile?.mainSchoolId;
  }

  /// Detect profile changes via didChangeDependencies
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkProfileChangesAndReloadLocations();
  }

  void _loadGlobalData() {
    final globalService = context.read<GlobalDataService>();
    if (globalService.isInitialized) {
      _loadLocations();
    }
  }

  /// Check if profile (school/license) has changed and reload locations if needed
  void _checkProfileChangesAndReloadLocations() {
    final profile = widget.profileService.userProfile;
    final currentSchoolId = profile?.mainSchoolId;
    final currentLicense = profile?.license;

    debugPrint('[FlightForm._checkProfileChangesAndReloadLocations] Checking for profile changes');
    debugPrint('[FlightForm._checkProfileChangesAndReloadLocations] Previous: schoolId=$_previousMainSchoolId, license=$_previousLicense');
    debugPrint('[FlightForm._checkProfileChangesAndReloadLocations] Current: schoolId=$currentSchoolId, license=$currentLicense');

    // Check if school or license has changed
    final schoolChanged = _previousMainSchoolId != currentSchoolId;
    final licenseChanged = _previousLicense != currentLicense;

    debugPrint('[FlightForm._checkProfileChangesAndReloadLocations] School changed: $schoolChanged, License changed: $licenseChanged');

    if (schoolChanged || licenseChanged) {
      debugPrint('[FlightForm._checkProfileChangesAndReloadLocations] PROFILE CHANGED - reloading locations');
      _previousMainSchoolId = currentSchoolId;
      _previousLicense = currentLicense;

      // Reload locations with new profile
      _loadLocations();

      // Check and clear invalid selected locations
      _validateAndClearInvalidLocations();

      setState(() {});
      debugPrint('[FlightForm._checkProfileChangesAndReloadLocations] Profile update complete, UI refreshed');
    }
  }

  /// Check if currently selected locations are still valid in the new filtered lists
  /// If not, clear the location and altitude fields
  void _validateAndClearInvalidLocations() {
    final currentTakeoff = _takeoffController.text;
    final currentLanding = _landingController.text;

    debugPrint('[FlightForm._validateAndClearInvalidLocations] Validating selected locations');
    debugPrint('[FlightForm._validateAndClearInvalidLocations] Current takeoff: "$currentTakeoff"');
    debugPrint('[FlightForm._validateAndClearInvalidLocations] Current landing: "$currentLanding"');
    debugPrint('[FlightForm._validateAndClearInvalidLocations] Available filtered takeoffs: ${_filteredTakeoffLocations.length}');
    debugPrint('[FlightForm._validateAndClearInvalidLocations] Available filtered landings: ${_filteredLandingLocations.length}');

    // Check if takeoff location is still valid
    if (currentTakeoff.isNotEmpty) {
      final takeoffStillValid = _filteredTakeoffLocations.any(
        (loc) => (loc['name'] ?? '').toString() == currentTakeoff,
      );
      debugPrint('[FlightForm._validateAndClearInvalidLocations] Takeoff "$currentTakeoff" valid: $takeoffStillValid');
      if (!takeoffStillValid) {
        debugPrint('[FlightForm._validateAndClearInvalidLocations] CLEARING takeoff location "$currentTakeoff" (no longer valid)');
        _takeoffController.clear();
        _takeoffAltitudeController.text = '1000';
        _takeoffFromDropdown = false;
      }
    }

    // Check if landing location is still valid
    if (currentLanding.isNotEmpty) {
      final landingStillValid = _filteredLandingLocations.any(
        (loc) => (loc['name'] ?? '').toString() == currentLanding,
      );
      debugPrint('[FlightForm._validateAndClearInvalidLocations] Landing "$currentLanding" valid: $landingStillValid');
      if (!landingStillValid) {
        debugPrint('[FlightForm._validateAndClearInvalidLocations] CLEARING landing location "$currentLanding" (no longer valid)');
        _landingController.clear();
        _landingAltitudeController.text = '500';
        _landingFromDropdown = false;
      }
    }
  }

  void _loadLocations() {
    final globalService = context.read<GlobalDataService>();
    final profile = widget.profileService.userProfile;
    final selectedSchoolId = _selectedFormSchoolId ?? profile?.mainSchoolId;
    final license = profile?.license?.toLowerCase() ?? ''; // Case-insensitive

    // Get all locations
    _availableLocations = globalService.globalLocations ?? [];
    
    debugPrint('[FlightForm._loadLocations] Starting location filtering');
    debugPrint('[FlightForm._loadLocations] Profile: license=$license, selectedSchoolId=$selectedSchoolId');
    debugPrint('[FlightForm._loadLocations] Total available locations: ${_availableLocations.length}');

    // Filter by school if student
    if (license == 'student') {
      if (selectedSchoolId == null || selectedSchoolId.isEmpty) {
        debugPrint('[FlightForm._loadLocations] ERROR: User is student but schoolId is null/empty!');
        debugPrint('[FlightForm._loadLocations] No locations will be shown (as per safety requirement)');
        _filteredTakeoffLocations = [];
        _filteredLandingLocations = [];
      } else {
        debugPrint('[FlightForm._loadLocations] Filtering by schoolId: $selectedSchoolId');
        
        // Debug: show what school IDs are in the locations
        final locationsWithSchools = _availableLocations
            .where((loc) => (loc['schools'] as List?)?.isNotEmpty ?? false)
            .toList();
        debugPrint('[FlightForm._loadLocations] Locations with school associations: ${locationsWithSchools.length}');
        
        // Show sample of school IDs in locations
        if (locationsWithSchools.isNotEmpty) {
          final sampleLocation = locationsWithSchools.first;
          debugPrint('[FlightForm._loadLocations] Sample location schools: ${sampleLocation['schools']}');
        }

        _filteredTakeoffLocations = _availableLocations
            .where((loc) =>
                (loc['type'] == 'takeoff') &&
            (loc['schools'] as List?)?.contains(selectedSchoolId) == true)
            .toList();
        _filteredLandingLocations = _availableLocations
            .where((loc) =>
                (loc['type'] == 'landing') &&
            (loc['schools'] as List?)?.contains(selectedSchoolId) == true)
            .toList();
        
        debugPrint('[FlightForm._loadLocations] Filtered takeoff locations: ${_filteredTakeoffLocations.length}');
        debugPrint('[FlightForm._loadLocations] Filtered landing locations: ${_filteredLandingLocations.length}');
        
        // Debug: show names of filtered locations
        if (_filteredTakeoffLocations.isNotEmpty) {
          final takeoffNames = _filteredTakeoffLocations.map((l) => l['name']).join(', ');
          debugPrint('[FlightForm._loadLocations] Takeoff locations: $takeoffNames');
        }
        if (_filteredLandingLocations.isNotEmpty) {
          final landingNames = _filteredLandingLocations.map((l) => l['name']).join(', ');
          debugPrint('[FlightForm._loadLocations] Landing locations: $landingNames');
        }
      }
    } else {
      // Non-students see all locations
      debugPrint('[FlightForm._loadLocations] User is not a student (license=$license), showing all locations');
      _filteredTakeoffLocations = _availableLocations.where((loc) => loc['type'] == 'takeoff').toList();
      _filteredLandingLocations = _availableLocations.where((loc) => loc['type'] == 'landing').toList();
      
      debugPrint('[FlightForm._loadLocations] All takeoff locations: ${_filteredTakeoffLocations.length}');
      debugPrint('[FlightForm._loadLocations] All landing locations: ${_filteredLandingLocations.length}');
    }
  }

  void _initControllers() {
    if (widget.flight != null) {
      final flight = widget.flight!;
      final date = DateTime.parse(flight.date);
      final profile = widget.profileService.userProfile;
      final isStudent = profile?.license?.toLowerCase() == 'student';
      final dateFormat = isStudent ? 'dd.MM' : 'dd.MM.yyyy';

      _selectedDate = date; // Store the full date
      _dateController = TextEditingController(
        text: DateFormat(dateFormat).format(date),
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
      _selectedStartTypeId = flight.startTypeId;
      _selectedFlightTypeId = flight.flightTypeId;
      _selectedManeuvers = Set.from(flight.advancedManeuvers);

      _hours = flight.flightTimeMinutes ~/ 60;
      _minutes = flight.flightTimeMinutes % 60;
      _takeoffFromDropdown = false;
      _landingFromDropdown = false;
    } else {
      final profile = widget.profileService.userProfile;
      final isStudent = profile?.license?.toLowerCase() == 'student';
      final dateFormat = isStudent ? 'dd.MM' : 'dd.MM.yyyy';
      final now = DateTime.now();
      _selectedDate = now; // Store the full date
      _dateController = TextEditingController(
        text: DateFormat(dateFormat).format(now),
      );
      _takeoffController = TextEditingController();
      _landingController = TextEditingController();
      _takeoffAltitudeController = TextEditingController(text: '1000');
      _landingAltitudeController = TextEditingController(text: '500');
      _commentController = TextEditingController();
      _selectedStartTypeId = null;
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
      // Use the stored date that includes the year selected by user in the date picker
      final parsedDate = _selectedDate ?? DateTime.now();

      final takeoffAlt = double.parse(_takeoffAltitudeController.text);
      final landingAlt = double.parse(_landingAltitudeController.text);
      final altDiff = takeoffAlt - landingAlt;

      final profile = widget.profileService.userProfile!;
      final mainSchoolId = profile.mainSchoolId ?? '';
      final thisFlightSchoolId = _selectedFormSchoolId ?? mainSchoolId;

      final flight = Flight(
        id: widget.flight?.id,
        studentUid: widget.flight?.studentUid ?? profile.uid ?? '',
        mainSchoolId: mainSchoolId,
        thisFlightSchoolId: thisFlightSchoolId,
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
        startTypeId: _selectedStartTypeId,
        flightTypeId: _selectedFlightTypeId,
        advancedManeuvers: _selectedManeuvers.toList(),
        schoolManeuvers: const [],
        licenseType: profile.license ?? 'student',
        status: widget.flight?.status ?? 'pending',
        createdAt: widget.flight?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
        gpsTracked: widget.gpsTracked,
      );

      debugPrint('[AddEditFlightForm] Saving flight: gpsTracked=${flight.gpsTracked}, isNewFromGps=${widget.isNewFromGps}');

      // GPS tracked flights always add as NEW (never update), even if flight object has data
      if (widget.flight == null || widget.isNewFromGps) {
        // Add new flight
        debugPrint('[AddEditFlightForm] Adding NEW flight with gpsTracked=${flight.gpsTracked}');
        await widget.flightService.addFlight(flight);
      } else {
        // Update existing flight (only for manual edits)
        debugPrint('[AddEditFlightForm] Updating existing flight');
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
    final initialDate = _selectedDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked; // Store the full date with year
        final profile = widget.profileService.userProfile;
        final isStudent = profile?.license?.toLowerCase() == 'student';
        final dateFormat = isStudent ? 'dd.MM' : 'dd.MM.yyyy';
        _dateController.text = DateFormat(dateFormat).format(picked);
      });
    }
  }

  /// Build date and school selection row
  /// For students: Date (50%) + School selector (50%)
  /// For pilots: Date (100%)
  Widget _buildDateAndSchoolRow(bool canEditDateAndLocation, String lang) {
    final profile = widget.profileService.userProfile;
    final isStudent = profile?.license?.toLowerCase() == 'student';

    if (isStudent) {
      // Row with Date (50%) and School (50%)
      return Row(
        children: [
           Expanded(
            flex: 2,
            child: _buildFlightSchoolSelector(lang),
          ),
  
            const SizedBox(width: 12),

            Expanded(
            flex: 1,
            child: TextField(
              controller: _dateController,
              readOnly: true,
              onTap: canEditDateAndLocation ? _selectDate : null,
              decoration: InputDecoration(
                labelText: _t('Date', lang),
                prefixIcon: const Icon(Icons.calendar_today),
                border: const OutlineInputBorder(),
                enabled: canEditDateAndLocation,
              ),
            ),
          ),


        ],
      );
    } else {
      // Full width date for pilots
      return TextField(
        controller: _dateController,
        readOnly: true,
        onTap: canEditDateAndLocation ? _selectDate : null,
        decoration: InputDecoration(
          labelText: _t('Date', lang),
          prefixIcon: const Icon(Icons.calendar_today),
          border: const OutlineInputBorder(),
          enabled: canEditDateAndLocation,
        ),
      );
    }
  }

  /// Build school selector for the flight form (students only)
  /// Searchable autocomplete similar to location selector
  Widget _buildFlightSchoolSelector(String lang) {
    final globalService = context.watch<GlobalDataService>();
    final schools = globalService.schools ?? [];

    // Find the currently selected school name
    final selectedSchoolName = _selectedFormSchoolId != null
        ? schools.firstWhere(
            (s) => s['id'] == _selectedFormSchoolId,
            orElse: () => <String, dynamic>{},
          )['name'] ?? ''
        : '';

    return Autocomplete<Map<String, dynamic>>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          // Show all schools when empty
          return schools;
        }
        
        // Filter schools by name (case-insensitive contains)
        final query = textEditingValue.text.toLowerCase();
        return schools.where((school) {
          final name = (school['name'] ?? '').toString().toLowerCase();
          return name.contains(query);
        });
      },
      displayStringForOption: (Map<String, dynamic> option) => option['name'] ?? '',
      onSelected: (Map<String, dynamic> selection) {
        setState(() {
          _selectedFormSchoolId = selection['id'];
          // Re-run location filtering with the new school selection
          _loadLocations();
          // Clear previously selected takeoff/landing locations since they might not be valid for the new school
          _takeoffController.clear();
          _landingController.clear();
          _takeoffAltitudeController.text = '1000';
          _landingAltitudeController.text = '500';
          _takeoffFromDropdown = false;
          _landingFromDropdown = false;
        });
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        // Keep controller in sync with our selected school
        if (controller.text != selectedSchoolName) {
          controller.text = selectedSchoolName;
          controller.selection = TextSelection.collapsed(offset: controller.text.length);
        }
        
        return ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, textValue, _) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              onTap: () {
                if (controller.text.isNotEmpty) {
                  controller.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: controller.text.length,
                  );
                }
              },
              decoration: InputDecoration(
                labelText: _t('School_This_Flight', lang),
                prefixIcon: const Icon(Icons.school),
                suffixIcon: textValue.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        tooltip: 'Clear school',
                        onPressed: () {
                          controller.clear();
                          setState(() {
                            _selectedFormSchoolId =
                                widget.profileService.userProfile?.mainSchoolId;
                            _loadLocations();
                            _takeoffController.clear();
                            _landingController.clear();
                            _takeoffAltitudeController.text = '1000';
                            _landingAltitudeController.text = '500';
                            _takeoffFromDropdown = false;
                            _landingFromDropdown = false;
                          });
                          focusNode.requestFocus();
                        },
                      )
                    : (schools.isNotEmpty
                        ? const Icon(Icons.arrow_drop_down)
                        : null),
                border: const OutlineInputBorder(),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFlightTypeDropdown() {
    final globalService = context.read<GlobalDataService>();
    final appConfig = context.watch<AppConfigService>();
    final lang = appConfig.currentLanguageCode;
    final flightTypes = globalService.globalFlighttypes ?? [];

    // Helper to safely convert place value to int
    // FIX: Renamed from _getPlaceValue - local functions shouldn't start with underscore
    int getPlaceValue(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 999;
      return 999;
    }

    // If no data available, return empty dropdown
    if (flightTypes.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_t('Flight_Type', lang)),
          const SizedBox(height: 8),
          Text('[No flight types loaded]', style: Theme.of(context).textTheme.bodySmall),
        ],
      );
    }

    // Create dropdown menu items, sorted by place
    final sortedFlightTypes = flightTypes.toList()
      ..sort((a, b) => getPlaceValue(a['place']).compareTo(getPlaceValue(b['place'])));

    final items = sortedFlightTypes.map((type) {
      // Use localized labels (labels.en, labels.de, etc.)
      final labels = type['labels'] as Map<String, dynamic>? ?? {};
      final typeLabel = (labels[lang] as String?) ?? (labels['en'] as String?) ?? 'Unknown';
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
        Text(_t('Flight_Type', lang)),
        const SizedBox(height: 8),
        DropdownButton<String>(
          isExpanded: true,
          hint: Text(_t('Select_Flight_Type', lang)),
          value: currentValue,
          onChanged: (String? newValue) {
            setState(() {
              _selectedFlightTypeId = newValue;
            });
          },
          items: items,
        ),
      ],
    );
  }

  // --- Start Type Dropdown ---
  Widget _buildStartTypeDropdown() {
    final globalService = context.read<GlobalDataService>();
    final appConfig = context.watch<AppConfigService>();
    final lang = appConfig.currentLanguageCode;
    final startTypes = globalService.globalStarttypes ?? [];

    // Helper to safely convert place value to int
    // FIX: Renamed from _getPlaceValue - local functions shouldn't start with underscore
    int getPlaceValue(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 999;
      return 999;
    }

    // Sort by place
    final sortedStartTypes = startTypes.toList()
      ..sort((a, b) => getPlaceValue(a['place']).compareTo(getPlaceValue(b['place'])));

    final items = sortedStartTypes.map((type) {
      final labels = type['labels'] as Map<String, dynamic>? ?? {};
      final typeLabel = (labels[lang] as String?) ?? (labels['en'] as String?) ?? 'Unknown';
      return DropdownMenuItem<String>(
        value: type['id'],
        child: Text(typeLabel),
      );
    }).toList();

    String? currentValue = _selectedStartTypeId;
    if (currentValue != null && !items.any((item) => item.value == currentValue)) {
      currentValue = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_t('Start_Type', lang)),
        const SizedBox(height: 8),
        DropdownButton<String>(
          isExpanded: true,
          hint: Text(_t('Select_Start_Type', lang)),
          value: currentValue,
          onChanged: (String? newValue) {
            setState(() {
              _selectedStartTypeId = newValue;
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
    final allManeuvers = globalService.globalManeuvers ?? [];

    // Helper to safely convert place value to int
    // FIX: Renamed from _getPlaceValue - local functions shouldn't start with underscore
    int getPlaceValue(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 999;
      return 999;
    }

    // Sort maneuvers by place
    final sortedManeuvers = allManeuvers.toList()
      ..sort((a, b) => getPlaceValue(a['place']).compareTo(getPlaceValue(b['place'])));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_t('Maneuvers', lang)),
        const SizedBox(height: 8),
        // Show selected maneuvers as chips
        if (_selectedManeuvers.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selectedManeuvers.map((maneuverKey) {
              final maneuver = allManeuvers.firstWhere(
                (m) => m['id'] == maneuverKey,
                orElse: () => {},
              );
              if (maneuver.isEmpty) return const SizedBox.shrink();
              
              final labels = maneuver['labels'] as Map<String, dynamic>? ?? {};
              final maneuverLabel = (labels[lang] as String?) ?? (labels['en'] as String?) ?? 'Unknown';
              
              return InputChip(
                label: Text(maneuverLabel),
                onDeleted: () {
                  setState(() {
                    _selectedManeuvers.remove(maneuverKey);
                  });
                },
              );
            }).toList(),
          ),
        if (_selectedManeuvers.isNotEmpty) const SizedBox(height: 12),
        // Add Maneuver(s) button
        ElevatedButton.icon(
          icon: const Icon(Icons.add),
          label: Text(_t('Add_Maneuvers', lang)),
          onPressed: () => _showManeuverSelectionDialog(sortedManeuvers, lang),
        ),
      ],
    );
  }

  void _showManeuverSelectionDialog(List<Map<String, dynamic>> sortedManeuvers, String lang) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: Text(_t('Select_Maneuvers', lang)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: sortedManeuvers.map((maneuver) {
                    final maneuverKey = maneuver['id'] as String;
                    final labels = maneuver['labels'] as Map<String, dynamic>? ?? {};
                    final maneuverLabel = (labels[lang] as String?) ?? (labels['en'] as String?) ?? 'Unknown';
                    final isSelected = _selectedManeuvers.contains(maneuverKey);
                    
                    return CheckboxListTile(
                      title: Text(maneuverLabel),
                      value: isSelected,
                      onChanged: (bool? selected) {
                        setDialogState(() {
                          if (selected == true) {
                            _selectedManeuvers.add(maneuverKey);
                          } else {
                            _selectedManeuvers.remove(maneuverKey);
                          }
                        });
                        setState(() {}); // Update parent widget
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(_t('Close', lang)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.flight != null && !widget.isNewFromGps;
    final canEditDateAndLocation = !isEdit || widget.flight!.canEdit();
    final appConfig = context.watch<AppConfigService>();
    final lang = appConfig.currentLanguageCode;

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
              isEdit ? _t('Edit_Flight', lang) : _t('Add_New_Flight', lang),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Date and School (for students) or Date full width (for pilots)
            _buildDateAndSchoolRow(canEditDateAndLocation, lang),
            const SizedBox(height: 12),

            // Takeoff Location and Altitude - Side by side (75% location, 25% altitude)
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Autocomplete<Map<String, dynamic>>(
                    key: ValueKey<String>('takeoff_${_selectedFormSchoolId ?? 'none'}'),
                    initialValue: TextEditingValue(text: _takeoffController.text),
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (!canEditDateAndLocation) {
                        return const Iterable<Map<String, dynamic>>.empty();
                      }
                      
                      if (textEditingValue.text.isEmpty) {
                        // Show all locations when empty
                        return _filteredTakeoffLocations;
                      }
                      
                      // Filter locations by name - matches any word and handles special chars
                      final query = textEditingValue.text;
                      return _filteredTakeoffLocations.where((location) {
                        final name = (location['name'] ?? '').toString();
                        return _locationMatchesQuery(name, query);
                      });
                    },
                    displayStringForOption: (Map<String, dynamic> option) => option['name'] ?? '',
                    onSelected: (Map<String, dynamic> selection) {
                      setState(() {
                        _takeoffController.text = selection['name'] ?? '';
                        _takeoffAltitudeController.text = (selection['altitude']?.toString() ?? '1000');
                        _takeoffFromDropdown = true;
                      });
                    },
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      // One-time sync: ensure autocomplete controller matches our backing state
                      if (controller.text != _takeoffController.text) {
                        controller.text = _takeoffController.text;
                        controller.selection = TextSelection.collapsed(offset: controller.text.length);
                      }

                      return ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (context, textValue, _) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            readOnly: !canEditDateAndLocation,
                            onTap: () {
                              // Select-all on tap so user can immediately type to replace
                              if (controller.text.isNotEmpty) {
                                controller.selection = TextSelection(
                                  baseOffset: 0,
                                  extentOffset: controller.text.length,
                                );
                              }
                            },
                            onChanged: (text) {
                              if (text != _takeoffController.text) {
                                _takeoffController.text = text;
                              }
                              if (_takeoffFromDropdown && mounted) {
                                setState(() => _takeoffFromDropdown = false);
                              }
                            },
                            decoration: InputDecoration(
                              labelText: _t('Takeoff_Location', lang),
                              prefixIcon: const Icon(Icons.flight_takeoff),
                              suffixIcon: canEditDateAndLocation
                                  ? (textValue.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear, size: 20),
                                          tooltip: 'Clear takeoff',
                                          onPressed: () {
                                            controller.clear();
                                            setState(() {
                                              _takeoffController.clear();
                                              _takeoffAltitudeController.text = '1000';
                                              _takeoffFromDropdown = false;
                                            });
                                            focusNode.requestFocus();
                                          },
                                        )
                                      : (_filteredTakeoffLocations.isNotEmpty
                                          ? const Icon(Icons.arrow_drop_down)
                                          : null))
                                  : null,
                              border: const OutlineInputBorder(),
                              enabled: canEditDateAndLocation,
                              helperText: _filteredTakeoffLocations.isNotEmpty
                                  ? _t('Type_Or_Select', lang)
                                  : null,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _takeoffAltitudeController,
                    readOnly: _takeoffFromDropdown && canEditDateAndLocation,
                    enabled: !(_takeoffFromDropdown && canEditDateAndLocation),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: InputDecoration(
                      labelText: _t('Takeoff_Altitude', lang),
                      prefixIcon: const Icon(Icons.height),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                      enabled: canEditDateAndLocation,
                      helperText: _takeoffFromDropdown ? _t('Auto_Filled', lang) : ' ',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Landing Location and Altitude - Side by side (75% location, 25% altitude)
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Autocomplete<Map<String, dynamic>>(
                    key: ValueKey<String>('landing_${_selectedFormSchoolId ?? 'none'}'),
                    initialValue: TextEditingValue(text: _landingController.text),
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (!canEditDateAndLocation) {
                        return const Iterable<Map<String, dynamic>>.empty();
                      }
                      
                      if (textEditingValue.text.isEmpty) {
                        // Show all locations when empty
                        return _filteredLandingLocations;
                      }
                      
                      // Filter locations by name - matches any word and handles special chars
                      final query = textEditingValue.text;
                      return _filteredLandingLocations.where((location) {
                        final name = (location['name'] ?? '').toString();
                        return _locationMatchesQuery(name, query);
                      });
                    },
                    displayStringForOption: (Map<String, dynamic> option) => option['name'] ?? '',
                    onSelected: (Map<String, dynamic> selection) {
                      setState(() {
                        _landingController.text = selection['name'] ?? '';
                        _landingAltitudeController.text = (selection['altitude']?.toString() ?? '500');
                        _landingFromDropdown = true;
                      });
                    },
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      // One-time sync: ensure autocomplete controller matches our backing state
                      if (controller.text != _landingController.text) {
                        controller.text = _landingController.text;
                        controller.selection = TextSelection.collapsed(offset: controller.text.length);
                      }

                      return ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (context, textValue, _) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            readOnly: !canEditDateAndLocation,
                            onTap: () {
                              // Select-all on tap so user can immediately type to replace
                              if (controller.text.isNotEmpty) {
                                controller.selection = TextSelection(
                                  baseOffset: 0,
                                  extentOffset: controller.text.length,
                                );
                              }
                            },
                            onChanged: (text) {
                              if (text != _landingController.text) {
                                _landingController.text = text;
                              }
                              if (_landingFromDropdown && mounted) {
                                setState(() => _landingFromDropdown = false);
                              }
                            },
                            decoration: InputDecoration(
                              labelText: _t('Landing_Location', lang),
                              prefixIcon: const Icon(Icons.flight_land),
                              suffixIcon: canEditDateAndLocation
                                  ? (textValue.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear, size: 20),
                                          tooltip: 'Clear landing',
                                          onPressed: () {
                                            controller.clear();
                                            setState(() {
                                              _landingController.clear();
                                              _landingAltitudeController.text = '500';
                                              _landingFromDropdown = false;
                                            });
                                            focusNode.requestFocus();
                                          },
                                        )
                                      : (_filteredLandingLocations.isNotEmpty
                                          ? const Icon(Icons.arrow_drop_down)
                                          : null))
                                  : null,
                              border: const OutlineInputBorder(),
                              enabled: canEditDateAndLocation,
                              helperText: _filteredLandingLocations.isNotEmpty
                                  ? _t('Type_Or_Select', lang)
                                  : null,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _landingAltitudeController,
                    readOnly: _landingFromDropdown && canEditDateAndLocation,
                    enabled: !(_landingFromDropdown && canEditDateAndLocation),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: InputDecoration(
                      labelText: _t('Landing_Altitude', lang),
                      prefixIcon: const Icon(Icons.height),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                      enabled: canEditDateAndLocation,
                      helperText: _landingFromDropdown ? _t('Auto_Filled', lang) : ' ',
                    ),
                  ),
                ),
              ],
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
                      Text(_t('Hours', lang)),
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
                      Text(_t('Minutes', lang)),
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

            // Start Type Dropdown
            _buildStartTypeDropdown(),
            const SizedBox(height: 12),

            // Flight Type Dropdown
            _buildFlightTypeDropdown(),
            const SizedBox(height: 12),

            // Maneuvers Selection (always visible)
            _buildManeuversSelection(),
            const SizedBox(height: 12),

            // Comment
            TextField(
              controller: _commentController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: _t('Comment', lang),
                border: const OutlineInputBorder(),
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
                    : Text(
                        isEdit
                            ? _t('Edit_Flight', lang)
                            : (widget.isNewFromGps
                                ? _t('Save_GPS_Flight', lang)
                                : _t('Save', lang)),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
