import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../models/dashboard_card_config.dart';

/// Service to manage dashboard card configuration (order, visibility)
class DashboardConfigService extends ChangeNotifier {
  List<DashboardCardConfig> _cards = [];
  late SharedPreferences _prefs;

  static const String _cardsOrderKey = 'dashboard_cards_order';
  static const String _cardsVisibilityKey = 'dashboard_cards_visibility';

  List<DashboardCardConfig> get cards => _cards;

  /// Initialize the service
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    // Initialize with defaults first
    _cards = DashboardCards.getAllCards();
    // Then load from storage if available
    await _loadCards();
  }

  /// Load cards from storage or use defaults
  Future<void> _loadCards() async {
    try {
      final savedOrder = _prefs.getStringList(_cardsOrderKey);
      final savedVisibility = _prefs.getString(_cardsVisibilityKey);

      if (savedOrder != null && savedOrder.isNotEmpty) {
        // Load from saved preferences
        _cards = DashboardCards.getAllCards();

        // Apply saved order
        final Map<String, int> orderMap = {
          for (int i = 0; i < savedOrder.length; i++) savedOrder[i]: i
        };

        _cards.sort((a, b) => (orderMap[a.id] ?? 999).compareTo(orderMap[b.id] ?? 999));

        // Apply saved visibility
        if (savedVisibility != null) {
          final visibilityMap = jsonDecode(savedVisibility) as Map<String, dynamic>;
          for (var card in _cards) {
            if (visibilityMap.containsKey(card.id)) {
              card.isVisible = visibilityMap[card.id] as bool;
            }
          }
        }
      } else {
        // Use default cards
        _cards = DashboardCards.getAllCards();
      }
    } catch (e) {
      debugPrint('Error loading dashboard cards: $e');
      _cards = DashboardCards.getAllCards();
    }
  }

  /// Save current card configuration
  Future<void> saveCardConfiguration() async {
    try {
      // Save order
      final cardIds = _cards.map((card) => card.id).toList();
      await _prefs.setStringList(_cardsOrderKey, cardIds);

      // Save visibility
      final visibilityMap = {
        for (var card in _cards) card.id: card.isVisible
      };
      await _prefs.setString(_cardsVisibilityKey, jsonEncode(visibilityMap));

      notifyListeners();
    } catch (e) {
      debugPrint('Error saving dashboard cards: $e');
    }
  }

  /// Reorder cards
  void reorderCard(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final card = _cards.removeAt(oldIndex);
    _cards.insert(newIndex, card);
    saveCardConfiguration();
  }

  /// Toggle card visibility
  void toggleCardVisibility(String cardId) {
    final cardIndex = _cards.indexWhere((card) => card.id == cardId);
    if (cardIndex != -1) {
      _cards[cardIndex].isVisible = !_cards[cardIndex].isVisible;
      saveCardConfiguration();
    }
  }

  /// Show card
  void showCard(String cardId) {
    final cardIndex = _cards.indexWhere((card) => card.id == cardId);
    if (cardIndex != -1) {
      _cards[cardIndex].isVisible = true;
      saveCardConfiguration();
    }
  }

  /// Hide card
  void hideCard(String cardId) {
    final cardIndex = _cards.indexWhere((card) => card.id == cardId);
    if (cardIndex != -1) {
      _cards[cardIndex].isVisible = false;
      saveCardConfiguration();
    }
  }

  /// Get visible cards only
  List<DashboardCardConfig> getVisibleCards() {
    return _cards.where((card) => card.isVisible).toList();
  }

  /// Reset to defaults
  Future<void> resetToDefaults() async {
    _cards = DashboardCards.getAllCards();
    await _prefs.remove(_cardsOrderKey);
    await _prefs.remove(_cardsVisibilityKey);
    notifyListeners();
  }

  /// Get card by ID
  DashboardCardConfig? getCard(String cardId) {
    try {
      return _cards.firstWhere((card) => card.id == cardId);
    } catch (e) {
      return null;
    }
  }
}
