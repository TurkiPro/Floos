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
    // 15–21 (current).
    final now = DateTime(2026, 7, 16);
    final start = DateTime(2026, 7, 1);
    final end = DateTime(2026, 8, 1);

    // The budgets come from outside (see weekly_budget_in_force_test for the
    // real ones); here each past week gets a figure that names its start day.
    double byStart(DateTime ws, DateTime we) => ws.day.toDouble();

    test('each week gets its own budget; the current one the home figure', () {
      final weeks = weeklyPerformance(
        rows: [
          _exp(800, DateTime(2026, 7, 2)), // week 1
          _exp(400, DateTime(2026, 7, 7)), // week 1
          _exp(999, DateTime(2026, 7, 8),
              recurrenceId: 5), // recurring -> excluded
        ],
        byId: {1: _cat()},
        now: now,
        periodStart: start,
        periodEnd: end,
        currentWeekBudget: 700,
        pastWeekBudget: byStart,
      );
      expect(weeks.length, 3);
      expect(weeks[0].budget, 1);
      expect(weeks[0].spent, 1200);
      expect(weeks[0].over, isTrue);
      expect(weeks[1].budget, 8);
      expect(weeks[1].spent, 0); // the recurring 999 is excluded
      expect(weeks[2].current, isTrue);
      expect(weeks[2].budget, 700);
    });

    test('a past week asks for the budget up to its own end', () {
      final ends = <DateTime>[];
      weeklyPerformance(
        rows: const [],
        byId: {1: _cat()},
        now: now,
        periodStart: start,
        periodEnd: end,
        currentWeekBudget: 700,
        pastWeekBudget: (ws, we) {
          ends.add(we);
          return 0;
        },
      );
      expect(ends, [DateTime(2026, 7, 8), DateTime(2026, 7, 15)]);
    });

    test('a short final week ends at the cycle end', () {
      // Cycle 1–24 July: weeks 1–8, 8–15, 15–22, then a 2-day tail 22–24.
      final ends = <DateTime, DateTime>{};
      final weeks = weeklyPerformance(
        rows: const [],
        byId: {1: _cat()},
        now: DateTime(2026, 7, 30),
        periodStart: DateTime(2026, 7, 1),
        periodEnd: DateTime(2026, 7, 24),
        currentWeekBudget: 700,
        pastWeekBudget: (ws, we) {
          ends[ws] = we;
          return 0;
        },
      );
      expect(weeks.last.weekStart, DateTime(2026, 7, 22));
      expect(weeks.last.days, hasLength(2));
      expect(ends[DateTime(2026, 7, 22)], DateTime(2026, 7, 24));
    });

    test('per-day breakdown slots every day of the week', () {
      final weeks = weeklyPerformance(
        rows: [
          _exp(800, DateTime(2026, 7, 2)),
          _exp(400, DateTime(2026, 7, 7))
        ],
        byId: {1: _cat()},
        now: now,
        periodStart: start,
        periodEnd: end,
        currentWeekBudget: 700,
        pastWeekBudget: byStart,
      );
      final w1 = weeks[0];
      expect(w1.days.length, 7); // full week has 7 day slots
      expect(w1.days[1].total, 800); // 2 July is day index 1
      expect(w1.days[6].total, 400); // 7 July is day index 6
      expect(w1.days[0].total, 0); // 1 July, empty
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
