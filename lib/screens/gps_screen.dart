// File: lib/screens/gps_screen.dart

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/tracked_flight.dart';
import '../services/flight_tracking_service.dart';
import '../services/gps_sensor_service.dart';
import '../services/app_config_service.dart';
import '../services/global_data_service.dart';
import '../services/tracklog_parser_service.dart';
import '../widgets/responsive_layout.dart';

class GpsScreen extends StatefulWidget {
  const GpsScreen({super.key});

  @override
  State<GpsScreen> createState() => _GpsScreenState();
}

class _GpsScreenState extends State<GpsScreen> with WidgetsBindingObserver {
  // Localization
  static const Map<String, Map<String, String>> _texts = {
    'GPS_Tracking': {'en': 'GPS Tracking', 'de': 'GPS-Tracking'},
    'Enable_Tracking': {'en': 'Enable Tracking', 'de': 'Tracking aktivieren'},
    'Tracking_Active': {'en': 'Tracking Active', 'de': 'Tracking aktiv'},
    'Tracking_Disabled': {'en': 'Tracking Disabled', 'de': 'Tracking deaktiviert'},
    'Current_Status': {'en': 'Current Status', 'de': 'Aktueller Status'},
    'In_Flight': {'en': 'IN FLIGHT', 'de': 'IM FLUG'},
    'On_Ground': {'en': 'On Ground', 'de': 'Am Boden'},
    'Recent_Flights': {'en': 'Recent Flights', 'de': 'Letzte Flüge'},
    'No_Flights': {'en': 'No tracked flights yet', 'de': 'Noch keine Flüge aufgezeichnet'},
    'Flight': {'en': 'Flight', 'de': 'Flug'},
    'Takeoff': {'en': 'Takeoff', 'de': 'Start'},
    'Landing': {'en': 'Landing', 'de': 'Landung'},
    'Airtime': {'en': 'Airtime', 'de': 'Flugzeit'},
    'Send_Firebase': {'en': 'Send to Firebase', 'de': 'An Firebase senden'},
    'Synced': {'en': 'Synced', 'de': 'Synchronisiert'},
    'Delete': {'en': 'Delete', 'de': 'Löschen'},
    'Cancel_Flight': {'en': 'Cancel Flight', 'de': 'Flug abbrechen'},
    'Nearest_Site': {'en': 'Nearest Site', 'de': 'Nächster Standort'},
    'Distance': {'en': 'Distance', 'de': 'Entfernung'},
    'Altitude': {'en': 'Altitude', 'de': 'Höhe'},
    'Speed': {'en': 'Speed', 'de': 'Geschwindigkeit'},
    'Test_Mode': {'en': 'Test Mode', 'de': 'Testmodus'},
    'Load_Tracklog': {'en': 'Load Tracklog', 'de': 'Tracklog laden'},
    'Generate_Test': {'en': 'Generate Test Flight', 'de': 'Testflug generieren'},
    'Stop_Simulation': {'en': 'Stop Simulation', 'de': 'Simulation stoppen'},
    'Running_Simulation': {'en': 'Running Simulation...', 'de': 'Simulation läuft...'},
    'Confirm_Delete': {'en': 'Delete this flight?', 'de': 'Diesen Flug löschen?'},
    'Yes': {'en': 'Yes', 'de': 'Ja'},
    'No': {'en': 'No', 'de': 'Nein'},
    'Feature_Stub': {'en': 'Firebase sync will be implemented later', 'de': 'Firebase-Sync wird später implementiert'},
    'Vertical_Speed': {'en': 'V/S', 'de': 'V/S'},
    'Web_Not_Supported': {'en': 'GPS tracking is not available in web browser', 'de': 'GPS-Tracking ist im Webbrowser nicht verfügbar'},
    'Use_Mobile_App': {'en': 'Please use the Android or iOS app for flight tracking', 'de': 'Bitte nutzen Sie die Android- oder iOS-App für das Flug-Tracking'},
    'Permission_Required': {'en': 'Location permission required', 'de': 'Standortberechtigung erforderlich'},
    'Grant_Permission': {'en': 'Grant Permission', 'de': 'Berechtigung erteilen'},
    'Open_Settings': {'en': 'Open Settings', 'de': 'Einstellungen öffnen'},
    'Background_Permission': {'en': 'Background location access recommended for continuous tracking', 'de': 'Hintergrund-Standortzugriff empfohlen für kontinuierliches Tracking'},
    'Battery_Optimization': {'en': 'Disable battery optimization for reliable tracking', 'de': 'Batterieoptimierung deaktivieren für zuverlässiges Tracking'},
    'Takeoff_Detected': {'en': 'TAKEOFF DETECTED', 'de': 'START ERKANNT'},
    'Landing_Detected': {'en': 'LANDING DETECTED', 'de': 'LANDUNG ERKANNT'},
    'Analyzing_Tracklog': {'en': 'Analyzing tracklog...', 'de': 'Analysiere Tracklog...'},
    'Flights_Detected': {'en': 'flights detected', 'de': 'Flüge erkannt'},
    'Error_Loading_File': {'en': 'Error loading file', 'de': 'Fehler beim Laden der Datei'},
    'Invalid_File_Format': {'en': 'Invalid file format. Supported: GPX, IGC, KML, JSON', 'de': 'Ungültiges Dateiformat. Unterstützt: GPX, IGC, KML, JSON'},
  };

