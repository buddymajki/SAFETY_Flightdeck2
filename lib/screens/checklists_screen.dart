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
  List<String> _categoryIds = [];
  int _selectedTabIndex = 0;
  SharedPreferences? _prefs;
  bool _isDisposed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isDisposed) return; // Skip if disposed
    
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
      _tabController.removeListener(_onTabChanged); // Remove listener before disposing
      _tabController.dispose();
      // Start on the category the pilot last had open instead of snapping back
      // to the first one every time the category list is rebuilt.
      _tabController = TabController(
        length: _categoryIds.length,
        initialIndex: _categoryIds.isEmpty
            ? 0
            : _selectedTabIndex.clamp(0, _categoryIds.length - 1),
        vsync: this,
      );
      _tabController.addListener(_onTabChanged);
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 0, vsync: this);
    _loadTabIndex();
  }

  /// Restores the last opened category. Runs once, and only moves the tab bar
  /// if the pilot has not already picked a category in the meantime.
  Future<void> _loadTabIndex() async {
    final prefs = await SharedPreferences.getInstance();
    if (_isDisposed) return;
    _prefs = prefs;

    final savedIndex = prefs.getInt('checklist_tab_index') ?? 0;
    if (savedIndex == _selectedTabIndex) return; // already there (or user moved)

    _selectedTabIndex = savedIndex;
    if (!mounted || _tabController.length == 0) return;
    _tabController.animateTo(
      savedIndex.clamp(0, _tabController.length - 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _saveTabIndex(int index) async {
    await _prefs?.setInt('checklist_tab_index', index);
  }

  /// Keeps [_selectedTabIndex] in step with the controller for *every* way the
  /// tab can change: a tap (during which indexIsChanging is true), a swipe of
  /// the content, and the chevron buttons.
  void _onTabChanged() {
    final index = _tabController.index;
    if (index == _selectedTabIndex) return;

    if (mounted) {
      setState(() => _selectedTabIndex = index);
    } else {
      _selectedTabIndex = index;
    }
    _saveTabIndex(index);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
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

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          // Category tab bar. The chevrons sit BESIDE the bar, not on top of
          // it: as overlays they covered the first and last visible tab and
          // swallowed taps meant for those tabs.
          Row(
            children: [
              _buildTabChevron(
                theme,
                icon: Icons.chevron_left,
                tooltip: 'Previous category',
                enabled: _selectedTabIndex > 0,
                onTap: _goToPreviousTab,
              ),
              Expanded(
                // TabBar handles its own horizontal scrolling (isScrollable: true).
                // It must NOT be wrapped in another horizontal scrollable, otherwise
                // the nested scroll view swallows tab taps on iOS (only swipe works).
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  indicatorSize: TabBarIndicatorSize.label,
                  tabAlignment: TabAlignment.start,
                  padding: EdgeInsets.zero,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                  labelColor: theme.colorScheme.onSurface,
                  unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  labelStyle: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                  unselectedLabelStyle: theme.textTheme.labelMedium,
                  indicatorColor: theme.colorScheme.primary,
                  tabs: [
                    for (final categoryId in categoryIds)
                      _buildTab(context, categoryId, itemsByCategory[categoryId]!, user, lang),
                  ],
                ),
              ),
              _buildTabChevron(
                theme,
                icon: Icons.chevron_right,
                tooltip: 'Next category',
                enabled: _selectedTabIndex < categoryIds.length - 1,
                onTap: _goToNextTab,
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

  /// A step-one-category button. Always occupies its slot so the tab bar does
  /// not jump around when the first or last category becomes selected; it just
  /// fades out when there is nothing to step to.
  Widget _buildTabChevron(
    ThemeData theme, {
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.25,
        child: Material(
          color: theme.colorScheme.primary.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: enabled ? onTap : null,
            child: Tooltip(
              message: tooltip,
              child: SizedBox(
                width: 32,
                height: 32,
                child: Icon(icon, size: 18, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Move selection to the previous tab. The scrollable TabBar
  /// automatically scrolls the newly selected tab into view.
  void _goToPreviousTab() {
    if (_tabController.index > 0) {
      _tabController.animateTo(_tabController.index - 1);
    }
  }

  /// Move selection to the next tab. The scrollable TabBar
  /// automatically scrolls the newly selected tab into view.
  void _goToNextTab() {
    if (_tabController.index < _tabController.length - 1) {
      _tabController.animateTo(_tabController.index + 1);
    }
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
                    color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
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
    final title = item.getTitle(languageCode);
    final description = item.getDescription(languageCode);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCompleted
              ? theme.colorScheme.primary.withValues(alpha: 0.3)
              : theme.dividerColor.withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
                              ? theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6)
                              : null,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (description != null && description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
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
    final title = item.getTitle(languageCode);
    final description = item.getDescription(languageCode);

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
