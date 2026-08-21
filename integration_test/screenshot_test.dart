import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:floos/app.dart';
import 'package:floos/app_settings.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/dev_seed.dart';
import 'package:floos/services/alerts_coordinator.dart';
import 'package:floos/services/app_lock_service.dart';
import 'package:floos/services/notification_service.dart';

/// Drives the real app on a real device image to capture the App Store / Play
/// screenshots, at whatever native resolution the device reports — which is why
/// this runs on an emulator/simulator rather than a resized desktop window
/// (Apple rejects screenshots that aren't exactly the expected pixel size).
///
/// It doubles as the first real-device smoke test of the native plugins:
/// flutter_local_notifications, local_auth and the icon badge only have real
/// implementations on mobile, so on the Windows dev machine they all no-op and
/// a crash-on-init would never surface. Here it would fail the run.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture store screenshots', (tester) async {
    // Android renders Flutter into a SurfaceView that can't be read back
    // directly; this swaps it for an offscreen image the harness can capture.
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
    }

    // A seeded in-memory database, so the screenshots show a plausible six
    // months of history instead of an empty app — and the user's real device
    // data (if any) is never touched.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await seedDummyData(db);

    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());
    // Show the weekly-budget status card on home, so it can be captured and
    // tapped through to the weekly-performance screen.
    settings.setShowWeeklyStatusOnHome(true);

    // Exercise the plugin init paths the same way main() does. These are the
    // calls that can throw MissingPluginException or fail a timezone lookup on
    // a real device; if any of them blow up, this test fails loudly.
    await NotificationService.init();
    await AppLockService.isAvailable();
    await refreshAlerts(db, settings);

    await tester.pumpWidget(FloosApp(db: db, settings: settings));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Capture is only supported on the mobile targets. Skipping it elsewhere
    // lets the whole navigation path be validated on the desktop dev machine,
    // instead of only ever finding a bad finder inside a 10-minute CI run.
    Future<void> shoot(String name) async {
      await tester.pumpAndSettle();
      if (Platform.isAndroid || Platform.isIOS) {
        await binding.takeScreenshot(name);
      } else {
        debugPrint('SHOOT (skipped on this platform): $name');
      }
    }

    // 1. Home — the salary-cycle header, balance + savings, the cycle split,
    //    the weekly-budget status, and the day-grouped expense list.
    await shoot('01_home');

    // 2. Statistics — committed vs. discretionary, the weekly budget, and the
    //    per-cycle spending trend.
    await tester.tap(find.byIcon(Icons.insights_outlined).first);
    await tester.pumpAndSettle();
    await shoot('02_statistics');
    await _back(tester);

    // 3. Budgets — the advisor's one-tap suggestions, learned from your spending.
    await tester.tap(find.byIcon(Icons.settings_outlined).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('الميزانيات'));
    await tester.pumpAndSettle();
    await shoot('03_budgets');
    await _back(tester);
    await _back(tester);

    // 4. Weekly performance — each week judged against its own frozen budget.
    await tester.tap(find.text('ميزانية الأسبوع'));
    await tester.pumpAndSettle();
    await shoot('04_weekly');
    await _back(tester);

    // 5. Savings goals — progress and the projected finish date.
    await tester.tap(find.text('الأهداف'));
    await tester.pumpAndSettle();
    await shoot('05_savings');

    // 6. Savings behaviour — rate vs. norm, streak, best cycle, per-cycle trend.
    await tester.tap(find.byIcon(Icons.insights_outlined).first);
    await tester.pumpAndSettle();
    await shoot('06_savings_behavior');
    await _back(tester);
    await _back(tester);
  });
}

Future<void> _back(WidgetTester tester) async {
  final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
  nav.pop();
  await tester.pumpAndSettle();
}
