import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/checklist_item.dart';
import '../services/global_data_service.dart';
import '../services/user_data_service.dart';
import '../services/app_config_service.dart';

class ChecklistsScreen extends StatelessWidget {
  const ChecklistsScreen({super.key});

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

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Iterate through fixed category order
          for (final categoryId in GlobalDataService.categoryOrder)
            if (itemsByCategory.containsKey(categoryId))
              _buildCategoryCard(
                context,
                categoryId,
                itemsByCategory[categoryId]!,
                lang,
              ),
        ],
      ),
    );
  }

  /// Build a card for a single category with its checklist items.
  Widget _buildCategoryCard(
    BuildContext context,
    String categoryId,
    List<ChecklistItem> items,
    String languageCode,
  ) {
    final theme = Theme.of(context);
    final global = context.read<GlobalDataService>();
    final user = context.read<UserDataService>();

    // Get translated category title
    final categoryTitle = global.getCategoryTitle(categoryId, languageCode);
    final completedCount = items.where((item) => user.isChecklistItemCompleted(item.id)).length;
    final progressText = '$completedCount/${items.length}';

    return Card(
      color: theme.cardColor,
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        initiallyExpanded: false,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                categoryTitle,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Text(progressText, style: theme.textTheme.bodyMedium),
          ],
        ),
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: CheckboxListTile(
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(languageCode == 'de' ? item.title_de : item.title_en, style: theme.textTheme.titleSmall)),
                    IconButton(
                      icon: const Icon(Icons.info_outline),
                      color: theme.colorScheme.primary,
                      onPressed: () {
                        final desc = languageCode == 'de' ? item.description_de : item.description_en;
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: theme.cardColor,
                            title: Text(languageCode == 'de' ? item.title_de : item.title_en),
                            content: Text(
                              (desc == null || desc.isEmpty) ? 'No description' : desc,
                              style: theme.textTheme.bodyMedium,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
                value: user.isChecklistItemCompleted(item.id),
                activeColor: theme.primaryColor,
                onChanged: (value) {
                  if (value != null) {
                    context.read<UserDataService>().toggleProgress(item.id, value);
                  }
                },
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
