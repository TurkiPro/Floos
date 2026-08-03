import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/budget_advisor.dart';
import 'package:floos/domain/calendar_format.dart';
import 'package:floos/domain/financial_period.dart';
import 'package:floos/domain/period_summary.dart';

RecurrenceRule _salary({DateTime? start}) => RecurrenceRule(
      id: 1,
      title: 'راتب',
      amount: 10000,
      categoryId: 9,
      type: TxnType.income,
      frequency: Frequency.monthly,
      interval: 1,
      startDate: start ?? DateTime(2026, 1, 1),
      active: true,
    );

Category _cat(TxnType t) => Category(
      id: t == TxnType.income ? 9 : 1,
      name: 'c',
      iconKey: 'k',
      colorValue: 0,
      type: t,
      kind: CategoryKind.essential,
      archived: false,
      sortOrder: 0,
      parentId: null,
    );

TxnRow _txn(TxnType t, double amount, DateTime date) => TxnRow(
      txn: Txn(
        id: 1,
        amount: amount,
        categoryId: t == TxnType.income ? 9 : 1,
        type: t,
        date: date,
        createdAt: date,
      ),
      category: _cat(t),
    );

SavingsContribution _c(double amount, DateTime date, {bool external = false}) =>
    SavingsContribution(
        id: 1, goalId: 1, amount: amount, date: date, external: external);

void main() {
  group('cyclesCovering', () {
    test('enumerates cycles from earliest activity to the current one', () {
      final cycles = cyclesCovering(
          [_salary()], DateTime(2026, 2, 10), DateTime(2026, 7, 15));
      expect(cycles.length, 6);
      expect(cycles.first.start, DateTime(2026, 7, 1)); // current, newest first
      expect(cycles.last.start, DateTime(2026, 2, 1)); // contains earliest
    });
  });

  group('cycleLabelFor', () {
    test('a month-aligned cycle shows just the month name', () {
      final p = FinancialPeriod(DateTime(2026, 7, 1), DateTime(2026, 8, 1));
      expect(cycleLabelFor(p, hijri: false), 'يوليو 2026');
    });

    test('a straddling cycle shows an inclusive date range', () {
      final p = FinancialPeriod(DateTime(2026, 7, 25), DateTime(2026, 8, 25));
      expect(cycleLabelFor(p, hijri: false), '25 يوليو – 24 أغسطس 2026');
    });
  });

  group('cycleSummaries', () {
    test('per-cycle totals, external ignored, empty cycles skipped', () {
      final rows = [
        _txn(TxnType.income, 10000, DateTime(2026, 3, 1)),
        _txn(TxnType.expense, 400, DateTime(2026, 3, 5)),
        // April: nothing
        _txn(TxnType.income, 10000, DateTime(2026, 5, 1)),
        _txn(TxnType.expense, 600, DateTime(2026, 5, 10)),
      ];
      final contribs = [
        _c(1000, DateTime(2026, 3, 6)),
        _c(5000, DateTime(2026, 3, 7), external: true), // ignored
      ];
      final out =
          cycleSummaries(rows, contribs, [_salary()], DateTime(2026, 5, 20));
      expect(out.length, 2); // May and March; April skipped
      expect(out.first.period.start, DateTime(2026, 5, 1));
      expect(out.first.income, 10000);
      expect(out.first.spent, 600);
      expect(out.last.period.start, DateTime(2026, 3, 1));
      expect(out.last.spent, 400);
      expect(out.last.saved, 1000);
      expect(out.last.remaining, 10000 - 400 - 1000);
    });
  });
}
