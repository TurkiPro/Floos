import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/period_summary.dart';

Category _cat(TxnType type) => Category(
      id: 1,
      name: 'c',
      iconKey: 'k',
      colorValue: 0,
      type: type,
      kind: CategoryKind.essential,
      archived: false,
      sortOrder: 0,
    );

TxnRow _txn(TxnType type, double amount, DateTime date) => TxnRow(
      txn: Txn(
        id: 1,
        amount: amount,
        categoryId: 1,
        type: type,
        date: date,
        createdAt: date,
      ),
      category: _cat(type),
    );

TxnRow _income(double amount, DateTime date) =>
    _txn(TxnType.income, amount, date);
TxnRow _expense(double amount, DateTime date) =>
    _txn(TxnType.expense, amount, date);

SavingsContribution _contrib(double amount, DateTime date) =>
    SavingsContribution(id: 1, goalId: 1, amount: amount, date: date);

void main() {
  group('monthlySummaries', () {
    test('aggregates income/spent/saved per month with derived figures', () {
      final rows = [
        _income(1000, DateTime(2026, 7, 1)),
        _income(200, DateTime(2026, 7, 20)),
        _expense(300, DateTime(2026, 7, 5)),
        _income(500, DateTime(2026, 6, 1)),
        _expense(100, DateTime(2026, 6, 10)),
      ];
      final contributions = [
        _contrib(240, DateTime(2026, 7, 8)),
        _contrib(50, DateTime(2026, 6, 15)),
      ];

      final summaries = monthlySummaries(rows, contributions);

      expect(summaries, hasLength(2));

      final july = summaries.firstWhere((s) => s.month == 7);
      expect(july.income, 1200);
      expect(july.spent, 300);
      expect(july.saved, 240);
      expect(july.remaining, 660); // 1200 - 300 - 240
      expect(july.savingsRate, 240 / 1200); // 0.2

      final june = summaries.firstWhere((s) => s.month == 6);
      expect(june.income, 500);
      expect(june.spent, 100);
      expect(june.saved, 50);
      expect(june.remaining, 350);
    });

    test('savingsRate is null when income is zero', () {
      final rows = [_expense(80, DateTime(2026, 7, 5))];
      final summaries = monthlySummaries(rows, const []);
      expect(summaries.single.income, 0);
      expect(summaries.single.savingsRate, isNull);
    });

    test('is ordered newest-first', () {
      final rows = [
        _income(100, DateTime(2025, 12, 1)),
        _income(100, DateTime(2026, 3, 1)),
        _income(100, DateTime(2026, 1, 1)),
      ];
      final summaries = monthlySummaries(rows, const []);
      expect(
        summaries.map((s) => '${s.year}-${s.month}'),
        ['2026-3', '2026-1', '2025-12'],
      );
    });

    test('a month with only contributions still appears', () {
      final contributions = [_contrib(75, DateTime(2026, 5, 4))];
      final summaries = monthlySummaries(const [], contributions);
      expect(summaries, hasLength(1));
      expect(summaries.single.month, 5);
      expect(summaries.single.year, 2026);
      expect(summaries.single.saved, 75);
      expect(summaries.single.income, 0);
      expect(summaries.single.spent, 0);
    });
  });

  group('yearlySummaries', () {
    test('aggregates income/spent/saved per year with derived figures', () {
      final rows = [
        _income(1000, DateTime(2026, 7, 1)),
        _income(500, DateTime(2026, 2, 1)),
        _expense(300, DateTime(2026, 3, 5)),
        _income(400, DateTime(2025, 8, 1)),
        _expense(100, DateTime(2025, 9, 10)),
      ];
      final contributions = [
        _contrib(300, DateTime(2026, 4, 8)),
        _contrib(50, DateTime(2025, 12, 15)),
      ];

      final summaries = yearlySummaries(rows, contributions);

      expect(summaries, hasLength(2));

      final y2026 = summaries.firstWhere((s) => s.year == 2026);
      expect(y2026.month, isNull);
      expect(y2026.income, 1500);
      expect(y2026.spent, 300);
      expect(y2026.saved, 300);
      expect(y2026.remaining, 900); // 1500 - 300 - 300
      expect(y2026.savingsRate, 300 / 1500); // 0.2

      final y2025 = summaries.firstWhere((s) => s.year == 2025);
      expect(y2025.income, 400);
      expect(y2025.spent, 100);
      expect(y2025.saved, 50);
      expect(y2025.remaining, 250);
    });

    test('is ordered newest-first', () {
      final rows = [
        _income(100, DateTime(2024, 1, 1)),
        _income(100, DateTime(2026, 1, 1)),
        _income(100, DateTime(2025, 1, 1)),
      ];
      final summaries = yearlySummaries(rows, const []);
      expect(summaries.map((s) => s.year), [2026, 2025, 2024]);
    });

    test('savingsRate is null when income is zero', () {
      final rows = [_expense(80, DateTime(2026, 7, 5))];
      final summaries = yearlySummaries(rows, const []);
      expect(summaries.single.income, 0);
      expect(summaries.single.savingsRate, isNull);
    });

    test('a year with only contributions still appears', () {
      final contributions = [_contrib(75, DateTime(2023, 5, 4))];
      final summaries = yearlySummaries(const [], contributions);
      expect(summaries, hasLength(1));
      expect(summaries.single.year, 2023);
      expect(summaries.single.saved, 75);
    });
  });
}
