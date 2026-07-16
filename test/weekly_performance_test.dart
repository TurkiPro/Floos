import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/weekly_performance.dart';
import 'package:floos/domain/weekly_series.dart';

Category _cat() => const Category(
      id: 1,
      name: 'c',
      iconKey: 'k',
      colorValue: 0,
      type: TxnType.expense,
      kind: CategoryKind.essential,
      archived: false,
      sortOrder: 0,
      parentId: null,
    );

TxnRow _exp(double amount, DateTime date, {int? recurrenceId}) => TxnRow(
      txn: Txn(
        id: 1,
        amount: amount,
        categoryId: 1,
        type: TxnType.expense,
        date: date,
        recurrenceId: recurrenceId,
        createdAt: date,
      ),
      category: _cat(),
    );

void main() {
  group('weeklyPerformance', () {
    // July 2026 cycle anchored on 1 July; now = 16 July. Weeks: 1–7, 8–14,
    // 15–21 (current, clamped to 15–16).
    final now = DateTime(2026, 7, 16);
    final start = DateTime(2026, 7, 1);
    final end = DateTime(2026, 8, 1);

    test('splits into salary-anchored weeks with pro-rated budgets', () {
      final weeks = weeklyPerformance(
        rows: [
          _exp(800, DateTime(2026, 7, 2)), // week 1
          _exp(400, DateTime(2026, 7, 7)), // week 1
          _exp(999, DateTime(2026, 7, 8),
              recurrenceId: 5), // week 2, recurring -> excluded
        ],
        byId: {1: _cat()},
        weeklyBudget: 700,
        now: now,
        periodStart: start,
        periodEnd: end,
      );
      expect(weeks.length, 3);
      expect(weeks[0].weekStart, DateTime(2026, 7, 1));
      expect(weeks[0].budget, closeTo(700, 1e-9)); // full 7-day week
      expect(weeks[0].spent, 1200);
      expect(weeks[0].over, isTrue);
      expect(weeks[1].budget, closeTo(700, 1e-9));
      expect(weeks[1].spent, 0); // the recurring 999 is excluded
      expect(weeks[2].current, isTrue);
      expect(weeks[2].budget, closeTo(200, 1e-9)); // 700 * 2/7
    });

    test('per-day breakdown slots every day of the week', () {
      final weeks = weeklyPerformance(
        rows: [
          _exp(800, DateTime(2026, 7, 2)),
          _exp(400, DateTime(2026, 7, 7))
        ],
        byId: {1: _cat()},
        weeklyBudget: 700,
        now: now,
        periodStart: start,
        periodEnd: end,
      );
      final w1 = weeks[0];
      expect(w1.days.length, 7); // full week has 7 day slots
      expect(w1.days[1].total, 800); // 2 July is day index 1
      expect(w1.days[6].total, 400); // 7 July is day index 6
      expect(w1.days[0].total, 0); // 1 July, empty
      // The slice carries the category name/colour for the chart legend.
      expect(w1.days[1].slices.first.name, 'c');
      expect(w1.days[1].slices.first.categoryId, 1);
    });
  });

  group('weeklySpendSeries', () {
    test('buckets total spend into the last N weeks from the anchor', () {
      final series = weeklySpendSeries(
        rows: [
          _exp(100, DateTime(2026, 6, 26)), // 3 weeks back
          _exp(200, DateTime(2026, 7, 16)), // current week
        ],
        anchorWeekStart: DateTime(2026, 7, 15),
        weeks: 4,
      );
      expect(series.length, 4);
      expect(series.first.total, 100);
      expect(series.first.weekStart, DateTime(2026, 6, 24));
      expect(series.last.total, 200);
      expect(series.last.weekStart, DateTime(2026, 7, 15));
    });
  });
}
