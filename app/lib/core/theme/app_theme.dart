import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Theme with script-aware text styles.
///
/// Fonts: Noto Serif family covers Devanagari, Malayalam, Kannada, Telugu,
/// Bengali, Gujarati, Gurmukhi, Odia and Tamil, and Noto Serif (Latin) has the
/// full IAST diacritic set. We rely on google_fonts to fetch the script font
/// on first use and cache it; for fully-offline first launch, bundle the .ttf
/// files under assets/fonts and register them in pubspec.
class AppTheme {
  AppTheme._();

  static const saffron = Color(0xFFC96A1B);
  static const deepMaroon = Color(0xFF5E1A1A);
  static const sepiaBg = Color(0xFFF4ECD8);
  static const sepiaInk = Color(0xFF4A3B2A);

  /// Set to false in tests / fully-offline builds to skip runtime font fetches.
  static bool useGoogleFonts = true;

  static ThemeData light({bool sepia = false}) {
    final scheme = ColorScheme.fromSeed(seedColor: saffron, brightness: Brightness.light, surface: sepia ? sepiaBg : null);
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: sepia ? sepiaBg : scheme.surface,
      textTheme: _textTheme(scheme.brightness, ink: sepia ? sepiaInk : null),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(seedColor: saffron, brightness: Brightness.dark);
    return _base(scheme).copyWith(textTheme: _textTheme(Brightness.dark));
  }

  static ThemeData _base(ColorScheme scheme) => ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0, scrolledUnderElevation: 1),
        chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
        navigationBarTheme: const NavigationBarThemeData(labelBehavior: NavigationDestinationLabelBehavior.alwaysShow),
      );

  static TextTheme _textTheme(Brightness b, {Color? ink}) {
    final base = b == Brightness.dark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;
    final t = useGoogleFonts ? GoogleFonts.notoSerifTextTheme(base) : base;
    return ink == null ? t : t.apply(bodyColor: ink, displayColor: ink);
  }

  /// Font family best suited to render [script] (ISO 15924).
  static TextStyle scriptStyle(String script, {double fontSize = 20, FontWeight? weight, double? height, Color? color}) {
    final s = TextStyle(fontSize: fontSize, fontWeight: weight, height: height ?? 1.7, color: color);
    if (!useGoogleFonts) return s;
    try {
      return switch (script) {
        'Deva' => GoogleFonts.notoSerifDevanagari(textStyle: s),
        'Mlym' => GoogleFonts.notoSerifMalayalam(textStyle: s),
        'Knda' => GoogleFonts.notoSerifKannada(textStyle: s),
        'Telu' => GoogleFonts.notoSerifTelugu(textStyle: s),
        'Beng' => GoogleFonts.notoSerifBengali(textStyle: s),
        'Gujr' => GoogleFonts.notoSerifGujarati(textStyle: s),
        'Guru' => GoogleFonts.notoSerifGurmukhi(textStyle: s),
        'Orya' => GoogleFonts.notoSerifOriya(textStyle: s),
        'Taml' => GoogleFonts.notoSerifTamil(textStyle: s),
        _ => GoogleFonts.notoSerif(textStyle: s),
      };
    } catch (_) {
      return s;
    }
  }
}
