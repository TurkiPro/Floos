import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'app_settings.dart';
import 'data/database.dart';
import 'ui/home_screen.dart';
import 'ui/theme/tokens.dart';

class FloosApp extends StatelessWidget {
  final AppDatabase db;
  final AppSettings settings;
  const FloosApp({super.key, required this.db, required this.settings});

  @override
  Widget build(BuildContext context) {
    // The database and settings are provided to the whole tree; screens read
    // them with context.read/watch. Both are created once in main() and live
    // for the life of the app.
    return Provider<AppDatabase>.value(
      value: db,
      child: ChangeNotifierProvider<AppSettings>.value(
        value: settings,
        // Rebuilds the MaterialApp when theme mode/accent change so the whole
        // tree re-themes instantly.
        child: Consumer<AppSettings>(
          builder: (context, s, _) => MaterialApp(
            title: 'فلوس',
            debugShowCheckedModeBanner: false,
            // Arabic locale + the Global delegates make the whole app render
            // RTL automatically, including date pickers and dialogs.
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: _buildTheme(Brightness.light, s.accent),
            darkTheme: _buildTheme(Brightness.dark, s.accent),
            themeMode: s.themeMode,
            home: const HomeScreen(),
          ),
        ),
      ),
    );
  }
}

ThemeData _buildTheme(Brightness brightness, AppAccent accent) {
  final isLight = brightness == Brightness.light;
  return ThemeData(
    brightness: brightness,
    useMaterial3: true,
    colorScheme:
        isLight ? AppColorSchemes.light(accent) : AppColorSchemes.dark(accent),
    scaffoldBackgroundColor:
        isLight ? AppColors.pageLight : AppColors.pageDark,
    // Card/tile/button radii set once globally so individual screens don't
    // repeat AppRadii values per widget.
    extensions: [categoryTileColors, AccentPalette(progress: accent.progress)],
    textTheme: _appTextTheme(brightness),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.button),
        ),
      ),
    ),
    // Selected segments default to Material's secondaryContainer (a teal we
    // never set), so force them onto the accent to stay on-brand everywhere
    // a type/theme toggle appears.
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent.primary
              : null,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent.onPrimary
              : null,
        ),
      ),
    ),
  );
}

/// IBM Plex Sans Arabic as the primary font, Tajawal as fallback.
TextTheme _appTextTheme(Brightness brightness) {
  final base = ThemeData(brightness: brightness).textTheme;
  final theme = GoogleFonts.ibmPlexSansArabicTextTheme(base);
  final fallback = GoogleFonts.tajawal().fontFamily!;
  TextStyle? withFallback(TextStyle? s) =>
      s?.copyWith(fontFamilyFallback: [fallback]);
  return theme.copyWith(
    displayLarge: withFallback(theme.displayLarge),
    displayMedium: withFallback(theme.displayMedium),
    displaySmall: withFallback(theme.displaySmall),
    headlineLarge: withFallback(theme.headlineLarge),
    headlineMedium: withFallback(theme.headlineMedium),
    headlineSmall: withFallback(theme.headlineSmall),
    titleLarge: withFallback(theme.titleLarge),
    titleMedium: withFallback(theme.titleMedium),
    titleSmall: withFallback(theme.titleSmall),
    bodyLarge: withFallback(theme.bodyLarge),
    bodyMedium: withFallback(theme.bodyMedium),
    bodySmall: withFallback(theme.bodySmall),
    labelLarge: withFallback(theme.labelLarge),
    labelMedium: withFallback(theme.labelMedium),
    labelSmall: withFallback(theme.labelSmall),
  );
}
