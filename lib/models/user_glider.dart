// File: lib/models/user_glider.dart

/// Model for a user's own glider (stored in users/{uid}/gliders)
class UserGlider {
  final String? id; // Firestore document ID
  final String brand;
  final String type;
  final String gliderClass; // EN-A, EN-B, etc.
  final bool tandem;
  final bool light;
  final String? colorMain; // Main color chosen by user

  UserGlider({
    this.id,
    required this.brand,
    required this.type,
    required this.gliderClass,
    this.tandem = false,
    this.light = false,
    this.colorMain,
  });

  /// Display name for dropdowns: "Type (Brand)"
  String get displayName => '$type ($brand)';

  factory UserGlider.fromFirestore(Map<String, dynamic> data, String docId) {
    return UserGlider(
      id: docId,
      brand: data['brand'] ?? '',
      type: data['type'] ?? '',
      gliderClass: data['class'] ?? '',
      tandem: data['tandem'] ?? false,
      light: data['light'] ?? false,
      colorMain: data['colorMain'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'brand': brand,
      'type': type,
      'class': gliderClass,
      'tandem': tandem,
      'light': light,
      'colorMain': colorMain,
    };
  }

  factory UserGlider.fromCache(Map<String, dynamic> data) {
    return UserGlider(
      id: data['id'],
      brand: data['brand'] ?? '',
      type: data['type'] ?? '',
      gliderClass: data['class'] ?? '',
      tandem: data['tandem'] ?? false,
      light: data['light'] ?? false,
      colorMain: data['colorMain'],
    );
  }

  Map<String, dynamic> toCache() {
    return {
      'id': id,
      'brand': brand,
      'type': type,
      'class': gliderClass,
      'tandem': tandem,
      'light': light,
      'colorMain': colorMain,
    };
  }

  /// Create a copy with selected fields updated
  UserGlider copyWith({
    String? id,
    String? brand,
    String? type,
    String? gliderClass,
    bool? tandem,
    bool? light,
    String? colorMain,
  }) {
    return UserGlider(
      id: id ?? this.id,
      brand: brand ?? this.brand,
      type: type ?? this.type,
      gliderClass: gliderClass ?? this.gliderClass,
      tandem: tandem ?? this.tandem,
      light: light ?? this.light,
      colorMain: colorMain ?? this.colorMain,
    );
  }
}
