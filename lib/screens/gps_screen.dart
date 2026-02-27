// File: lib/screens/gps_screen.dart

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/tracked_flight.dart';
import '../models/flight.dart';
import '../services/flight_tracking_service.dart';
import '../services/flight_service.dart';
import '../services/gps_sensor_service.dart';
import '../services/profile_service.dart';
import '../services/app_config_service.dart';
import '../services/global_data_service.dart';
import '../services/tracklog_parser_service.dart';
import '../widgets/responsive_layout.dart';
import 'flightbook_screen.dart';

class GpsScreen extends StatefulWidget {
  const GpsScreen({super.key});

  @override
  State<GpsScreen> createState() => _GpsScreenState();
}

class _GpsScreenState extends State<GpsScreen> with WidgetsBindingObserver {
  // Localization
  static const Map<String, Map<String, String>> _texts = {
    'GPS_Tracking': {'en': 'GPS Tracking', 'de': 'GPS-Tracking', 'it': 'Tracciamento GPS', 'fr': 'Suivi GPS'},
    'Enable_Tracking': {'en': 'Enable Tracking', 'de': 'Tracking aktivieren', 'it': 'Attiva tracciamento', 'fr': 'Activer le suivi'},
    'Tracking_Active': {'en': 'Tracking Active', 'de': 'Tracking aktiv', 'it': 'Tracciamento attivo', 'fr': 'Suivi actif'},
    'Tracking_Disabled': {'en': 'Tracking Disabled', 'de': 'Tracking deaktiviert', 'it': 'Tracciamento disattivato', 'fr': 'Suivi désactivé'},
    'Current_Status': {'en': 'Current Status', 'de': 'Aktueller Status', 'it': 'Stato attuale', 'fr': 'État actuel'},
    'In_Flight': {'en': 'IN FLIGHT', 'de': 'IM FLUG', 'it': 'IN VOLO', 'fr': 'EN VOL'},
    'On_Ground': {'en': 'On Ground', 'de': 'Am Boden', 'it': 'A terra', 'fr': 'Au sol'},
    'Recent_Flights': {'en': 'Pending Tracklogs', 'de': 'Ausstehende Trackprotokolle', 'it': 'Tracklog in sospeso', 'fr': 'Tracklogs en attente'},
    'No_Flights': {'en': 'No pending tracklogs yet', 'de': 'Noch keine ausstehenden Trackprotokolle', 'it': 'Nessun tracklog in sospeso', 'fr': 'Aucun tracklog en attente'},
    'Flight': {'en': 'Flight', 'de': 'Flug', 'it': 'Volo', 'fr': 'Vol'},
    'Takeoff': {'en': 'Takeoff', 'de': 'Start', 'it': 'Decollo', 'fr': 'Décollage'},
    'Landing': {'en': 'Landing', 'de': 'Landung', 'it': 'Atterraggio', 'fr': 'Atterrissage'},
    'Airtime': {'en': 'Airtime', 'de': 'Flugzeit', 'it': 'Tempo di volo', 'fr': 'Temps de vol'},
    'Send_Firebase': {'en': 'Send to Firebase', 'de': 'An Firebase senden', 'it': 'Invia a Firebase', 'fr': 'Envoyer à Firebase'},
    'Save_To_Flight_Book': {'en': 'Save to Flight Book', 'de': 'In Flugbuch speichern', 'it': 'Salva nel libro di volo', 'fr': 'Enregistrer dans le carnet de vol'},
    'Synced': {'en': 'Synced', 'de': 'Synchronisiert', 'it': 'Sincronizzato', 'fr': 'Synchronisé'},
    'Delete': {'en': 'Delete', 'de': 'Löschen', 'it': 'Elimina', 'fr': 'Supprimer'},
    'Cancel_Flight': {'en': 'Cancel Flight', 'de': 'Flug abbrechen', 'it': 'Annulla volo', 'fr': 'Annuler le vol'},
    'Nearest_Site': {'en': 'Nearest Site', 'de': 'Nächster Standort', 'it': 'Sito più vicino', 'fr': 'Site le plus proche'},
    'Distance': {'en': 'Distance', 'de': 'Entfernung', 'it': 'Distanza', 'fr': 'Distance'},
    'Altitude': {'en': 'Altitude', 'de': 'Höhe', 'it': 'Altitudine', 'fr': 'Altitude'},
    'Speed': {'en': 'Speed', 'de': 'Geschwindigkeit', 'it': 'Velocità', 'fr': 'Vitesse'},
    'Test_Mode': {'en': 'Test Mode', 'de': 'Testmodus', 'it': 'Modalità test', 'fr': 'Mode test'},
    'Load_Tracklog': {'en': 'Load Tracklog', 'de': 'Tracklog laden', 'it': 'Carica tracklog', 'fr': 'Charger tracklog'},
    'Generate_Test': {'en': 'Generate Test Flight', 'de': 'Testflug generieren', 'it': 'Genera volo di test', 'fr': 'Générer un vol test'},
    'Stop_Simulation': {'en': 'Stop Simulation', 'de': 'Simulation stoppen', 'it': 'Ferma simulazione', 'fr': 'Arrêter la simulation'},
    'Running_Simulation': {'en': 'Running Simulation...', 'de': 'Simulation läuft...', 'it': 'Simulazione in corso...', 'fr': 'Simulation en cours...'},
    'Confirm_Delete': {'en': 'Delete this flight?', 'de': 'Diesen Flug löschen?', 'it': 'Eliminare questo volo?', 'fr': 'Supprimer ce vol ?'},
    'Yes': {'en': 'Yes', 'de': 'Ja', 'it': 'Sì', 'fr': 'Oui'},
    'No': {'en': 'No', 'de': 'Nein', 'it': 'No', 'fr': 'Non'},
    'Flight_Saved': {'en': 'Flight saved to Flight Book', 'de': 'Flug ins Flugbuch gespeichert', 'it': 'Volo salvato nel libro di volo', 'fr': 'Vol enregistré dans le carnet de vol'},
    'Feature_Stub': {'en': 'Firebase sync will be implemented later', 'de': 'Firebase-Sync wird später implementiert', 'it': 'La sincronizzazione Firebase sarà implementata in seguito', 'fr': 'La synchronisation Firebase sera implémentée plus tard'},
    'Vertical_Speed': {'en': 'V/S', 'de': 'V/S', 'it': 'V/S', 'fr': 'V/S'},
    'Web_Not_Supported': {'en': 'GPS tracking is not available in web browser', 'de': 'GPS-Tracking ist im Webbrowser nicht verfügbar', 'it': 'Il tracciamento GPS non è disponibile nel browser web', 'fr': 'Le suivi GPS n\'est pas disponible dans le navigateur web'},
    'Use_Mobile_App': {'en': 'Please use the Android or iOS app for flight tracking', 'de': 'Bitte nutzen Sie die Android- oder iOS-App für das Flug-Tracking', 'it': 'Utilizzare l\'app Android o iOS per il tracciamento dei voli', 'fr': 'Veuillez utiliser l\'application Android ou iOS pour le suivi des vols'},
    'Permission_Required': {'en': 'Location permission required', 'de': 'Standortberechtigung erforderlich', 'it': 'Autorizzazione posizione necessaria', 'fr': 'Autorisation de localisation requise'},
    'Grant_Permission': {'en': 'Grant Permission', 'de': 'Berechtigung erteilen', 'it': 'Concedi autorizzazione', 'fr': 'Accorder l\'autorisation'},
    'Open_Settings': {'en': 'Open Settings', 'de': 'Einstellungen öffnen', 'it': 'Apri impostazioni', 'fr': 'Ouvrir les paramètres'},
    'Background_Permission': {'en': 'Background location access recommended for continuous tracking', 'de': 'Hintergrund-Standortzugriff empfohlen für kontinuierliches Tracking', 'it': 'Accesso alla posizione in background consigliato per il tracciamento continuo', 'fr': 'Accès à la localisation en arrière-plan recommandé pour un suivi continu'},
    'Battery_Optimization': {'en': 'Disable battery optimization for reliable tracking', 'de': 'Batterieoptimierung deaktivieren für zuverlässiges Tracking', 'it': 'Disattivare l\'ottimizzazione batteria per un tracciamento affidabile', 'fr': 'Désactiver l\'optimisation de la batterie pour un suivi fiable'},
    'Takeoff_Detected': {'en': 'TAKEOFF DETECTED', 'de': 'START ERKANNT', 'it': 'DECOLLO RILEVATO', 'fr': 'DÉCOLLAGE DÉTECTÉ'},
    'Landing_Detected': {'en': 'LANDING DETECTED', 'de': 'LANDUNG ERKANNT', 'it': 'ATTERRAGGIO RILEVATO', 'fr': 'ATTERRISSAGE DÉTECTÉ'},
    'Analyzing_Tracklog': {'en': 'Analyzing tracklog...', 'de': 'Analysiere Tracklog...', 'it': 'Analisi tracklog...', 'fr': 'Analyse du tracklog...'},
    'Flights_Detected': {'en': 'flights detected', 'de': 'Flüge erkannt', 'it': 'voli rilevati', 'fr': 'vols détectés'},
    'Error_Loading_File': {'en': 'Error loading file', 'de': 'Fehler beim Laden der Datei', 'it': 'Errore nel caricamento del file', 'fr': 'Erreur lors du chargement du fichier'},
    'Invalid_File_Format': {'en': 'Invalid file format. Supported: GPX, IGC, KML, JSON', 'de': 'Ungültiges Dateiformat. Unterstützt: GPX, IGC, KML, JSON', 'it': 'Formato file non valido. Supportati: GPX, IGC, KML, JSON', 'fr': 'Format de fichier invalide. Supportés : GPX, IGC, KML, JSON'},
    'Clear_All': {'en': 'Clear All', 'de': 'Alle löschen', 'it': 'Cancella tutto', 'fr': 'Tout effacer'},
    'Clear_All_Title': {'en': 'Clear All?', 'de': 'Alle löschen?', 'it': 'Cancellare tutto?', 'fr': 'Tout effacer ?'},
    'Clear_All_Message': {'en': 'Delete all pending tracklogs? This action cannot be undone.', 'de': 'Möchtest du alle ausstehenden Trackprotokolle löschen? Diese Aktion kann nicht rückgängig gemacht werden.', 'it': 'Eliminare tutti i tracklog in sospeso? Questa azione non può essere annullata.', 'fr': 'Supprimer tous les tracklogs en attente ? Cette action est irréversible.'},
    'All_Cleared': {'en': 'All tracklogs cleared', 'de': 'Alle Trackprotokolle gelöscht', 'it': 'Tutti i tracklog cancellati', 'fr': 'Tous les tracklogs effacés'},
    'GPS_Enabled': {'en': 'GPS Tracking', 'de': 'GPS-Tracking', 'it': 'Tracciamento GPS', 'fr': 'Suivi GPS'},
    'Audio_Feedback': {'en': 'Audio Feedback', 'de': 'Audio-Feedback', 'it': 'Feedback audio', 'fr': 'Retour audio'},
  };