  String _t(String key, String lang) {
    return _texts[key]?[lang] ?? _texts[key]?['en'] ?? key;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeService();
    _setupGpsCallbacks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cleanupGpsCallbacks();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle for background tracking
    // GPS tracking continues in background via the native service
    super.didChangeAppLifecycleState(state);
  }

  void _setupGpsCallbacks() {
    if (kIsWeb) return; // No GPS on web
    
    final gpsSensorService = context.read<GpsSensorService>();
    final trackingService = context.read<FlightTrackingService>();

    // Connect GPS position updates to flight tracking service
    gpsSensorService.onPositionUpdate = (position) {
      trackingService.processPosition(
        latitude: position.latitude,
        longitude: position.longitude,
        altitude: position.altitude,
        speed: position.speed,
        heading: position.heading,
        timestamp: position.timestamp,
      );
    };

    // Connect accelerometer updates
    gpsSensorService.onAccelerometerUpdate = (event) {
      trackingService.processSensorData(
        accelerometerX: event.x,
        accelerometerY: event.y,
        accelerometerZ: event.z,
      );
    };

    // Connect gyroscope updates
    gpsSensorService.onGyroscopeUpdate = (event) {
      trackingService.processSensorData(
        gyroscopeX: event.x,
        gyroscopeY: event.y,
        gyroscopeZ: event.z,
      );
    };
  }

  void _cleanupGpsCallbacks() {
    if (kIsWeb) return;
    
    final gpsSensorService = context.read<GpsSensorService>();
    gpsSensorService.onPositionUpdate = null;
    gpsSensorService.onAccelerometerUpdate = null;
    gpsSensorService.onGyroscopeUpdate = null;
  }

