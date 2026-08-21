import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/spending_window.dart';
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

    double adaptive(double spentBefore, DateTime ws) => adaptiveWeeklyBudget(
          recommended: 700,
          spentBeforeThisWeek: spentBefore,
          periodStart: start,
          periodEnd: end,
          now: ws,
        );

    test('each week gets its own budget, adapted as of that week', () {
      final weeks = weeklyPerformance(
        rows: [
          _exp(800, DateTime(2026, 7, 2)), // week 1
          _exp(400, DateTime(2026, 7, 7)), // week 1
          _exp(999, DateTime(2026, 7, 8),
              recurrenceId: 5), // recurring -> excluded
        ],
        byId: {1: _cat()},
        baseWeekly: 700,
        now: now,
        periodStart: start,
        periodEnd: end,
      );
      expect(weeks.length, 3);
      // Week 1: no prior spend -> the base itself.
      expect(weeks[0].budget, closeTo(700, 1e-9));
      expect(weeks[0].spent, 1200);
      expect(weeks[0].over, isTrue);
      // Week 2: week 1's 1200 overspend lowers THIS week's budget below the base.
      expect(
          weeks[1].budget, closeTo(adaptive(1200, DateTime(2026, 7, 8)), 1e-9));
      expect(weeks[1].budget, lessThan(700));
      expect(weeks[1].spent, 0); // the recurring 999 is excluded
      expect(weeks[2].current, isTrue);
    });

    test("a past week's budget is frozen — later weeks don't change it", () {
      List<WeekPerformance> run(List<TxnRow> rows) => weeklyPerformance(
            rows: rows,
            byId: {1: _cat()},
            baseWeekly: 700,
            now: DateTime(2026, 7, 20),
            periodStart: start,
            periodEnd: end,
          );
      final a = run([_exp(300, DateTime(2026, 7, 2))]); // week 1 only
      final b = run([
        _exp(300, DateTime(2026, 7, 2)), // same week 1
        _exp(5000, DateTime(2026, 7, 17)), // a LATER week blows its budget
      ]);
      final w1a = a.firstWhere((w) => w.index == 1);
      final w1b = b.firstWhere((w) => w.index == 1);
      // The later week's overspend must not move week 1's already-passed budget.
      expect(w1b.budget, closeTo(w1a.budget, 1e-9));
    });

    test('a short final week is pro-rated to its length', () {
      // Cycle 1–24 July: weeks 1–8, 8–15, 15–22, then a 2-day tail 22–24.
      final s = DateTime(2026, 7, 1);
      final e = DateTime(2026, 7, 24);
      final weeks = weeklyPerformance(
        rows: const [],
        byId: {1: _cat()},
        baseWeekly: 700,
        now: DateTime(2026, 7, 24),
        periodStart: s,
        periodEnd: e,
      );
      final last = weeks.last;
      expect(last.weekStart, DateTime(2026, 7, 22));
      // Its own adaptive budget (nothing spent all cycle), pro-rated by 2/7.
      final adaptiveLast = adaptiveWeeklyBudget(
        recommended: 700,
        spentBeforeThisWeek: 0,
        periodStart: s,
        periodEnd: e,
        now: DateTime(2026, 7, 22),
      );
      expect(last.budget, closeTo(adaptiveLast * 2 / 7, 1e-9));
    });

    test('per-day breakdown slots every day of the week', () {
      final weeks = weeklyPerformance(
        rows: [
          _exp(800, DateTime(2026, 7, 2)),
          _exp(400, DateTime(2026, 7, 7))
        ],
        byId: {1: _cat()},
        baseWeekly: 700,
        now: now,
        periodStart: start,
        periodEnd: end,
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