  String _t(String key, String lang) {
    return _texts[key]?[lang] ?? _texts[key]?['en'] ?? key;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeService();
    // NOTE: GPS callbacks (onPositionUpdate → processPosition) are now
    // wired globally in StatsUpdateWatcher, not here.
    // This screen is purely for display/monitoring.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // NOTE: No callback cleanup needed - callbacks are managed globally
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle for background tracking
    // GPS tracking continues in background via the native service
    super.didChangeAppLifecycleState(state);
  }

  // GPS callbacks (_setupGpsCallbacks / _cleanupGpsCallbacks) have been
  // moved to StatsUpdateWatcher in main.dart for global lifecycle management.
  // Position updates now reach FlightTrackingService regardless of which screen
  // the user is on.

  Future<void> _initializeService() async {
    final globalData = context.read<GlobalDataService>();
    final trackingService = context.read<FlightTrackingService>();
    final appConfig = context.read<AppConfigService>();

    // Initialize with sites from GlobalDataService
    // This will load pending tracklogs from cache and notify listeners
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
              _buildGpsStatusCard(context, trackingService, gpsSensorService, lang),
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

  Widget _buildGpsStatusCard(
    BuildContext context,
    FlightTrackingService service,
    GpsSensorService gpsSensorService,
    String lang,
  ) {
    final theme = Theme.of(context);
    final isWebPlatform = kIsWeb;
    
    // Check actual position signal and tracking status
    final hasGpsSignal = gpsSensorService.lastPosition != null;
    final isTracking = gpsSensorService.isTracking;
    final isGpsToggleOn = isTracking || service.isTrackingEnabled;
    
    // Determine status color and message
    Color statusColor = Colors.red;
    String statusText = 'Phone GPS Disabled';
    
    if (!isGpsToggleOn) {
      statusColor = Colors.grey;
      statusText = _t('Tracking_Disabled', lang);
    } else if (isTracking) {
      if (hasGpsSignal) {
        statusColor = Colors.green;
        statusText = 'GPS Signal OK';
      } else {
        statusColor = Colors.orange;
        statusText = 'Searching for GPS signal...';
      }
    }
    
    return Card(
      margin: const EdgeInsets.all(12),
      color: statusColor.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasGpsSignal && isGpsToggleOn ? Icons.gps_fixed : Icons.gps_off,
                  color: statusColor,
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
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isWebPlatform ? _t('Web_Not_Supported', lang) : statusText,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!isWebPlatform) ...[
              const SizedBox(height: 16),
              // GPS on/off toggle
              Row(
                children: [
                  Icon(
                    isGpsToggleOn ? Icons.gps_fixed : Icons.gps_off,
                    color: isGpsToggleOn ? Colors.green : Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _t('GPS_Enabled', lang),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Switch(
                    value: isGpsToggleOn,
                    activeColor: Colors.green,
                    onChanged: (value) async {
                      if (value) {
                        // Turn GPS on
                        final success = await gpsSensorService.autoStartTracking();
                        if (success) {
                          await service.enableTracking();
                        }
                      } else {
                        // Turn GPS off
                        await service.disableTracking();
                        await gpsSensorService.stopTracking();
                      }
                    },
                  ),
                ],
              ),
              const Divider(height: 8),
              // Audio feedback on/off toggle
              Row(
                children: [
                  Icon(
                    service.audioFeedbackEnabled ? Icons.volume_up : Icons.volume_off,
                    color: service.audioFeedbackEnabled ? Colors.blue : Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _t('Audio_Feedback', lang),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Switch(
                    value: service.audioFeedbackEnabled,
                    activeColor: Colors.blue,
                    onChanged: (value) async {
                      await service.setAudioFeedback(value);
                    },
                  ),
                ],
              ),
            ],
            if (!isWebPlatform && !gpsSensorService.hasBackgroundPermission && isTracking) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _t('Background_Permission', lang),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.orange,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
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
            if (isInFlight)
              _buildInFlightStatus(context, service, position, theme, lang)
            else
              _buildGroundStatus(context, service, position, theme, lang),
          ],
        ),
      ),
    );
  }

  /// Build status display for in-flight state
  Widget _buildInFlightStatus(
    BuildContext context,
    FlightTrackingService service,
    TrackPoint? position,
    ThemeData theme,
    String lang,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.green.shade700,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                service.currentStatus,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
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
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white70,
                              fontFamily: 'monospace',
                            ),
                          ),
                          if (service.nearestSiteName != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              '📍 ${service.nearestSiteName}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white,
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
        if (position != null) ...[
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDataRow(
                context,
                Icons.height,
                _t('Altitude', lang),
                '${position.altitude.toStringAsFixed(0)} m',
                true,
              ),
              const SizedBox(height: 6),
              _buildDataRow(
                context,
                Icons.speed,
                _t('Speed', lang),
                '${((position.speed ?? 0.0) * 3.6).toStringAsFixed(1)} km/h',
                true,
              ),
              const SizedBox(height: 6),
              _buildDataRow(
                context,
                (position.verticalSpeed ?? 0.0) >= 0
                    ? Icons.arrow_upward
                    : Icons.arrow_downward,
                _t('Vertical_Speed', lang),
                '${(position.verticalSpeed ?? 0.0).toStringAsFixed(2)} m/s',
                true,
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Build status display for ground state
  Widget _buildGroundStatus(
    BuildContext context,
    FlightTrackingService service,
    TrackPoint? position,
    ThemeData theme,
    String lang,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.cardColor.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Show current coordinates only (no status message)
              if (position != null) ...[
                Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      size: 18,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current Position',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              // Show nearest takeoff site
              if (service.nearestTakeoffSiteName != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.flight_takeoff,
                      size: 18,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Closest Takeoff',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  service.nearestTakeoffSiteName!,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (service.nearestTakeoffSiteDistance != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '${service.nearestTakeoffSiteDistance!.toStringAsFixed(0)} m',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              // Show nearest landing site
              if (service.nearestLandingSiteName != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.flight_land,
                      size: 18,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Closest Landing',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  service.nearestLandingSiteName!,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (service.nearestLandingSiteDistance != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '${service.nearestLandingSiteDistance!.toStringAsFixed(0)} m',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _t('Recent_Flights', lang),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              // Show "Clear All" button when there are flights
              if (flights.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _confirmClearAllTracklogs(context, service, lang),
                  icon: const Icon(Icons.delete_sweep, size: 18),
                  label: Text(
                    _t('Clear_All', lang),
                    style: TextStyle(color: Colors.red.shade400),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade400,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
            ],
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
                    color: statusColor.withValues(alpha: 0.2),
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

            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!flight.isSyncedToFirebase &&
                    flight.status == FlightTrackingStatus.completed)
                  TextButton.icon(
                    onPressed: () => _saveFlightToBook(context, flight, lang),
                    icon: const Icon(Icons.save, size: 18),
                    label: Text(_t('Save_To_Flight_Book', lang)),
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
    await service.startSimulation(tracklog, interval: const Duration(milliseconds: 400)); //helyszín: flight_tracking_serviceben, de itt lehet a szimulációt gyorsítan v lassítani nagyobb számmal
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

  void _saveFlightToBook(
    BuildContext context,
    TrackedFlight trackedFlight,
    String lang,
  ) {
    final profileService = context.read<ProfileService>();
    final globalDataService = context.read<GlobalDataService>();
    final profile = profileService.userProfile;
    if (profile == null) return;

    // Get locations from global data service
    final locations = globalDataService.globalLocations ?? [];

    // Find takeoff location in database to get official altitude
    double takeoffAltitude = trackedFlight.takeoffAltitude;
    final takeoffLocation = locations.firstWhere(
      (loc) => (loc['name'] ?? '').toString().toLowerCase() == trackedFlight.takeoffSiteName.toLowerCase(),
      orElse: () => <String, dynamic>{},
    );
    if (takeoffLocation.isNotEmpty && takeoffLocation['altitude'] != null) {
      takeoffAltitude = (takeoffLocation['altitude'] as num).toDouble();
    }

    // Find landing location in database to get official altitude
    double landingAltitude = trackedFlight.landingAltitude ?? 0.0;
    if (trackedFlight.landingSiteName != null) {
      final landingLocation = locations.firstWhere(
        (loc) => (loc['name'] ?? '').toString().toLowerCase() == trackedFlight.landingSiteName!.toLowerCase(),
        orElse: () => <String, dynamic>{},
      );
      if (landingLocation.isNotEmpty && landingLocation['altitude'] != null) {
        landingAltitude = (landingLocation['altitude'] as num).toDouble();
      }
    }

    // Create a Flight object pre-filled with GPS tracking data
    // Handle nullable fields from TrackedFlight with defaults
    final flight = Flight(
      studentUid: profile.uid ?? '',
      mainSchoolId: profile.mainSchoolId ?? '',
      thisFlightSchoolId: profile.mainSchoolId ?? '',
      date: trackedFlight.takeoffTime.toIso8601String(),
      takeoffName: trackedFlight.takeoffSiteName,
      takeoffId: null,
      takeoffAltitude: takeoffAltitude,
      landingName: trackedFlight.landingSiteName ?? 'Unknown Landing',
      landingId: null,
      landingAltitude: landingAltitude,
      altitudeDifference: takeoffAltitude - landingAltitude,
      flightTimeMinutes: trackedFlight.flightTimeMinutes,
      comment: null,
      startTypeId: null,
      flightTypeId: null,
      advancedManeuvers: const [],
      schoolManeuvers: const [],
      licenseType: profile.license ?? 'student',
      status: 'pending',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      gpsTracked: true,
    );

    // Show the flight book form with pre-filled data using a helper method
    _showSaveToFlightBookModal(context, flight, trackedFlight.id, lang);
  }

  void _showSaveToFlightBookModal(
    BuildContext context,
    Flight flight,
    String trackedFlightId,
    String lang,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => AddEditFlightForm(
        flightService: context.read<FlightService>(),
        profileService: context.read<ProfileService>(),
        flight: flight,
        gpsTracked: true,
        isNewFromGps: true,
        onSaved: () {
          Navigator.pop(context);
          // Remove the tracked flight from pending tracklogs after successful save
          final trackingService = context.read<FlightTrackingService>();
          trackingService.removeTrackedFlight(trackedFlightId);
          // Set status to Standby after flight is saved
          trackingService.setStatusToStandby();
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

  void _confirmClearAllTracklogs(
    BuildContext context,
    FlightTrackingService service,
    String lang,
  ) {
    final count = service.trackedFlights.length;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('Clear_All_Title', lang)),
        content: Text(
          _t('Clear_All_Message', lang),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_t('No', lang)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await service.clearAllPendingTracklogs();
              // Also clear any orphaned tracklogs from old cache format
              await FlightTrackingService.clearOrphanedTracklogs();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _t('All_Cleared', lang),
                    ),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            child: Text(
              _t('Clear_All', lang),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

}

