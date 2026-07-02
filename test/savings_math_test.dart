import 'package:flutter_test/flutter_test.dart';
import 'package:floos/domain/savings_math.dart';

void main() {
  group('monthsUntilDeadline', () {
    test('counts whole months ahead', () {
      expect(
          monthsUntilDeadline(DateTime(2026, 1, 15), DateTime(2026, 6, 1)), 5);
    });

    test('never returns less than 1 for a past or current-month deadline', () {
      expect(
          monthsUntilDeadline(DateTime(2026, 6, 20), DateTime(2026, 6, 1)), 1);
      expect(
          monthsUntilDeadline(DateTime(2026, 7, 1), DateTime(2026, 1, 1)), 1);
    });

    test('spans a year boundary', () {
      expect(
          monthsUntilDeadline(DateTime(2025, 11, 1), DateTime(2026, 2, 1)), 3);
    });
  });

  group('suggestedMonthlyDeposit', () {
    test('spreads the remaining amount over the months left', () {
      final d = suggestedMonthlyDeposit(
        target: 6000,
        saved: 1000,
        deadline: DateTime(2026, 6, 1),
        now: DateTime(2026, 1, 1),
      );
      expect(d, 1000); // 5000 remaining / 5 months
    });

    test('recalculates higher after a skipped month (fewer months left)', () {
      // Same goal, one month later, nothing deposited: 5000 over 4 months.
      final d = suggestedMonthlyDeposit(
        target: 6000,
        saved: 1000,
        deadline: DateTime(2026, 6, 1),
        now: DateTime(2026, 2, 1),
      );
      expect(d, 1250);
    });

    test('is null without a deadline', () {
      expect(
        suggestedMonthlyDeposit(
            target: 6000, saved: 0, deadline: null, now: DateTime(2026, 1, 1)),
        isNull,
      );
    });

    test('is zero once the goal is met', () {
      expect(
        suggestedMonthlyDeposit(
            target: 6000,
            saved: 6000,
            deadline: DateTime(2026, 6, 1),
            now: DateTime(2026, 1, 1)),
        0,
      );
    });
  });
}
