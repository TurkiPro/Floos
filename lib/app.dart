import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
            // The gate must wrap the Navigator (via builder:), not the home
            // route — otherwise every pushed screen (Settings, Statistics, a
            // sheet) renders above the lock and bypasses it.
            builder: (context, child) =>
                _LockGate(child: child ?? const SizedBox.shrink()),
            home: const HomeScreen(),
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
  // Covers the screen the instant the app stops being frontmost, so the
  // OS app-switcher snapshot (taken on `inactive`, before `paused`) and the
  // transient inactive overlays (Control Centre, an incoming call) can't
  // capture the balance. Only engaged when the lock is on.
  bool _obscured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Deliberately does NOT auto-authenticate on launch. A locked app shows the
    // unlock screen with a button; the user taps it to choose Face ID or their
    // device passcode, rather than Face ID being forced in their face on every
    // open. See _UnlockScreen.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lockOn = context.read<AppSettings>().appLockEnabled;
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (lockOn && mounted) {
          // Drop the keyboard so it can't float above the cover.
          FocusManager.instance.primaryFocus?.unfocus();
          setState(() {
            _obscured = true;
            _unlocked = false;
          });
        }
        break;
      case AppLifecycleState.resumed:
        // Lift the privacy cover, but don't auto-authenticate — the unlock
        // screen waits for the user to tap فتح.
        if (mounted) setState(() => _obscured = false);
        break;
      case AppLifecycleState.detached:
        break;
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
    final lockOn = context.watch<AppSettings>().appLockEnabled;
    // `_obscured` (backgrounded) shows the data-free cover; otherwise a locked
    // app shows the interactive unlock screen. Either way the covering widget
    // stacks OVER the child so the whole Navigator stays mounted underneath —
    // locking must never destroy navigation state.
    final covering = lockOn && (_obscured || !_unlocked);

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (covering)
          _obscured
              ? const _ObscureCover()
              : _UnlockScreen(onUnlock: _maybeAuthenticate),
      ],
    );
  }
}

/// The opaque, data-free cover shown while the app is backgrounded/inactive —
/// this is what the OS app-switcher snapshots.
class _ObscureCover extends StatelessWidget {
  const _ObscureCover();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Icon(Icons.lock_outline, size: 56, color: scheme.primary),
      ),
    );
  }
}

/// The interactive lock screen shown when the app is open but not yet unlocked.
class _UnlockScreen extends StatelessWidget {
  final VoidCallback onUnlock;
  const _UnlockScreen({required this.onUnlock});

  @override
  Widget build(BuildContext context) {
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
              onPressed: onUnlock,
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

/// IBM Plex Sans Arabic as the primary font, Tajawal as fallback. Both are
/// bundled assets (see pubspec `fonts:`) — the app must never fetch fonts, or
/// anything, at runtime. `apply` sets the family + fallback on every slot,
/// exactly what the previous per-slot loop did.
TextTheme _appTextTheme(Brightness brightness) {
  final base = ThemeData(brightness: brightness).textTheme;
  return base.apply(
    fontFamily: 'IBM Plex Sans Arabic',
    fontFamilyFallback: const ['Tajawal'],
  );
}
