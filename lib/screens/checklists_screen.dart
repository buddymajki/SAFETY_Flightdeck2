import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/checklist_item.dart';
import '../services/global_data_service.dart';
import '../services/user_data_service.dart';
import '../services/app_config_service.dart';
//import '../widgets/responsive_layout.dart';

class ChecklistsScreen extends StatefulWidget {
  const ChecklistsScreen({super.key});

  @override
  State<ChecklistsScreen> createState() => _ChecklistsScreenState();
}

class _ChecklistsScreenState extends State<ChecklistsScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  late ScrollController _tabScrollController;
  List<String> _categoryIds = [];
  int _selectedTabIndex = 0;
  late SharedPreferences _prefs;
  late Future<void> _loadIndexFuture;
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final global = context.read<GlobalDataService>();
    final items = global.allChecklistItems;

    // Build category list
    final itemsByCategory = _groupByCategory(items);
    final newCategoryIds = GlobalDataService.categoryOrder
        .where((categoryId) => itemsByCategory.containsKey(categoryId))
        .toList();

    // Only reinitialize tab controller if number of categories changed
    if (newCategoryIds.length != _categoryIds.length) {
      _categoryIds = newCategoryIds;
      _tabController.dispose();
      _tabController = TabController(length: _categoryIds.length, vsync: this);
      _tabController.addListener(_onTabChanged);
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 0, vsync: this);
    _tabScrollController = ScrollController();
    _tabScrollController.addListener(_updateScrollIndicators);
    _loadIndexFuture = _loadTabIndex();
  }

  Future<void> _loadTabIndex() async {
    _prefs = await SharedPreferences.getInstance();
    _selectedTabIndex = _prefs.getInt('checklist_tab_index') ?? 0;
    // Schedule the tab index update for after the widget builds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tabController.length > 0) {
        final targetIndex = _selectedTabIndex.clamp(0, _tabController.length - 1);
        _tabController.animateTo(
          targetIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        // Also scroll the tab bar to show the selected tab
        _scrollTabIntoView(targetIndex);
      }
    });
  }

  /// Scroll the tab bar to show the target tab index
  void _scrollTabIntoView(int tabIndex) {
    if (!_tabScrollController.hasClients) return;
    
    // Approximate position: each tab is roughly 100-120 pixels wide (including padding)
    final estimatedTabWidth = 110.0;
    final targetScroll = (tabIndex * estimatedTabWidth) - 50; // Center it roughly
    
    _tabScrollController.animateTo(
      targetScroll.clamp(0, _tabScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _saveTabIndex(int index) async {
    await _prefs.setInt('checklist_tab_index', index);
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      setState(() {
        _selectedTabIndex = _tabController.index;
      });
      _saveTabIndex(_tabController.index);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _tabScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final global = context.watch<GlobalDataService>();
    final user = context.watch<UserDataService>();
    final lang = context.watch<AppConfigService>().currentLanguageCode;

    final isLoaded = global.isInitialized && user.isInitialized;

    if (!isLoaded) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }

    final items = global.allChecklistItems;
    if (items.isEmpty) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: Text(
            'No checklists available.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    // Group items by category
    final itemsByCategory = _groupByCategory(items);
    final categoryIds = GlobalDataService.categoryOrder
        .where((categoryId) => itemsByCategory.containsKey(categoryId))
        .toList();

    // Animate to saved tab after future completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_loadIndexFuture.toString().contains('_CompleteStreamFuture')) {
        if (_tabController.length > 0 &&
            _tabController.index != _selectedTabIndex.clamp(0, _tabController.length - 1)) {
          _tabController.animateTo(
            _selectedTabIndex.clamp(0, _tabController.length - 1),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      }
    });

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          // TabBar with floating chevron buttons
          Stack(
            children: [
              SingleChildScrollView(
                controller: _tabScrollController,
                scrollDirection: Axis.horizontal,
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  indicatorSize: TabBarIndicatorSize.label,
                  tabAlignment: TabAlignment.start,
                  padding: EdgeInsets.zero,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                  labelColor: theme.colorScheme.onSurface,
                  unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.3),
                  labelStyle: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                  unselectedLabelStyle: theme.textTheme.labelMedium,
                  indicatorColor: theme.colorScheme.primary,
                    tabs: [
                      for (final categoryId in categoryIds)
                        _buildTab(context, categoryId, itemsByCategory[categoryId]!, user, lang),
                    ],
                  ),
                ),
              // Left chevron - floating button
              if (_shouldShowLeftScroll())
                Positioned(
                  left: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _scrollTabsLeft,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color: theme.colorScheme.primary.withOpacity(0.8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.chevron_left,
                          size: 18,
                          color: Colors.white.withOpacity(1.0),
                        ),
                      ),
                    ),
                  ),
                ),
              // Right chevron - floating button
              if (_shouldShowRightScroll())
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _scrollTabsRight,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color: theme.colorScheme.primary.withOpacity(0.8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: Colors.white.withOpacity(1.0),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // TabBarView content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                for (final categoryId in categoryIds)
                  _buildCategoryTabContent(
                    context,
                    categoryId,
                    itemsByCategory[categoryId]!,
                    lang,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Update scroll indicators based on actual scroll position
  void _updateScrollIndicators() {
    if (!_tabScrollController.hasClients) {
      setState(() {
        _canScrollLeft = false;
        _canScrollRight = false;
      });
      return;
    }

    final maxScroll = _tabScrollController.position.maxScrollExtent;
    final currentScroll = _tabScrollController.offset;

    setState(() {
      _canScrollLeft = currentScroll > 10; // Small threshold to avoid jitter
      _canScrollRight = (maxScroll - currentScroll) > 10;
    });
  }

  /// Scroll tabs to the left by one tab width
  void _scrollTabsLeft() {
    if (!_tabScrollController.hasClients) return;
    final scrollAmount = 120.0; // Approximate tab width
    _tabScrollController.animateTo(
      (_tabScrollController.offset - scrollAmount).clamp(0, _tabScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// Scroll tabs to the right by one tab width
  void _scrollTabsRight() {
    if (!_tabScrollController.hasClients) return;
    final scrollAmount = 120.0; // Approximate tab width
    _tabScrollController.animateTo(
      (_tabScrollController.offset + scrollAmount).clamp(0, _tabScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// Check if there are more tabs to the left to scroll
  bool _shouldShowLeftScroll() {
    return _canScrollLeft;
  }

  /// Check if there are more tabs to the right to scroll
  /// Only show if there is actual scroll space remaining
  bool _shouldShowRightScroll() {
    return _canScrollRight;
  }


  /// Build a single tab with category name and progress indicator
  Widget _buildTab(
    BuildContext context,
    String categoryId,
    List<ChecklistItem> items,
    UserDataService user,
    String languageCode,
  ) {
    final global = context.read<GlobalDataService>();
    final shortName = global.getCategoryShortName(categoryId, languageCode);

    return Tab(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 0),
        child: Text(shortName),
      ),
    );
  }

  /// Build the content for a tab (list of checklist items)
  Widget _buildCategoryTabContent(
    BuildContext context,
    String categoryId,
    List<ChecklistItem> items,
    String languageCode,
  ) {
    final theme = Theme.of(context);
    final global = context.read<GlobalDataService>();
    final user = context.watch<UserDataService>();
    final categoryTitle = global.getCategoryTitle(categoryId, languageCode);
    final completedCount = items.where((item) => user.isChecklistItemCompleted(item.id)).length;
    final total = items.length;

    return SingleChildScrollView(
      child: Column(
        children: [
          // Header with full category title and progress
          Container(
            width: double.infinity,
            color: theme.scaffoldBackgroundColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  categoryTitle,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  '$completedCount/$total',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          // Checklist items
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              children: [
                for (int index = 0; index < items.length; index++) ...[
                  _buildChecklistItemCard(context, items[index], languageCode, user),
                  if (index < items.length - 1) const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build an individual checklist item card with modern design
  Widget _buildChecklistItemCard(
    BuildContext context,
    ChecklistItem item,
    String languageCode,
    UserDataService user,
  ) {
    final theme = Theme.of(context);
    final isCompleted = user.isChecklistItemCompleted(item.id);
    final title = languageCode == 'de' ? item.title_de : item.title_en;
    final description = languageCode == 'de' ? item.description_de : item.description_en;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCompleted
              ? theme.colorScheme.primary.withOpacity(0.3)
              : theme.dividerColor.withOpacity(0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            context.read<UserDataService>().toggleProgress(item.id, !isCompleted);
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Checkbox with animation
                Padding(
                  padding: const EdgeInsets.only(right: 12, top: 2),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isCompleted
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                        width: 2,
                      ),
                      color: isCompleted ? theme.colorScheme.primary : Colors.transparent,
                    ),
                    width: 24,
                    height: 24,
                    child: isCompleted
                        ? Icon(
                            Icons.check,
                            size: 16,
                            color: theme.colorScheme.onPrimary,
                          )
                        : null,
                  ),
                ),
                // Title and description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          decoration: isCompleted ? TextDecoration.lineThrough : null,
                          color: isCompleted
                              ? theme.textTheme.bodySmall?.color?.withOpacity(0.6)
                              : null,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (description != null && description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                // Info button
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: IconButton(
                    icon: const Icon(Icons.info_outline),
                    iconSize: 20,
                    color: theme.colorScheme.primary,
                    onPressed: () {
                      _showItemDetails(context, item, languageCode);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Show detailed information about a checklist item
  void _showItemDetails(
    BuildContext context,
    ChecklistItem item,
    String languageCode,
  ) {
    final theme = Theme.of(context);
    final title = languageCode == 'de' ? item.title_de : item.title_en;
    final description = languageCode == 'de' ? item.description_de : item.description_en;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Text(
            (description == null || description.isEmpty) ? 'No description available.' : description,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
              style: TextStyle(color: theme.colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, List<ChecklistItem>> _groupByCategory(List<ChecklistItem> items) {
    final Map<String, List<ChecklistItem>> grouped = {};
    for (final item in items) {
      final key = (item.category.isEmpty) ? 'Uncategorized' : item.category;
      grouped.putIfAbsent(key, () => []).add(item);
    }
    return grouped;
  }
}