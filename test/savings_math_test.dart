import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/database.dart';
import 'package:floos/domain/savings_math.dart';

SavingsContribution _contrib(double amount, DateTime date,
        {bool external = false}) =>
    SavingsContribution(
        id: 1, goalId: 1, amount: amount, date: date, external: external);

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

  group('goalEta', () {
    test('projects the finish date from the actual saving pace', () {
      // 1000 saved over 30 days => 1000/30 per day; 1000 still to go => 30 more
      // days from now (31 Jan) => 2 Mar 2026.
      final eta = goalEta(
        contributions: [_contrib(1000, DateTime(2026, 1, 1))],
        target: 2000,
        now: DateTime(2026, 1, 31),
      );
      expect(eta, DateTime(2026, 3, 2));
    });

    test('is null once the goal is already met', () {
      expect(
        goalEta(
          contributions: [_contrib(2000, DateTime(2026, 1, 1))],
          target: 2000,
          now: DateTime(2026, 1, 31),
        ),
        isNull,
      );
    });

    test('external deposits count toward the balance but not the pace', () {
      // Only an imported 5000 (external) and no internal saving => no real pace
      // to project from, even though there's 1000 still to go.
      expect(
        goalEta(
          contributions: [
            _contrib(5000, DateTime(2026, 1, 1), external: true),
          ],
          target: 6000,
          now: DateTime(2026, 1, 31),
        ),
        isNull,
      );
    });

    test('is null with no contributions', () {
      expect(
        goalEta(contributions: const [], target: 1000, now: DateTime(2026, 1)),
        isNull,
      );
    });
  });
}
