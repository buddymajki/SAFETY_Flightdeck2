import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';

import 'firebase_options.dart';
import 'config/app_theme.dart';
import 'services/global_data_service.dart';
import 'services/user_data_service.dart';
import 'services/app_config_service.dart';
import 'services/dashboard_config_service.dart';
import 'services/profile_service.dart';
import 'services/flight_service.dart';
import 'services/flight_tracking_service.dart';
import 'services/live_tracking_service.dart';
import 'services/gps_sensor_service.dart';
import 'services/stats_service.dart';
import 'services/gtc_service.dart';
import 'services/test_service.dart';
import 'services/connectivity_service.dart';
import 'services/update_service.dart';
import 'auth/auth_service.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_navigation.dart';
import 'widgets/update_dialog.dart';

import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Hide all system UI - we'll use a custom status bar widget instead
  // This is the most reliable way to ensure consistent UI across all Android devices
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Ensure offline persistence is enabled where supported.
  try {
    FirebaseFirestore.instance.settings =
        const Settings(persistenceEnabled: true);
  } catch (_) {}

  runApp(const AppRestartWrapper(child: MyApp()));
}

class AppRestartWrapper extends StatefulWidget {
  const AppRestartWrapper({super.key, required this.child});

  final Widget child;

  static void restartApp(BuildContext context) {
    final state = context.findAncestorStateOfType<_AppRestartWrapperState>();
    state?._restart();
  }

  @override
  State<AppRestartWrapper> createState() => _AppRestartWrapperState();
}

class _AppRestartWrapperState extends State<AppRestartWrapper> {
  Key _appKey = UniqueKey();

  void _restart() {
    setState(() {
      _appKey = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _appKey,
      child: widget.child,
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // ConnectivityService - initialized early for offline support
        ChangeNotifierProvider(create: (_) {
          final service = ConnectivityService();
          service.initialize();
          return service;
        }),
        ChangeNotifierProvider(create: (_) => UpdateService()),
        ChangeNotifierProvider(create: (_) => GlobalDataService()),
        ChangeNotifierProvider(create: (_) => AppConfigService()),
        ChangeNotifierProvider(create: (_) => GTCService()),
        ChangeNotifierProvider(create: (_) => TestService()),
        ChangeNotifierProvider(create: (_) => DashboardConfigService()),
        ChangeNotifierProvider(create: (_) => GpsSensorService()),
        Provider(create: (_) => AuthService()),
        // ProfileService lifecycle: reload when auth state changes
        ChangeNotifierProxyProvider<AuthService, ProfileService>(
          create: (_) => ProfileService(),
          update: (_, authService, profileService) {
            final service = profileService ?? ProfileService();
            final uid = authService.currentUser?.uid;
            if (uid != null) {
              service.initializeData(uid);
            } else {
              service.resetService();
            }
            return service;
          },
        ),
        // UserDataService lifecycle: reload when auth state changes
        ChangeNotifierProxyProvider<AuthService, UserDataService>(
          create: (_) => UserDataService(),
          update: (_, authService, userDataService) {
            final service = userDataService ?? UserDataService();
            final uid = authService.currentUser?.uid;
            if (uid != null) {
              service.initializeData(uid);
            } else {
              service.resetService();
            }
            return service;
          },
        ),
        // FlightService lifecycle: reload when auth state or profile changes
        ChangeNotifierProxyProvider2<AuthService, ProfileService,
            FlightService>(
          create: (_) => FlightService(),
          update: (_, authService, profileService, flightService) {
            final service = flightService ?? FlightService();
            final uid = authService.currentUser?.uid;
            final mainSchoolId = profileService.userProfile?.mainSchoolId;

            if (uid != null) {
              // Flights should load even if the main school is not yet set; pass empty string when missing
              service.initializeData(uid, mainSchoolId ?? '');
            } else {
              service.resetService();
            }
            return service;
          },
        ),
        // LiveTrackingService - depends on ProfileService
        ChangeNotifierProxyProvider<ProfileService, LiveTrackingService>(
          create: (_) => LiveTrackingService(),
          update: (_, profileService, liveTrackingService) {
            final service = liveTrackingService ?? LiveTrackingService();
            // Update profile data for live tracking
            service.updateProfile(profileService.userProfile);
            return service;
          },
        ),
        // FlightTrackingService lifecycle: depends on GlobalDataService, AppConfigService, LiveTrackingService, and AuthService
        // NOTE: Also needs AuthService to handle user-specific cache isolation
        ChangeNotifierProxyProvider4<GlobalDataService, AppConfigService, LiveTrackingService, AuthService,
            FlightTrackingService>(
          create: (_) => FlightTrackingService(),
          update: (_, globalDataService, appConfigService, liveTrackingService, authService, trackingService) {
            final service = trackingService ?? FlightTrackingService();
            
            // CRITICAL: Set current user for cache isolation
            // This ensures pending tracklogs are user-specific
            final uid = authService.currentUser?.uid;
            service.setCurrentUser(uid);
            
            if (globalDataService.globalLocations != null) {
              service.initialize(
                globalDataService.globalLocations!,
                lang: appConfigService.currentLanguageCode,
              );
            }
            // Connect live tracking service
            service.setLiveTrackingService(liveTrackingService);
            return service;
          },
        ),
        // StatsService lifecycle: depends on all data services
        ChangeNotifierProxyProvider4<AuthService, FlightService,
            UserDataService, GlobalDataService, StatsService>(
          create: (_) => StatsService(),
          update: (_, authService, flightService, userDataService,
              globalDataService, statsService) {
            final service = statsService ?? StatsService();
            final uid = authService.currentUser?.uid;

            // Inject service references for offline-first calculation
            service.flightService = flightService;
            service.userDataService = userDataService;
            service.globalDataService = globalDataService;

            if (uid != null) {
              service.initializeData(uid);
            } else {
              service.resetService();
            }
            return service;
          },
        ),
      ],
      child: MaterialApp(
        title: 'FlightDeck',
        theme: AppTheme.dark(),
        home: const StatsUpdateWatcher(child: SplashScreen()),
        routes: {
          '/login': (context) => const LoginScreen(),
          '/home': (context) => const MainNavigationScreen(),
        },
      ),
    );
  }
}

