import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/auth_service.dart';
import '../main.dart';
import 'dashboard_screen.dart';
import 'profile_screen.dart';
import 'theory_screen.dart';
import 'checklists_screen.dart';
import 'flightbook_screen.dart';
import 'gps_screen.dart';
import 'tests_screen.dart';
import '../services/app_config_service.dart';
import '../services/app_version_service.dart';
import '../services/update_service.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/custom_status_bar.dart';
import '../widgets/update_dialog.dart';
import '../services/gtc_service.dart';
import '../services/profile_service.dart';
import '../services/test_service.dart';
import '../models/test_model.dart';
import '../services/stats_service.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  String _currentTitle = 'Dashboard';
  late PageController _pageController;

  final List<Widget> _widgetOptions = <Widget>[
    const DashboardScreen(),
    const ChecklistsScreen(),
    const FlightBookScreen(),
    const GpsScreen(),
    const TheoryScreen(),
    const TestsScreen(),
    const ProfileScreen(),
  ];

  static const Map<String, Map<String, String>> _localizedLabels = {
    'en': {
      'dashboard': 'Dashboard',
      'checklist': 'Checklist',
      'flightbook': 'Flight Book',
      'gps': 'GPS',
      'theory': 'Theory',
      'tests': 'Tests',
      'profile': 'Profile',
      'menu': 'Menu',
      'logout': 'Logout',
      'check_updates': 'Check for Updates',
      'checking_updates': 'Checking for updates...',
      'no_updates': 'You are using the latest version',
      'update_available': 'Update Available!',
    },
    'de': {
      'dashboard': 'Übersicht',
      'checklist': 'Checkliste',
      'flightbook': 'Flugbuch',
      'gps': 'GPS',
      'theory': 'Theorie',
      'tests': 'Prüfungen',
      'profile': 'Profil',
      'menu': 'Menü',
      'logout': 'Abmelden',
      'check_updates': 'Nach Updates suchen',
      'checking_updates': 'Suche nach Updates...',
      'no_updates': 'Sie verwenden die neueste Version',
      'update_available': 'Update verfügbar!',
    },
  };

  String _getLabel(BuildContext context, String key) {
    final lang = context.read<AppConfigService>().displayLanguageCode;
    return _localizedLabels[lang]?[key] ?? _localizedLabels['en']![key]!;
  }

  List<String> _getTitles(BuildContext context) {
    return [
      _getLabel(context, 'dashboard'),
      _getLabel(context, 'checklist'),
      _getLabel(context, 'flightbook'),
      _getLabel(context, 'gps'),
      _getLabel(context, 'theory'),
      _getLabel(context, 'tests'),
      _getLabel(context, 'profile'),
    ];
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    
    // Check for app updates - now screen is fully loaded and ready to show dialog
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      _currentTitle = _getTitles(context)[index];
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _onPageChanged(int index) {
    setState(() {
      _selectedIndex = index;
      _currentTitle = _getTitles(context)[index];
    });
  }

  Future<void> _handleLogout(BuildContext context) async {
    try {
      await context.read<AuthService>().signOut(context);
      if (context.mounted) {
        AppRestartWrapper.restartApp(context);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error during logout: $e')),
        );
      }
    }
  }

  void _showBottomMenu(BuildContext context) {
    final navBarColor = Theme.of(context).appBarTheme.backgroundColor ?? Colors.black;

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        color: navBarColor,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(8),
          children: [
            ListTile(
              leading: const Icon(Icons.person, color: Colors.white),
              title: Text(_getLabel(context, 'profile'), style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _onItemTapped(6); // Navigate to Profile screen
              },
            ),
            const Divider(color: Colors.grey),
            ListTile(
              leading: const Icon(Icons.system_update_alt, color: Colors.blue),
              title: Text(_getLabel(context, 'check_updates')),
              onTap: () {
                Navigator.pop(context);
                _manualCheckForUpdates();
              },
            ),
            const Divider(color: Colors.grey),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: Text(_getLabel(context, 'logout'), style: const TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _handleLogout(context);
              },
            ),
            const Divider(color: Colors.grey),
            // App version info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'App Version',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FutureBuilder<String>(
                    future: AppVersionService.getFullVersion(),
                    builder: (context, snapshot) {
                      return Text(
                        snapshot.data ?? 'Loading...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Check for app updates and show dialog if update is available
  Future<void> _checkForUpdates() async {
    try {
      final updateService = context.read<UpdateService>();

      // ============================================================
      // AKTÍV: Firestore alapú verzió-ellenőrzés
      // (régen: GitHub / Google Drive metadata.json)
      // ============================================================
      final hasUpdate = await updateService.checkForUpdates();

      // ============================================================
      // RÉGI – KOMMENTÁLVA (GitHub / Google Drive)
      // const metadataUrl = 'https://raw.githubusercontent.com/buddymajki/SAFETY_Flightdeck2/master/metadata.json';
      // final hasUpdate = await updateService.checkForUpdatesFromGoogleDrive(metadataUrl);
      // ============================================================

      if (hasUpdate && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) => UpdateDialog(
            onSkip: () => debugPrint('[Update] User skipped update'),
            onUpdate: () => debugPrint('[Update] User opened Firebase App Distribution'),
          ),
        );
      }
    } catch (e) {
      debugPrint('[Update] Error checking for updates: $e');
    }
  }

  /// Manual check for updates (triggered by user from drawer menu)
  Future<void> _manualCheckForUpdates() async {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_getLabel(context, 'checking_updates')),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      final updateService = context.read<UpdateService>();

      // ============================================================
      // AKTÍV: Firestore alapú verzió-ellenőrzés
      // ============================================================
      final hasUpdate = await updateService.checkForUpdates();

      // ============================================================
      // RÉGI – KOMMENTÁLVA (GitHub / Google Drive)
      // const metadataUrl = 'https://raw.githubusercontent.com/buddymajki/SAFETY_Flightdeck2/master/metadata.json';
      // final hasUpdate = await updateService.checkForUpdatesFromGoogleDrive(metadataUrl);
      // ============================================================

      if (!mounted) return;

      if (hasUpdate) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_getLabel(context, 'update_available')),
            duration: const Duration(seconds: 1),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext dialogContext) => UpdateDialog(
              onSkip: () => debugPrint('[Update] User skipped update'),
              onUpdate: () => debugPrint('[Update] User opened Firebase App Distribution'),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_getLabel(context, 'no_updates')),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('[Update] Error checking for updates: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error checking for updates'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navBarColor = theme.appBarTheme.backgroundColor ?? Colors.black;
    final primaryColor = theme.primaryColor;

    // GTC notification logic - only show badge if UNACCEPTED (not signed/accepted)
    final gtcService = context.watch<GTCService>();
    final profileService = context.watch<ProfileService>();
    final profile = profileService.userProfile;
    final isStudent = (profile?.license ?? '').toLowerCase() == 'student';
    final schoolId = profile?.mainSchoolId;
    final hasUnacceptedGtc = isStudent && schoolId != null && gtcService.getGTCForSchool(schoolId) != null && !gtcService.isGTCAcceptedForSchool(schoolId);

    // Test notification logic - show badge only if user has actionable tests available
    // First, ensure submissions are loaded so we can check accurately
    final testService = context.watch<TestService>();
    if (profile != null && profile.uid != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Load submissions in background if not already loaded
        testService.loadUserSubmissions(profile.uid!).catchError((e) {
          debugPrint('[MainNavigation] Error loading submissions: $e');
          return <TestSubmission>[];
        });
      });
    }

    bool showTestsBadge = hasUnacceptedGtc;
    if (!showTestsBadge && profile != null && profile.uid != null) {
      final statsService = context.watch<StatsService>();
      final statsJson = statsService.stats.toJson();
      // Use sync check with cached submissions
      showTestsBadge = testService.hasAvailableTestsSync(
        userId: profile.uid!,
        statsJson: statsJson,
      );
    }

    return Consumer<AppConfigService>(
      builder: (context, cfg, _) {
        final code = cfg.displayLanguageCode.toUpperCase();
        return Scaffold(
          appBar: null, // Removed - using CustomStatusBar instead
          body: Column(
            children: [
              // Custom status bar at the top (replaces native Android status bar)
              const CustomStatusBar(),
              // App header with title and language selector
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                color: theme.appBarTheme.backgroundColor ?? Colors.black87,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _currentTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18.0,
                        color: Colors.white,
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Language',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        child: Text(
                          code,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      onSelected: (value) {
                        context.read<AppConfigService>().setLanguage(value);
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem<String>(value: 'en', child: Text('EN')),
                        const PopupMenuItem<String>(value: 'de', child: Text('DE')),
                      ],
                    ),
                  ],
                ),
              ),
              // Main content area
              Expanded(
                child: ResponsiveContainer(
                  maxWidth: 1200,
                  padding: EdgeInsets.zero,
                  child: PageView(
                    controller: _pageController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    onPageChanged: _onPageChanged,
                    children: _widgetOptions,
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: Container(
            color: navBarColor,
            height: 70,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildNavBarItem(
                  icon: Icons.dashboard,
                  label: _getLabel(context, 'dashboard'),
                  isSelected: _selectedIndex == 0,
                  onTap: () => _onItemTapped(0),
                  primaryColor: primaryColor,
                ),
                _buildNavBarItem(
                  icon: Icons.fact_check,
                  label: _getLabel(context, 'checklist'),
                  isSelected: _selectedIndex == 1,
                  onTap: () => _onItemTapped(1),
                  primaryColor: primaryColor,
                ),
                _buildNavBarItem(
                  icon: Icons.book,
                  label: _getLabel(context, 'flightbook'),
                  isSelected: _selectedIndex == 2,
                  onTap: () => _onItemTapped(2),
                  primaryColor: primaryColor,
                ),
                _buildNavBarItem(
                  icon: Icons.gps_fixed,
                  label: _getLabel(context, 'gps'),
                  isSelected: _selectedIndex == 3,
                  onTap: () => _onItemTapped(3),
                  primaryColor: primaryColor,
                ),
                _buildNavBarItem(
                  icon: Icons.school,
                  label: _getLabel(context, 'theory'),
                  isSelected: _selectedIndex == 4,
                  onTap: () => _onItemTapped(4),
                  primaryColor: primaryColor,
                ),
                _buildNavBarItem(
                  icon: Icons.quiz,
                  label: _getLabel(context, 'tests'),
                  isSelected: _selectedIndex == 5,
                  onTap: () => _onItemTapped(5),
                  primaryColor: primaryColor,
                  showBadge: showTestsBadge,
                ),
                InkWell(
                  onTap: () => _showBottomMenu(context),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.menu,
                        size: 24,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getLabel(context, 'menu'),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavBarItem({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required Color primaryColor,
    bool showBadge = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 24,
                color: isSelected ? primaryColor : Colors.grey.shade400,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected ? primaryColor : Colors.grey.shade400,
                ),
              ),
            ],
          ),
          if (showBadge)
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.orange,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
