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
          Container(
            color: _tabBarBackground,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
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
                  // The selected tab is drawn as a filled pill by _buildTab, so the
                  // TabBar's own indicator and divider are switched off.
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    padding: EdgeInsets.zero,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 3),
                    indicator: const BoxDecoration(),
                    dividerColor: Colors.transparent,
                    overlayColor: WidgetStateProperty.all(Colors.transparent),
                    tabs: [
                      for (int i = 0; i < categoryIds.length; i++)
                        _buildTab(context, categoryIds[i], i == _selectedTabIndex, lang),
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
          color: theme.colorScheme.primary.withValues(alpha: 0.55),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: Tooltip(
              message: tooltip,
              child: SizedBox(
                width: 30,
                height: 30,
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


  /// Background of the category tab strip, a shade darker than the page.
  static const Color _tabBarBackground = Color(0xFF2A3042);

  /// A single category tab, drawn as a pill: filled with the primary colour
  /// when selected, a faint outline-less chip otherwise.
  Widget _buildTab(
    BuildContext context,
    String categoryId,
    bool isSelected,
    String languageCode,
  ) {
    final theme = Theme.of(context);
    final global = context.read<GlobalDataService>();
    final title = global.getCategoryTitle(categoryId, languageCode);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? theme.colorScheme.primary : Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          color: theme.colorScheme.onSurface,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        ),
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
          // Header: category title, "done / total" and a progress bar
          Container(
            width: double.infinity,
            color: theme.scaffoldBackgroundColor,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        categoryTitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '$completedCount / $total',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : completedCount / total,
                    minHeight: 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    color: theme.colorScheme.primary,
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
                  if (index < items.length - 1) const SizedBox(height: 10),
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

    final onSurface = theme.colorScheme.onSurface;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
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
            padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Rounded-square checkbox with animation
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: theme.colorScheme.primary, width: 2),
                      color: isCompleted ? theme.colorScheme.primary : Colors.transparent,
                    ),
                    width: 26,
                    height: 26,
                    child: isCompleted
                        ? Icon(
                            Icons.check,
                            size: 18,
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
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: isCompleted ? onSurface.withValues(alpha: 0.8) : onSurface,
                        ),
                      ),
                      if (description != null && description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: onSurface.withValues(alpha: 0.62),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                // Info button
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  iconSize: 22,
                  color: onSurface.withValues(alpha: 0.62),
                  onPressed: () {
                    _showItemDetails(context, item, languageCode);
                  },
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
