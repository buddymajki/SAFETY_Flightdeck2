import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'config/app_theme.dart';
import 'services/global_data_service.dart';
import 'services/user_data_service.dart';
import 'services/app_config_service.dart';
import 'services/profile_service.dart';
import 'services/flight_service.dart';
import 'services/stats_service.dart';
import 'auth/auth_service.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_navigation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Ensure offline persistence is enabled where supported.
  try {
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GlobalDataService()),
        ChangeNotifierProvider(create: (_) => AppConfigService()),
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
        ChangeNotifierProxyProvider2<AuthService, ProfileService, FlightService>(
          create: (_) => FlightService(),
          update: (_, authService, profileService, flightService) {
            final service = flightService ?? FlightService();
            final uid = authService.currentUser?.uid;
            final schoolId = profileService.userProfile?.schoolId;
            if (uid != null && schoolId != null && schoolId.isNotEmpty) {
              service.initializeData(uid, schoolId);
            } else if (uid != null && schoolId == null) {
              // Profile not loaded yet, wait briefly
              Future.delayed(const Duration(milliseconds: 500)).then((_) {
                if (profileService.userProfile?.schoolId != null) {
                  service.initializeData(uid, profileService.userProfile!.schoolId!);
                }
              });
            } else {
              service.resetService();
            }
            return service;
          },
        ),
        // StatsService lifecycle: depends on all data services
        ChangeNotifierProxyProvider4<AuthService, FlightService, UserDataService, GlobalDataService, StatsService>(
          create: (_) => StatsService(),
          update: (_, authService, flightService, userDataService, globalDataService, statsService) {
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
class StatsUpdateWatcher extends StatefulWidget {
  final Widget child;
  
  const StatsUpdateWatcher({super.key, required this.child});

  @override
  State<StatsUpdateWatcher> createState() => _StatsUpdateWatcherState();
}

class _StatsUpdateWatcherState extends State<StatsUpdateWatcher> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
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
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
