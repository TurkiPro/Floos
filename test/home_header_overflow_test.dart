import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:floos/app.dart';
import 'package:floos/app_settings.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';

/// The home header lays the wordmark out beside two circular buttons. Its
/// subtitle is the salary cycle plus the payday countdown, and a cycle that
/// straddles two months renders as a full date range — long enough that on a
/// real phone it overflowed the row and pushed the wallet glyph off the screen
/// edge.
///
/// The assertion here is **geometry**, not the absence of overflow errors.
/// Widget tests render with a fixed-width test font, so Arabic strings are
/// nothing like their real width and unrelated cards further down the screen
/// report overflows that do not happen on a device. Measuring where the header's
/// own widgets land is font-independent: if the row overflows, they leave the
/// screen; if the wordmark column is properly constrained, they cannot.
void main() {
  Future<void> pumpHomeAt(WidgetTester tester, Size logicalSize) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());

    // A salary on the 25th never lines up with a calendar month, so the cycle
    // always renders as a date range rather than a single month name — the
    // long-label case that triggered the bug.
    final categories = await db.categoryDao.getAll();
    final incomeCategory =
        categories.firstWhere((c) => c.type == TxnType.income);
    await db.recurrenceDao.add(
      title: 'راتب',
      amount: 12000,
      categoryId: incomeCategory.id,
      type: TxnType.income,
      frequency: Frequency.monthly,
      startDate: DateTime(2026, 1, 25),
    );

    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = logicalSize * 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FloosApp(db: db, settings: settings));
    await tester.pumpAndSettle();
  }

  /// Unmounts, lets drift's zero-duration stream cleanup timer fire (as
  /// widget_test.dart does), and discards overflow reports from widgets other
  /// than the header — see the note above on test-font metrics.
  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    while (tester.takeException() != null) {}
  }

  for (final size in const [
    Size(320, 640), // smallest width still worth supporting
    Size(375, 812), // iPhone SE / 13 mini class
    Size(390, 844), // iPhone 14/15 class — the reported case
  ]) {
    final width = size.width.toInt();
    testWidgets('the wallet glyph stays on screen at ${width}pt wide',
        (tester) async {
      await pumpHomeAt(tester, size);

      final wallet = find.byIcon(Icons.account_balance_wallet_rounded);
      expect(wallet, findsOneWidget);

      final rect = tester.getRect(wallet);
      expect(rect.left, greaterThanOrEqualTo(-0.01),
          reason: 'the glyph ran off the start edge');
      expect(rect.right, lessThanOrEqualTo(size.width + 0.01),
          reason: 'the glyph ran off the end edge');

      await teardownTree(tester);
    });

    testWidgets('the cycle subtitle stays on screen at ${width}pt wide',
        (tester) async {
      await pumpHomeAt(tester, size);

      // The subtitle is the widest thing in the header; find it by the
      // separator it puts between the cycle label and the countdown.
      final subtitle = find.byWidgetPredicate(
        (w) => w is Text && (w.data?.contains('•') ?? false),
      );
      expect(subtitle, findsWidgets);

      final rect = tester.getRect(subtitle.first);
      expect(rect.left, greaterThanOrEqualTo(-0.01));
      expect(rect.right, lessThanOrEqualTo(size.width + 0.01));

      await teardownTree(tester);
    });
  }
}
