import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'data/database.dart';
import 'ui/home_screen.dart';
import 'ui/theme/tokens.dart';

class FloosApp extends StatelessWidget {
  final AppDatabase db;
  const FloosApp({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    // The database is provided to the whole tree; screens read it with
    // context.read<AppDatabase>(). It is created once in main() and lives for
    // the life of the app.
    return Provider<AppDatabase>.value(
      value: db,
      child: MaterialApp(
        title: 'فلوس',
        debugShowCheckedModeBanner: false,
        // Arabic locale + the Global delegates make the whole app render RTL
        // automatically, including date pickers and dialogs.
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const HomeScreen(),
      ),
    );
  }
}

ThemeData _buildTheme(Brightness brightness) {
  final isLight = brightness == Brightness.light;
  return ThemeData(
    brightness: brightness,
    useMaterial3: true,
    colorScheme: isLight ? AppColorSchemes.light() : AppColorSchemes.dark(),
    scaffoldBackgroundColor:
        isLight ? AppColors.pageLight : AppColors.pageDark,
    // Card/tile/button radii set once globally so individual screens don't
    // repeat AppRadii values per widget.
    extensions: const [categoryTileColors],
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
