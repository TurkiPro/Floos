import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:floos/app.dart';
import 'package:floos/app_settings.dart';
import 'package:floos/data/database.dart';

/// The lock gate must cover the whole app, not just Home. Before plan 017 the
/// gate wrapped only the home route, so any pushed screen — and even Home
/// itself on resume — rendered above/underneath the lock and bypassed it.
void main() {
  testWidgets('lock on: the unlock screen covers the app and blocks Home',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    SharedPreferences.setMockInitialValues({'appLockEnabled': true});
    final settings = AppSettings(await SharedPreferences.getInstance());

    await tester.pumpWidget(FloosApp(db: db, settings: settings));
    await tester.pumpAndSettle();

    // local_auth throws MissingPluginException in tests, so authenticate()
    // returns false and the app stays locked.
    expect(find.text('فلوس مقفل'), findsOneWidget);

    // The add-transaction bar must not be operable behind the lock.
    await tester.tap(find.text('إضافة حركة'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('حفظ'), findsNothing,
        reason: 'no sheet opens behind lock');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('lock off: home renders and is interactive', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());

    await tester.pumpWidget(FloosApp(db: db, settings: settings));
    await tester.pumpAndSettle();

    expect(find.text('فلوس'), findsOneWidget);
    expect(find.text('لا توجد مصاريف هذا الشهر'), findsOneWidget);
    expect(find.text('فلوس مقفل'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
