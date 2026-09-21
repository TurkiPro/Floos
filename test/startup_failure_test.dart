import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:floos/app.dart';
import 'package:floos/app_settings.dart';
import 'package:floos/data/database.dart';

/// Startup chores (recurrence catch-up, notification init, alert refresh) used
/// to run unguarded in main(). An exception in any of them escaped before
/// runApp, so the app never rendered at all — on a phone that is a blank white
/// screen with nothing to report.
///
/// The app must now start regardless, and say what went wrong.
void main() {
  late AppDatabase db;
  late AppSettings settings;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
  });

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  testWidgets('a clean start shows no banner', (tester) async {
    await tester.pumpWidget(FloosApp(db: db, settings: settings));
    await tester.pumpAndSettle();

    expect(find.text('فلوس'), findsOneWidget);
    expect(find.textContaining('تعذّر إكمال'), findsNothing);

    await teardownTree(tester);
  });

  testWidgets('a failed startup still renders the app, and says why',
      (tester) async {
    await tester.pumpWidget(FloosApp(
      db: db,
      settings: settings,
      startupFailures: const [
        'تحديث العمليات المتكررة: SqliteException(1): no such column',
      ],
    ));
    await tester.pumpAndSettle();

    // The app is usable underneath — this is the whole point.
    expect(find.text('فلوس'), findsOneWidget);

    // And the reason is on screen, verbatim, so it can be reported.
    expect(find.textContaining('تعذّر إكمال'), findsOneWidget);
    expect(find.textContaining('no such column'), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('the banner can be dismissed', (tester) async {
    await tester.pumpWidget(FloosApp(
      db: db,
      settings: settings,
      startupFailures: const ['تهيئة التنبيهات: boom'],
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('تعذّر إكمال'), findsOneWidget);

    await tester.tap(find.text('إخفاء'));
    await tester.pumpAndSettle();
    expect(find.textContaining('تعذّر إكمال'), findsNothing);
    expect(find.text('فلوس'), findsOneWidget);

    await teardownTree(tester);
  });
}
