import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/auth_service.dart';
import '../config/app_theme.dart';
import '../services/global_data_service.dart';
import '../services/user_data_service.dart';

class MainNavigation extends StatelessWidget {
  const MainNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FlightDeck'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await context.read<AuthService>().signOut(context);
              if (context.mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil(
                  '/login',
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: Consumer2<GlobalDataService, UserDataService>(
        builder: (context, globalDataService, userDataService, _) {
          return SingleChildScrollView(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 32),
                    // User UID Card
                    Card(
                      color: AppTheme.cardBackground,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            const Text(
                              'Logged-In User',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              userDataService.uid ?? 'N/A',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                                fontFamily: 'monospace',
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // User Profile Fields
                    Card(
                      color: AppTheme.cardBackground,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'User Profile',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ..._buildProfileDetails(userDataService.profile),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Global Data Counts
                    Card(
                      color: AppTheme.cardBackground,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            const Text(
                              'Global Data Loaded',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildCountRow('Global Checklists', globalDataService.globalChecklists?.length ?? 0),
                            _buildCountRow('Flight Types', globalDataService.globalFlighttypes?.length ?? 0),
                            _buildCountRow('Locations', globalDataService.globalLocations?.length ?? 0),
                            _buildCountRow('Maneuvers', globalDataService.globalManeuverlist?.length ?? 0),
                            _buildCountRow('School Maneuvers', globalDataService.globalSchoolmaneuvers?.length ?? 0),
                            _buildCountRow('Schools', globalDataService.schools?.length ?? 0),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // User Data Counts
                    Card(
                      color: AppTheme.cardBackground,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            const Text(
                              'User Data Loaded',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildCountRow('Flight Log Entries', userDataService.flightlog.length),
                            _buildCountRow('Checklist Progress', userDataService.checklistprogress.length),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Sign Out Button
                    ElevatedButton.icon(
                      onPressed: () async {
                        await context.read<AuthService>().signOut(context);
                        if (context.mounted) {
                          Navigator.of(context).pushNamedAndRemoveUntil(
                            '/login',
                            (route) => false,
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      ),
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign Out'),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCountRow(String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white70,
            ),
          ),
          Text(
            count.toString(),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildProfileDetails(Map<String, dynamic>? profile) {
    if (profile == null || profile.isEmpty) {
      return const [
        Text(
          'No profile data loaded.',
          style: TextStyle(fontSize: 14, color: Colors.white70),
        ),
      ];
    }

    final entries = profile.entries
        .where((e) => e.key != 'id')
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (entries.isEmpty) {
      return const [
        Text(
          'Profile has no fields.',
          style: TextStyle(fontSize: 14, color: Colors.white70),
        ),
      ];
    }

    return entries
        .map((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      e.key,
                      style: const TextStyle(fontSize: 14, color: Colors.white70),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      _stringify(e.value),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 14, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ))
        .toList();
  }

  String _stringify(Object? value) {
    if (value == null) return '—';
    if (value is Timestamp) return value.toDate().toIso8601String();
    return value.toString();
  }
}
