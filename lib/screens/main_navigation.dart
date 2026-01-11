import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/auth_service.dart';
import '../main.dart';
import 'dashboard_screen.dart';
import 'profile_screen.dart';
import 'theory_screen.dart';
import 'checklists_screen.dart';
import 'flightbook_screen.dart';
import 'tests_screen.dart';
import '../services/app_config_service.dart';
import '../widgets/responsive_layout.dart';

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
    const TheoryScreen(),
    const TestsScreen(),
    const ProfileScreen(),
  ];


  static const Map<String, Map<String, String>> _localizedLabels = {
    'en': {
      'dashboard': 'Dashboard',
      'checklist': 'Checklist',
      'flightbook': 'Flight Book',
      'theory': 'Theory',
      'tests': 'Tests',
      'profile': 'Profile',
      'menu': 'Menu',
      'logout': 'Logout',
    },
    'de': {
      'dashboard': 'Übersicht',
      'checklist': 'Checkliste',
      'flightbook': 'Flugbuch',
      'theory': 'Theorie',
      'tests': 'Prüfungen',
      'profile': 'Profil',
      'menu': 'Menü',
      'logout': 'Abmelden',
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
      _getLabel(context, 'theory'),
      _getLabel(context, 'tests'),
      _getLabel(context, 'profile'),
    ];
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
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
                _onItemTapped(5); // Navigate to Profile screen
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
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navBarColor = theme.appBarTheme.backgroundColor ?? Colors.black;
    final primaryColor = theme.primaryColor;

    return Consumer<AppConfigService>(
      builder: (context, cfg, _) {
        final code = cfg.displayLanguageCode.toUpperCase();
        return Scaffold(
          appBar: AppBar(
            title: Text(
              _currentTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
            actions: [
              PopupMenuButton<String>(
                tooltip: 'Language',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Center(
                    child: Text(
                      code,
                      style: const TextStyle(fontWeight: FontWeight.bold),
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
          body: ResponsiveContainer(
            maxWidth: 1200,
            padding: EdgeInsets.zero,
            child: PageView(
              controller: _pageController,
              physics: const AlwaysScrollableScrollPhysics(),
              onPageChanged: _onPageChanged,
              children: _widgetOptions,
            ),
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
                  icon: Icons.school,
                  label: _getLabel(context, 'theory'),
                  isSelected: _selectedIndex == 3,
                  onTap: () => _onItemTapped(3),
                  primaryColor: primaryColor,
                ),
                _buildNavBarItem(
                  icon: Icons.quiz,
                  label: _getLabel(context, 'tests'),
                  isSelected: _selectedIndex == 4,
                  onTap: () => _onItemTapped(4),
                  primaryColor: primaryColor,
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
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
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
    );
  }
}
