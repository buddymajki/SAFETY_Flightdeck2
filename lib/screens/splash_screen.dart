import 'dart:developer';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/flight_service.dart';
import '../services/global_data_service.dart';
import '../services/stats_service.dart';
import '../services/user_data_service.dart';
import '../services/profile_service.dart';
import '../services/dashboard_config_service.dart';
import 'login_screen.dart';
import 'main_navigation.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadData();
    });
  }

  Future<void> _preloadData() async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (!mounted) return;

    if (currentUser == null) {
      // Not logged in; go to Login
      _goTo(const LoginScreen());
      return;
    }

    final uid = currentUser.uid;

    try {
      // Initialize global + user + profile + flight + stats + dashboard config data
      final global = context.read<GlobalDataService>();
      final user = context.read<UserDataService>();
      final profile = context.read<ProfileService>();
      final flight = context.read<FlightService>();
      final stats = context.read<StatsService>();
      final dashboardConfig = context.read<DashboardConfigService>();

      // Phase 1: Initialize global + user data + dashboard config
      await Future.wait<void>([
        global.initializeData(),
        user.initializeData(uid),
        dashboardConfig.init(),
      ]);

      // Phase 2: Initialize profile (needed to get schoolId)
      await profile.initializeData(uid);

      // Get schoolId from profile for flight + stats initialization
      final schoolId = profile.currentMainSchoolId ?? '';

      // Phase 3: Initialize flight + stats with proper user context
      await Future.wait<void>([
        flight.initializeData(uid, schoolId),
        stats.initializeData(uid),
      ]);

      log('[Splash] Data load complete. globals=${global.globalChecklists?.length ?? 0} flights=${flight.flights.length} uid=$uid');

      if (!mounted) return;
      _goTo(const MainNavigationScreen());
    } catch (e, st) {
      log('[Splash] preload error: $e', stackTrace: st);
      if (!mounted) return;
      // Show basic error and route to login
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load data: $e')),
      );
      _goTo(const LoginScreen());
    }
  }

  void _goTo(Widget page) {
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => page),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/logo_512.png',
              width: 150,
              height: 150,
            ),
            const SizedBox(height: 32),
            const Text(
              'FlightDeck v2.01',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color.fromARGB(255, 245, 245, 245),
              ),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
