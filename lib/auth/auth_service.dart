import 'dart:developer';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../services/global_data_service.dart';
import '../services/user_data_service.dart';
import '../services/flight_service.dart';
import '../services/stats_service.dart';
import '../services/profile_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  
  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOut(BuildContext context) async {
    // Always clear local caches before signing out to avoid stale data.
    try {
      context.read<UserDataService>().resetService();
      context.read<GlobalDataService>().resetService();
      context.read<FlightService>().resetService();
      context.read<StatsService>().resetService();
      await context.read<ProfileService>().resetService();
    } catch (e) {
      // If providers are not available in this context, ignore.
      log('[AuthService] resetService during signOut failed: $e');
    } finally {
      await _auth.signOut();
    }
  }
}