  Future<void> _initializeService() async {
    final globalData = context.read<GlobalDataService>();
    final trackingService = context.read<FlightTrackingService>();
    final appConfig = context.read<AppConfigService>();

    // Initialize with sites from GlobalDataService
    if (globalData.globalLocations != null) {
      await trackingService.initialize(
        globalData.globalLocations!,
        lang: appConfig.currentLanguageCode,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = context.watch<AppConfigService>();
    final lang = appConfig.currentLanguageCode;
    final trackingService = context.watch<FlightTrackingService>();
    final globalData = context.watch<GlobalDataService>();
    final gpsSensorService = context.watch<GpsSensorService>();

    // Update sites if they change
    if (globalData.globalLocations != null && trackingService.isInitialized) {
      trackingService.updateSites(globalData.globalLocations!);
      trackingService.setLanguage(lang);
    }

    return ResponsiveContainer(
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Show web warning if on web platform
              if (kIsWeb) _buildWebWarning(context, lang),
              _buildTrackingToggle(context, trackingService, gpsSensorService, lang),
              // Show permission card if needed (only on mobile)
              if (!kIsWeb && !gpsSensorService.hasLocationPermission && gpsSensorService.errorMessage != null)
                _buildPermissionCard(context, gpsSensorService, lang),
              _buildStatusCard(context, trackingService, lang),
              if (trackingService.isInFlight)
                _buildCurrentFlightCard(context, trackingService, lang),
              _buildTestModeCard(context, trackingService, lang),
              _buildRecentFlightsSection(context, trackingService, lang),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebWarning(BuildContext context, String lang) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(12),
      color: Colors.orange.shade900,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.white, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('Web_Not_Supported', lang),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _t('Use_Mobile_App', lang),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
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

  Widget _buildPermissionCard(
    BuildContext context,
    GpsSensorService gpsSensorService,
    String lang,
  ) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.red.shade900,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_off, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _t('Permission_Required', lang),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            if (gpsSensorService.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                gpsSensorService.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await gpsSensorService.checkAndRequestPermissions();
                    },
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: Text(
                      _t('Grant_Permission', lang),
                      style: const TextStyle(color: Colors.white),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white54),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await gpsSensorService.openAppSettings();
                    },
                    icon: const Icon(Icons.settings, color: Colors.white),
                    label: Text(
                      _t('Open_Settings', lang),
                      style: const TextStyle(color: Colors.white),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white54),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackingToggle(
    BuildContext context,
    FlightTrackingService service,
    GpsSensorService gpsSensorService,
    String lang,
  ) {
    final theme = Theme.of(context);
    final isEnabled = service.isTrackingEnabled;
    final isWebPlatform = kIsWeb;

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              isEnabled ? Icons.gps_fixed : Icons.gps_off,
              color: isWebPlatform 
                  ? Colors.grey.shade600
                  : (isEnabled ? Colors.green : Colors.grey),
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('GPS_Tracking', lang),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isWebPlatform ? Colors.grey : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isWebPlatform
                        ? _t('Web_Not_Supported', lang)
                        : (isEnabled
                            ? _t('Tracking_Active', lang)
                            : _t('Tracking_Disabled', lang)),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isWebPlatform 
                          ? Colors.grey
                          : (isEnabled ? Colors.green : Colors.grey),
                    ),
                  ),
                  // Show background permission hint
                  if (!isWebPlatform && !gpsSensorService.hasBackgroundPermission && isEnabled) ...[
                    const SizedBox(height: 4),
                    Text(
                      _t('Background_Permission', lang),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.orange,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Switch(
              value: isEnabled,
              onChanged: isWebPlatform
                  ? null // Disabled on web
                  : (value) async {
                      if (value) {
                        // Request permissions before enabling
                        final status = await gpsSensorService.checkAndRequestPermissions();
                        if (status.isGranted) {
                          await service.toggleTracking();
                          // Start GPS tracking
                          await gpsSensorService.startTracking();
                          // Request battery optimization exemption
                          await gpsSensorService.requestBatteryOptimizationExemption();
                        }
                      } else {
                        await service.toggleTracking();
                        await gpsSensorService.stopTracking();
                      }
                    },
              activeColor: Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(
    BuildContext context,
    FlightTrackingService service,
    String lang,
  ) {
    final theme = Theme.of(context);
    final position = service.lastPosition;
    final isInFlight = service.isInFlight;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: isInFlight ? Colors.blue.shade900 : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isInFlight ? Icons.flight_takeoff : Icons.landscape,
                  color: isInFlight ? Colors.white : theme.iconTheme.color,
                ),
                const SizedBox(width: 8),
                Text(
                  _t('Current_Status', lang),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isInFlight ? Colors.white : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isInFlight
                    ? Colors.green.shade700
                    : theme.cardColor.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.currentStatus,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isInFlight ? Colors.white : null,
                    ),
                  ),
                  // Show current location (coordinates and site name)
                  if (position != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 16,
                          color: isInFlight ? Colors.white70 : Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: isInFlight ? Colors.white70 : Colors.grey,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              if (service.nearestSiteName != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '📍 ${service.nearestSiteName}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: isInFlight ? Colors.white : Colors.blue,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  // Show flight event status
                  if (service.lastFlightEvent != null) ...[
                    const SizedBox(height: 8),
                    Chip(
                      label: Text(
                        service.lastFlightEvent!.type.toString().split('.').last.toUpperCase() == 'TAKEOFF'
                            ? _t('Takeoff_Detected', lang)
                            : _t('Landing_Detected', lang),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      backgroundColor: service.lastFlightEvent!.type.toString().split('.').last.toUpperCase() == 'TAKEOFF'
                          ? Colors.green.shade600
                          : Colors.red.shade600,
                      side: const BorderSide(color: Colors.white30),
                    ),
                  ],
                ],
              ),
            ),
            if (service.nearestSiteName != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.place,
                    size: 16,
                    color: isInFlight ? Colors.white70 : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_t('Nearest_Site', lang)}: ${service.nearestSiteName}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isInFlight ? Colors.white70 : Colors.grey,
                    ),
                  ),
                  if (service.nearestSiteDistance != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '(${service.nearestSiteDistance!.toStringAsFixed(0)}m)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isInFlight ? Colors.white60 : Colors.grey,
                      ),
                    ),
                  ],
                ],
              ),
            ],
            if (position != null) ...[
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDataRow(
                    context,
                    Icons.height,
                    '${_t('Altitude', lang)}',
                    '${position.altitude.toStringAsFixed(0)} m',
                    isInFlight,
                  ),
                  const SizedBox(height: 6),
                  _buildDataRow(
                    context,
                    Icons.speed,
                    '${_t('Speed', lang)}',
                    '${((position.speed ?? 0.0) * 3.6).toStringAsFixed(1)} km/h',
                    isInFlight,
                  ),
                  const SizedBox(height: 6),
                  _buildDataRow(
                    context,
                    (position.verticalSpeed ?? 0.0) >= 0
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    '${_t('Vertical_Speed', lang)}',
                    '${(position.verticalSpeed ?? 0.0).toStringAsFixed(2)} m/s',
                    isInFlight,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    bool isInFlight,
  ) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isInFlight ? Colors.white70 : Colors.grey,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isInFlight ? Colors.white70 : Colors.grey,
              ),
            ),
          ],
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: isInFlight ? Colors.white : null,
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentFlightCard(
    BuildContext context,
    FlightTrackingService service,
    String lang,
  ) {
    final theme = Theme.of(context);
    final flight = service.currentFlight!;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.orange.shade900,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flight, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_t('In_Flight', lang)} - ${flight.takeoffSiteName}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_t('Airtime', lang)}: ${FlightTrackingService.formatDuration(flight.flightTimeMinutes)}',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white,
                  ),
                ),
                Text(
                  '${flight.trackPoints.length} points',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _confirmCancelFlight(context, service, lang),
                icon: const Icon(Icons.cancel, color: Colors.white70),
                label: Text(
                  _t('Cancel_Flight', lang),
                  style: const TextStyle(color: Colors.white70),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white54),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestModeCard(
    BuildContext context,
    FlightTrackingService service,
    String lang,
  ) {
    final theme = Theme.of(context);
    final isSimulating = service.isSimulating;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        leading: Icon(
          Icons.science,
          color: isSimulating ? Colors.orange : null,
        ),
        title: Text(
          _t('Test_Mode', lang),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: isSimulating
            ? Text(
                _t('Running_Simulation', lang),
                style: const TextStyle(color: Colors.orange),
              )
            : null,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isSimulating) ...[
                  ElevatedButton.icon(
                    onPressed: () => service.stopSimulation(),
                    icon: const Icon(Icons.stop),
                    label: Text(_t('Stop_Simulation', lang)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    onPressed: () => _generateAndRunTestFlight(service),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(_t('Generate_Test', lang)),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _loadTracklogFile(service),
                    icon: const Icon(Icons.folder_open),
                    label: Text(_t('Load_Tracklog', lang)),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Supported formats: GPX, IGC, KML, JSON',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentFlightsSection(
    BuildContext context,
    FlightTrackingService service,
    String lang,
  ) {
    final theme = Theme.of(context);
    final flights = service.trackedFlights;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            _t('Recent_Flights', lang),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (flights.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.flight_takeoff,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _t('No_Flights', lang),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...flights.asMap().entries.map((entry) {
            final index = entry.key;
            final flight = entry.value;
            final flightNumber = flights.length - index;
            return _buildFlightCard(context, flight, flightNumber, service, lang);
          }),
      ],
    );
  }

  Widget _buildFlightCard(
    BuildContext context,
    TrackedFlight flight,
    int flightNumber,
    FlightTrackingService service,
    String lang,
  ) {
    final theme = Theme.of(context);
    final dateFormatter = DateFormat('dd.MM.yyyy HH:mm');

    final statusColor = switch (flight.status) {
      FlightTrackingStatus.completed => Colors.green,
      FlightTrackingStatus.cancelled => Colors.orange,
      FlightTrackingStatus.inFlight => Colors.blue,
    };

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${_t('Flight', lang)} #$flightNumber',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    flight.status.name.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (flight.isSyncedToFirebase)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.cloud_done,
                      color: Colors.green.shade400,
                      size: 20,
                    ),
                  ),
              ],
            ),
            const Divider(height: 16),

            // Flight details
            _buildFlightDetailRow(
              context,
              Icons.flight_takeoff,
              _t('Takeoff', lang),
              '${flight.takeoffSiteName}\n${dateFormatter.format(flight.takeoffTime)}',
            ),
            const SizedBox(height: 8),
            _buildFlightDetailRow(
              context,
              Icons.flight_land,
              _t('Landing', lang),
              flight.landingTime != null
                  ? '${flight.landingSiteName ?? "Unknown"}\n${dateFormatter.format(flight.landingTime!)}'
                  : '-',
            ),
            const SizedBox(height: 8),
            _buildFlightDetailRow(
              context,
              Icons.timer,
              _t('Airtime', lang),
              FlightTrackingService.formatDuration(flight.flightTimeMinutes),
            ),

            // Actions
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!flight.isSyncedToFirebase &&
                    flight.status == FlightTrackingStatus.completed)
                  TextButton.icon(
                    onPressed: () => _sendToFirebase(context, flight, lang),
                    icon: const Icon(Icons.cloud_upload, size: 18),
                    label: Text(_t('Send_Firebase', lang)),
                  ),
                IconButton(
                  onPressed: () =>
                      _confirmDeleteFlight(context, service, flight, lang),
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.red.shade400,
                  tooltip: _t('Delete', lang),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlightDetailRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  // ============================================
  // ACTIONS
  // ============================================

  Future<void> _generateAndRunTestFlight(FlightTrackingService service) async {
    final tracklog = service.generateTestTracklog(
      duration: const Duration(minutes: 20),
    );
    await service.startSimulation(tracklog, interval: const Duration(milliseconds: 50));
  }

  Future<void> _startTracklogSimulation(FlightTrackingService service, List<TrackPoint> trackPoints) async {
    // Start the simulation with faster playback
    await service.startSimulation(trackPoints, interval: const Duration(milliseconds: 100));
  }

  Future<void> _loadTracklogFile(FlightTrackingService service) async {
    if (!mounted) return;

    try {
      // Pick a file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gpx', 'igc', 'kml', 'json'],
        lockParentWindow: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      
      // Show loading dialog
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(_t('Analyzing_Tracklog', _getCurrentLanguage())),
          content: const SizedBox(
            height: 40,
            child: Center(
              child: CircularProgressIndicator(),
            ),
          ),
        ),
      );

      // Read file contents
      final fileBytes = file.bytes;
      if (fileBytes == null) {
        Navigator.pop(context);
        _showErrorDialog(context, _t('Error_Loading_File', _getCurrentLanguage()));
        return;
      }

      final fileContent = String.fromCharCodes(fileBytes);
      final extension = file.extension?.toLowerCase() ?? '';

      // Parse the file based on extension
      List<TrackPoint> trackPoints = [];
      try {
        switch (extension) {
          case 'gpx':
            trackPoints = TracklogParserService.parseGpx(fileContent);
            break;
          case 'igc':
            trackPoints = TracklogParserService.parseIgc(fileContent);
            break;
          case 'kml':
            trackPoints = TracklogParserService.parseKml(fileContent);
            break;
          case 'json':
            trackPoints = TracklogParserService.parseJson(fileContent);
            break;
          default:
            throw Exception('Unsupported file format: $extension');
        }
      } catch (e) {
        Navigator.pop(context);
        _showErrorDialog(
          context, 
          _t('Invalid_File_Format', _getCurrentLanguage()),
        );
        return;
      }

      if (trackPoints.isEmpty) {
        Navigator.pop(context);
        _showErrorDialog(
          context,
          'No valid GPS points found in file',
        );
        return;
      }

      // Analyze the tracklog for flights
      final flights = service.analyzeTracklog(trackPoints);
      
      Navigator.pop(context); // Close loading dialog

      if (!mounted) return;
      
      // Show results
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Analysis Complete'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${trackPoints.length} GPS points analyzed',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                '${flights.length} ${_t('Flights_Detected', _getCurrentLanguage())}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              if (flights.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Detected flights:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: flights.length,
                    itemBuilder: (context, index) {
                      final flight = flights[index];
                      final duration = flight.trackPoints.isNotEmpty
                          ? flight.trackPoints.last.timestamp.difference(flight.trackPoints.first.timestamp)
                          : Duration.zero;
                      return Text(
                        '${index + 1}. ${flight.takeoffSiteName} → ${flight.landingSiteName ?? 'Unknown'} (${duration.inMinutes}m)',
                        style: const TextStyle(fontSize: 12),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _startTracklogSimulation(service, trackPoints);
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play Simulation'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        _showErrorDialog(context, 'Error: ${e.toString()}');
      }
    }
  }

  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _getCurrentLanguage() {
    try {
      return context.read<AppConfigService>().currentLanguageCode;
    } catch (e) {
      return 'en';
    }
  }

  void _confirmCancelFlight(
    BuildContext context,
    FlightTrackingService service,
    String lang,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('Cancel_Flight', lang)),
        content: const Text('Are you sure you want to cancel this flight?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_t('No', lang)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              service.cancelCurrentFlight();
            },
            child: Text(
              _t('Yes', lang),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteFlight(
    BuildContext context,
    FlightTrackingService service,
    TrackedFlight flight,
    String lang,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('Delete', lang)),
        content: Text(_t('Confirm_Delete', lang)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_t('No', lang)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              service.deleteTrackedFlight(flight.id);
            },
            child: Text(
              _t('Yes', lang),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _sendToFirebase(
    BuildContext context,
    TrackedFlight flight,
    String lang,
  ) {
    // Stub implementation - show message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_t('Feature_Stub', lang)),
        action: SnackBarAction(
          label: 'OK',
          onPressed: () {},
        ),
      ),
    );

    // TODO: Implement actual Firebase sync
    // This will convert TrackedFlight to Flight model and use FlightService.addFlight()
  }
}
