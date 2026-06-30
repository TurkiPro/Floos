// Basic smoke test for the Floos home screen.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floos/app.dart';
import 'package:floos/data/database.dart';

void main() {
  testWidgets('Home screen shows app bar and empty state',
      (WidgetTester tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(FloosApp(db: db));
    await tester.pumpAndSettle();

    expect(find.text('فلوس'), findsOneWidget);
    expect(find.text('لا توجد حركات بعد'), findsOneWidget);

    // Unmount explicitly so the HomeScreen's StreamBuilder cancels its drift
    // .watch() subscription now, then pump with an explicit (zero) duration:
    // cancelling schedules a zero-duration cleanup Timer
    // (StreamQueryStore.markAsClosed), and only a pump that elapses fake time
    // — pump() with no argument does not — actually fires it. Otherwise
    // flutter_test's pending-timer check fails the test even though nothing
    // is actually wrong.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
