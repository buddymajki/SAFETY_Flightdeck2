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

  runApp(const MyApp());
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
      ],
      child: MaterialApp(
        title: 'FlightDeck',
        theme: AppTheme.dark(),
        home: const SplashScreen(),
        routes: {
          '/login': (context) => const LoginScreen(),
          '/home': (context) => const MainNavigationScreen(),
        },
      ),
    );
  }
}
