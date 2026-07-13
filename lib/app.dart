import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'app_settings.dart';
import 'data/database.dart';
import 'services/app_lock_service.dart';
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
            home: const _LockGate(child: HomeScreen()),
          ),
        ),
      ),
    );
  }
}

/// Holds the app behind Face ID / fingerprint / device passcode when the lock
/// is enabled. Re-locks whenever the app is backgrounded, so returning to it
/// requires authenticating again.
class _LockGate extends StatefulWidget {
  final Widget child;
  const _LockGate({required this.child});

  @override
  State<_LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<_LockGate> with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _authenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAuthenticate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (context.read<AppSettings>().appLockEnabled && mounted) {
        setState(() => _unlocked = false);
      }
    } else if (state == AppLifecycleState.resumed) {
      _maybeAuthenticate();
    }
  }

  Future<void> _maybeAuthenticate() async {
    if (!mounted || _authenticating || _unlocked) return;
    if (!context.read<AppSettings>().appLockEnabled) return;
    _authenticating = true;
    final ok = await AppLockService.authenticate();
    _authenticating = false;
    if (mounted && ok) setState(() => _unlocked = true);
  }

  @override
  Widget build(BuildContext context) {
    final locked = context.watch<AppSettings>().appLockEnabled && !_unlocked;
    if (!locked) return widget.child;

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 56, color: scheme.primary),
            const SizedBox(height: AppSpacing.lg),
            const Text('فلوس مقفل',
                style: TextStyle(
                    fontSize: AppTextSizes.row, fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'استخدم بصمتك أو رمز جهازك للفتح.',
              style: TextStyle(
                  fontSize: AppTextSizes.label, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: _maybeAuthenticate,
              icon: const Icon(Icons.lock_open),
              label: const Text('فتح'),
            ),
          ],
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
    scaffoldBackgroundColor: isLight ? AppColors.pageLight : AppColors.pageDark,
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
          (states) =>
              states.contains(WidgetState.selected) ? accent.primary : null,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? accent.onPrimary : null,
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
