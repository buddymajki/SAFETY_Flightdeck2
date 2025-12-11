import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/auth_service.dart';
import 'dashboard_screen.dart';
import 'profile_screen.dart';
import 'theory_screen.dart';
import 'checklists_screen.dart';
import 'flightbook_screen.dart';
import '../services/app_config_service.dart';

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
    const ProfileScreen(),
  ];

  final List<String> _titles = <String>[
    'Dashboard',
    'Checklist',
    'Flight Book',
    'Theory',
    'Profile',
  ];

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
      _currentTitle = _titles[index];
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
      _currentTitle = _titles[index];
    });
  }

  Future<void> _handleLogout(BuildContext context) async {
    try {
      await context.read<AuthService>().signOut(context);
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/login',
          (route) => false,
        );
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
              leading: const Icon(Icons.settings, color: Colors.white),
              title: const Text('Settings', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _onItemTapped(4); // Go to Profile
              },
            ),
            const Divider(color: Colors.grey),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          // Language selector
          Consumer<AppConfigService>(
            builder: (context, cfg, _) {
              final code = cfg.displayLanguageCode.toUpperCase();
              return PopupMenuButton<String>(
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
              );
            },
          ),
        ],
      ),
      body: PageView(
        controller: _pageController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: _widgetOptions,
        onPageChanged: _onPageChanged,
      ),
      bottomNavigationBar: Container(
        color: navBarColor,
        height: 70,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNavBarItem(
              icon: Icons.dashboard,
              label: 'Dashboard',
              isSelected: _selectedIndex == 0,
              onTap: () => _onItemTapped(0),
              primaryColor: primaryColor,
            ),
            _buildNavBarItem(
              icon: Icons.fact_check,
              label: 'Checklist',
              isSelected: _selectedIndex == 1,
              onTap: () => _onItemTapped(1),
              primaryColor: primaryColor,
            ),
            _buildNavBarItem(
              icon: Icons.book,
              label: 'Flight Book',
              isSelected: _selectedIndex == 2,
              onTap: () => _onItemTapped(2),
              primaryColor: primaryColor,
            ),
            _buildNavBarItem(
              icon: Icons.school,
              label: 'Theory',
              isSelected: _selectedIndex == 3,
              onTap: () => _onItemTapped(3),
              primaryColor: primaryColor,
            ),
            _buildNavBarItem(
              icon: Icons.settings,
              label: 'Profile',
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
                    'Menu',
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