/// Widget that connects flight and checklist services to stats updates
/// AND handles GPS initialization + callback wiring.
/// This widget lives INSIDE the MultiProvider tree so it has access to all providers.
class StatsUpdateWatcher extends StatefulWidget {
  final Widget child;

  const StatsUpdateWatcher({super.key, required this.child});

  @override
  State<StatsUpdateWatcher> createState() => _StatsUpdateWatcherState();
}

class _StatsUpdateWatcherState extends State<StatsUpdateWatcher> with WidgetsBindingObserver {
  bool _gpsInitialized = false;
  bool _callbacksWired = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cleanupGpsCallbacks();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Check for app updates (moved to MainNavigationScreen to avoid splash screen race condition)
    // _checkForUpdates();

    // Wire up stats update callbacks
    final statsService = context.read<StatsService>();
    final flightService = context.read<FlightService>();
    final userDataService = context.read<UserDataService>();

    flightService.onFlightDataChanged = () {
      statsService.updateStats();
    };

    userDataService.onChecklistDataChanged = () {
      statsService.updateStats();
    };

    // Wire up GPS callbacks globally (not just on GPS screen)
    _wireGpsCallbacks();

    // Initialize GPS tracking on first build
    if (!_gpsInitialized) {
      _gpsInitialized = true;
      // Use addPostFrameCallback to ensure context is fully ready
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initializeGpsTracking();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[AppLifecycle] App resumed - checking GPS');
      _initializeGpsTracking();
    }
  }

  /// Wire GPS position/sensor callbacks to FlightTrackingService
  /// This ensures positions reach flight detection even if user never visits GPS screen
  void _wireGpsCallbacks() {
    if (_callbacksWired) return;
    _callbacksWired = true;

    try {
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

      debugPrint('[GpsInit] GPS callbacks wired globally');
    } catch (e) {
      debugPrint('[GpsInit] Error wiring GPS callbacks: $e');
      _callbacksWired = false; // Retry on next didChangeDependencies
    }
  }

  void _cleanupGpsCallbacks() {
    try {
      final gpsSensorService = context.read<GpsSensorService>();
      gpsSensorService.onPositionUpdate = null;
      gpsSensorService.onAccelerometerUpdate = null;
      gpsSensorService.onGyroscopeUpdate = null;
    } catch (_) {}
  }

  Future<void> _initializeGpsTracking() async {
    try {
      if (!mounted) return;
      
      final gpsSensorService = context.read<GpsSensorService>();
      final trackingService = context.read<FlightTrackingService>();
      
      // If GPS stream is already running, still ensure FlightTrackingService is enabled.
      // Fixes emulator/demo case where GPS icon is green but Current Status doesn't update
      // because processPosition short-circuits when tracking is disabled.
      if (gpsSensorService.isTracking) {
        await trackingService.enableTracking();
        return;
      }
      
      // Check if Android GPS is enabled
      final isGpsEnabled = await Geolocator.isLocationServiceEnabled();
      
      if (!isGpsEnabled) {
        debugPrint('[GpsInit] Android GPS is disabled - prompting user');
        if (mounted) {
          _showGpsDisabledDialog();
        }
        return;
      }
      
      // GPS is enabled, start tracking
      final success = await gpsSensorService.autoStartTracking();
      if (success) {
        await trackingService.enableTracking();
        debugPrint('[GpsInit] GPS tracking auto-started successfully');
      } else {
        debugPrint('[GpsInit] GPS tracking failed to start (permission issue?)');
      }
    } catch (e) {
      debugPrint('[GpsInit] Error initializing GPS: $e');
    }
  }

  void _showGpsDisabledDialog() {
    // Avoid showing dialog if Navigator isn't ready yet (e.g., still on splash screen)
    final navigator = Navigator.maybeOf(context);
    if (navigator == null) {
      debugPrint('[GpsInit] Navigator not ready, will retry on next lifecycle event');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('GPS Required'),
        content: const Text(
          'Flight tracking requires GPS to be enabled. '
          'Please enable GPS in your device settings.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Geolocator.openLocationSettings();
            },
            child: const Text('Enable GPS'),
          ),
        ],
      ),
    );
  }

  /// Check for app updates and show dialog if update is available
  Future<void> _checkForUpdates() async {
    try {
      final updateService = context.read<UpdateService>();
      
      // Check for updates in background
      final hasUpdate = await updateService.checkForUpdates();
      
      if (hasUpdate && mounted) {
        // Show update dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) => UpdateDialog(
            onSkip: () {
              debugPrint('[Update] User skipped update');
            },
            onUpdate: () {
              debugPrint('[Update] Update installed successfully');
            },
          ),
        );
      }
    } catch (e) {
      debugPrint('[Update] Error checking for updates: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
