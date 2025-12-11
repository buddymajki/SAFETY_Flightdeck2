// lib/config/app_theme.dart

import 'package:flutter/material.dart';

class AppTheme {
  // Custom color palette
  static const Color contentBackground = Color.fromARGB(255, 49, 55, 74);
  static const Color cardBackground = Color.fromARGB(255, 60, 68, 88);
  static const Color primaryColor = Color(0xFF805ad5);
  static const Color navBarColor = Color.fromARGB(255, 26, 32, 44);
  static const Color textColor = Color.fromARGB(255, 245, 245, 245); // Off-white

  /// Returns a fully configured Dark ThemeData with custom color palette.
  static ThemeData dark() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: contentBackground,
      cardColor: cardBackground,
      primaryColor: primaryColor,
      
      // Ideális esetben a TextTheme-nek elég lenne a colorScheme-ből örökölnie, 
      // de a biztonság kedvéért maradhat.

      colorScheme: ColorScheme.dark(
        primary: primaryColor,      // Lila gombok háttere
        surface: cardBackground,    // Kártyák, sheet-ek háttere
        background: contentBackground, // Scaffold háttere
        
        // --- KRITIKUS JAVÍTÁS ---
        // A 'primary' színen lévő szöveg/ikon színe (pl. gombokon)
        onPrimary: Colors.white, 
        // A 'surface' (kártyák) és 'background' (Scaffold) tetején lévő szöveg színe
        onSurface: textColor, 
        onBackground: textColor,
        // -------------------------
      ),
      
      // --- JAVÍTÁS AZ ELEVATED BUTTON STÍLUSHOZ ---
      // A gomb alapértelmezett stílusa is megkapja az onPrimary színt
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          // Automatikusan az onPrimary-ra állítja a szöveg és ikon színt
          foregroundColor: Colors.white, 
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      // ---------------------------------------------

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: navBarColor,
        indicatorColor: primaryColor,
        labelTextStyle: MaterialStateProperty.all(const TextStyle(color: textColor)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: navBarColor,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: navBarColor,
        elevation: 0,
        titleTextStyle: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.bold),
        iconTheme: IconThemeData(color: textColor),
      ),
    );
  }
}