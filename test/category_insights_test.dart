import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/category_breakdown.dart';
import 'package:floos/domain/category_insights.dart';

final now = DateTime(2026, 7, 15);

Category _cat({
  required int id,
  CategoryKind kind = CategoryKind.essential,
  int? parentId,
}) =>
    Category(
      id: id,
      name: 'c$id',
      iconKey: 'k',
      colorValue: 0,
      type: TxnType.expense,
      kind: kind,
      archived: false,
      sortOrder: 0,
      parentId: parentId,
    );

TxnRow _exp(int catId, double amount, DateTime date,
        {CategoryKind kind = CategoryKind.essential}) =>
    TxnRow(
      txn: Txn(
        id: 1,
        amount: amount,
        categoryId: catId,
        type: TxnType.expense,
        date: date,
        createdAt: date,
      ),
      category: _cat(id: catId, kind: kind),
    );

RecurrenceRule _salary() => RecurrenceRule(
      id: 1,
      title: 'راتب',
      amount: 10000,
      categoryId: 9,
      type: TxnType.income,
      frequency: Frequency.monthly,
      interval: 1,
      startDate: DateTime(2026, 1, 25),
      active: true,
    );

void main() {
  group('categoryTrends', () {
    // Three prior cycles of 100 each for category 1 -> norm 100.
    final rows = [
      _exp(1, 100, DateTime(2026, 4, 1)), // [03-25, 04-25)
      _exp(1, 100, DateTime(2026, 5, 1)), // [04-25, 05-25)
      _exp(1, 100, DateTime(2026, 6, 1)), // [05-25, 06-25)
    ];

    test('up when this cycle is well above the norm', () {
      final t = categoryTrends(
        rows: rows,
        incomeRules: [_salary()],
        now: now,
        thisCycleTotals: {1: 150},
      );
      expect(t[1]!.direction, TrendDirection.up);
      expect(t[1]!.pctChange, closeTo(50, 0.001));
    });

    test('down when well below, steady when near', () {
      final down = categoryTrends(
        rows: rows,
        incomeRules: [_salary()],
        now: now,
        thisCycleTotals: {1: 50},
      );
      expect(down[1]!.direction, TrendDirection.down);

      final steady = categoryTrends(
        rows: rows,
        incomeRules: [_salary()],
        now: now,
        thisCycleTotals: {1: 105},
      );
      expect(steady[1]!.direction, TrendDirection.steady);
    });

    test('no prior spend -> none', () {
      final t = categoryTrends(
        rows: const [],
        incomeRules: [_salary()],
        now: now,
        thisCycleTotals: {7: 300},
      );
      expect(t[7]!.direction, TrendDirection.steady);
      expect(t[7]!.pctChange, 0);
    });
  });

  group('cutSuggestions', () {
    test('a rising luxury outranks a bigger steady essential', () {
      final rent = _cat(id: 1); // essential
      final coffee = _cat(id: 2, kind: CategoryKind.luxury);
      final breakdown = [
        CategoryStat(
            categoryId: 1, total: 2000, transactions: [_exp(1, 2000, now)]),
        CategoryStat(
            categoryId: 2,
            total: 800,
            transactions: [_exp(2, 800, now, kind: CategoryKind.luxury)]),
      ];
      final s = cutSuggestions(
        breakdown: breakdown,
        byId: {1: rent, 2: coffee},
        trends: {
          1: CategoryTrend.none,
          2: const CategoryTrend(TrendDirection.up, 40),
        },
        periodTotal: 2800,
      );
      expect(s.first.categoryId, 2); // the rising luxury
      expect(s.first.reason, contains('كماليات'));
      expect(s.first.reason, contains('ترتفع'));
    });

    test('a small steady essential is filtered out', () {
      final water = _cat(id: 5);
      final breakdown = [
        CategoryStat(
            categoryId: 5, total: 20, transactions: [_exp(5, 20, now)]),
      ];
      final s = cutSuggestions(
        breakdown: breakdown,
        byId: {5: water},
        trends: {5: CategoryTrend.none},
        periodTotal: 4000, // 0.5% share -> score well under the floor
      );
      expect(s, isEmpty);
    });
  });
}
