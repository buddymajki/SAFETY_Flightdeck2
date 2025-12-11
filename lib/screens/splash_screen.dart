import 'dart:developer';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/global_data_service.dart';
import '../services/user_data_service.dart';
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
      // Initialize global + user data in parallel
      final global = context.read<GlobalDataService>();
      final user = context.read<UserDataService>();

      await Future.wait([
        global.initializeData(),
        user.initializeData(uid),
      ]);

      log('[Splash] Data load complete. globals=${global.globalChecklists?.length ?? 0} uid=$uid');

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
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
