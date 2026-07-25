import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/spending_window.dart';

void main() {
  final today = DateTime(2026, 7, 15);

  group('monthlyEquivalent', () {
    test('monthly passes through', () {
      expect(
          monthlyEquivalent(Frequency.monthly, 3000, 1), closeTo(3000, 1e-9));
    });

    test('weekly scales by 52/12', () {
      expect(monthlyEquivalent(Frequency.weekly, 100, 1),
          closeTo(100 * 52 / 12, 1e-9));
    });

    test('yearly is a twelfth', () {
      expect(
          monthlyEquivalent(Frequency.yearly, 12000, 1), closeTo(1000, 1e-9));
    });

    test('daily uses the average month length', () {
      expect(monthlyEquivalent(Frequency.daily, 10, 1), closeTo(304.4, 1e-9));
    });

    test('an interval divides the cost (every 2 months = half)', () {
      expect(
          monthlyEquivalent(Frequency.monthly, 3000, 2), closeTo(1500, 1e-9));
    });
  });

  group('incomeWeeklyBase', () {
    final start = DateTime(2026, 7, 1);
    final end = DateTime(2026, 8, 1); // 31-day cycle => 31/7 weeks

    test('disposable income spread over the cycle weeks', () {
      // (6000 − 2000 − 0) ÷ (31/7) = 4000 * 7 / 31.
      expect(
        incomeWeeklyBase(
          salaryMonthly: 6000,
          obligationsMonthly: 2000,
          savedThisCycle: 0,
          periodStart: start,
          periodEnd: end,
        ),
        closeTo(4000 * 7 / 31, 1e-9),
      );
    });

    test('savings this cycle reduce the disposable base', () {
      expect(
        incomeWeeklyBase(
          salaryMonthly: 6000,
          obligationsMonthly: 2000,
          savedThisCycle: 1500,
          periodStart: start,
          periodEnd: end,
        ),
        closeTo(2500 * 7 / 31, 1e-9),
      );
    });

    test('never negative when obligations exceed the salary', () {
      expect(
        incomeWeeklyBase(
          salaryMonthly: 1000,
          obligationsMonthly: 1200,
          savedThisCycle: 0,
          periodStart: start,
          periodEnd: end,
        ),
        0,
      );
    });

    test('a zero-length period divides by one week, no divide-by-zero', () {
      expect(
        incomeWeeklyBase(
          salaryMonthly: 700,
          obligationsMonthly: 0,
          savedThisCycle: 0,
          periodStart: start,
          periodEnd: start,
        ),
        closeTo(700, 1e-9),
      );
    });
  });

  group('weeklySpend', () {
    test('recommended = essential/weeks + luxury/weeks * 0.85', () {
      // Earliest 14 days ago => windowDays 14 => weeks 2.
      final w = weeklySpend(
        essentialWindow: 300,
        luxuryWindow: 400,
        earliestInWindow: today.subtract(const Duration(days: 13)),
        today: today,
      );
      // 300/2 + (400/2)*0.85 = 150 + 170.
      expect(w.recommended, closeTo(320, 1e-9));
    });

    test('pace ignores the discretionary discount', () {
      final w = weeklySpend(
        essentialWindow: 300,
        luxuryWindow: 400,
        earliestInWindow: today.subtract(const Duration(days: 13)),
        today: today,
      );
      // (300 + 400) / 2.
      expect(w.pace, closeTo(350, 1e-9));
    });

    test('weeks clamps to 1 for a sub-week window', () {
      final w = weeklySpend(
        essentialWindow: 100,
        luxuryWindow: 0,
        earliestInWindow: today.subtract(const Duration(days: 2)),
        today: today,
      );
      expect(w.recommended, closeTo(100, 1e-9)); // /1
    });

    test('weeks clamps to 12 for a window older than 84 days', () {
      final w = weeklySpend(
        essentialWindow: 1200,
        luxuryWindow: 0,
        earliestInWindow: today.subtract(const Duration(days: 200)),
        today: today,
      );
      expect(w.recommended, closeTo(100, 1e-9)); // 1200 / 12
    });

    test('no expenses in window => weeks 1, no divide-by-zero', () {
      final w = weeklySpend(
        essentialWindow: 0,
        luxuryWindow: 0,
        earliestInWindow: null,
        today: today,
      );
      expect(w.recommended, 0);
      expect(w.pace, 0);
    });
  });

  group('adaptiveWeeklyBudget', () {
    // A 4-week cycle (8 July – 5 Aug) with now one whole week in => weeksElapsed
    // = 1, weeksLeft = 3 (this week + two more).
    final periodStart = DateTime(2026, 7, 8);
    final periodEnd = DateTime(2026, 8, 5);
    final now = DateTime(2026, 7, 15);

    double adaptive(double recommended, double spentBefore) =>
        adaptiveWeeklyBudget(
          recommended: recommended,
          spentBeforeThisWeek: spentBefore,
          periodStart: periodStart,
          periodEnd: periodEnd,
          now: now,
        );

    test('returns the baseline when prior spend matches it exactly', () {
      // Spent one baseline week (300) across the 1 elapsed week => no carry.
      expect(adaptive(300, 300), closeTo(300, 1e-9));
    });

    test('overspending earlier lowers it (deficit spread over weeks left)', () {
      // Deficit = 300*1 - 600 = -300, over 3 weeks => -100.
      expect(adaptive(300, 600), closeTo(200, 1e-9));
    });

    test('a surplus raises it', () {
      // Surplus = 300*1 - 0 = 300, over 3 weeks => +100.
      expect(adaptive(300, 0), closeTo(400, 1e-9));
    });

    test('never goes negative', () {
      expect(adaptive(100, 1000), 0);
    });
  });

  group('balanceCappedWeekly', () {
    test('near payday, caps at the remaining balance (not a full 7 days)', () {
      // 600 left, 6 days to payday: a flat weekly figure of 700 would exceed
      // everything you have — cap it at the 600 balance.
      expect(
        balanceCappedWeekly(adaptive: 700, remainingForCycle: 600, daysLeft: 6),
        closeTo(600, 1e-9),
      );
    });

    test('with a week or more left, the balance ceiling does not bite', () {
      // 1400 over 14 days => 100/day => 700 for a 7-day week; adaptive is under.
      expect(
        balanceCappedWeekly(
            adaptive: 500, remainingForCycle: 1400, daysLeft: 14),
        closeTo(500, 1e-9),
      );
    });

    test('still caps at the 7-day ceiling when adaptive is above it', () {
      expect(
        balanceCappedWeekly(
            adaptive: 900, remainingForCycle: 1400, daysLeft: 14),
        closeTo(700, 1e-9),
      );
    });

    test('no balance left => zero', () {
      expect(
          balanceCappedWeekly(adaptive: 500, remainingForCycle: 0, daysLeft: 5),
          0);
      expect(
          balanceCappedWeekly(
              adaptive: 500, remainingForCycle: -50, daysLeft: 5),
          0);
    });
  });
}
