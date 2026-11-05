import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floos/data/backup.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/dashboard_summary.dart';
import 'package:floos/domain/financial_period.dart';
import 'package:floos/domain/ledger_balance.dart';
import 'package:floos/domain/statistics_summary.dart';
import 'package:floos/domain/weekly_budget_status.dart';
import 'package:floos/services/alerts_coordinator.dart';

/// Debts (schema v16): money lent and borrowed moves the balance but is never
/// spending or income, and borrowed money is never yours to spend.

Category _cat(TxnType type) => Category(
      id: type == TxnType.income ? 9 : 1,
      name: 'c',
      iconKey: 'k',
      colorValue: 0,
      type: type,
      kind: CategoryKind.essential,
      archived: false,
      sortOrder: 0,
    );

TxnRow _txn(TxnType type, double amount, DateTime date,
        {int? recurrenceId}) =>
    TxnRow(
      txn: Txn(
        id: 1,
        amount: amount,
        categoryId: type == TxnType.income ? 9 : 1,
        type: type,
        date: date,
        recurrenceId: recurrenceId,
        createdAt: date,
      ),
      category: _cat(type),
    );

var _nextId = 1;
DebtMovementRow _move(DebtDirection direction, double amount, DateTime date,
    {bool external = false, int debtId = 1}) {
  final debt = Debt(
    id: debtId,
    person: 'فهد',
    direction: direction,
    createdAt: date,
  );
  return DebtMovementRow(
    movement: DebtMovement(
      id: _nextId++,
      debtId: debtId,
      amount: amount,
      date: date,
      external: external,
    ),
    debt: debt,
  );
}

LedgerInputs _ledger(List<TxnRow> rows, List<DebtMovementRow> debts) =>
    LedgerInputs(
        rows: rows,
        contributions: const [],
        investments: const [],
        debts: debts);

final _july = FinancialPeriod(DateTime(2026, 7, 1), DateTime(2026, 8, 1));

void main() {
  group('the balance', () {
    final income = [_txn(TxnType.income, 10000, DateTime(2026, 7, 1))];

    test('lending takes money out; a repayment brings it back', () {
      final lent = [
        _move(DebtDirection.lent, 500, DateTime(2026, 7, 5)),
        _move(DebtDirection.lent, -200, DateTime(2026, 7, 9)),
      ];
      expect(ledgerTotals(_ledger(income, lent)).balance, 10000 - 500 + 200);
    });

    test('borrowing brings money in; repaying it takes money out', () {
      final borrowed = [
        _move(DebtDirection.borrowed, 2000, DateTime(2026, 7, 5)),
        _move(DebtDirection.borrowed, -500, DateTime(2026, 7, 9)),
      ];
      expect(ledgerTotals(_ledger(income, borrowed)).balance,
          10000 + 2000 - 500);
    });

    test('external movements never touch the balance', () {
      final old = [
        _move(DebtDirection.lent, 3000, DateTime(2026, 7, 5), external: true),
        _move(DebtDirection.borrowed, 9000, DateTime(2026, 7, 5),
            external: true, debtId: 2),
      ];
      expect(ledgerTotals(_ledger(income, old)).balance, 10000);
    });

    test('spendable leaves borrowed money out entirely', () {
      final l = _ledger(income, [
        _move(DebtDirection.borrowed, 2000, DateTime(2026, 7, 5)),
        _move(DebtDirection.lent, 300, DateTime(2026, 7, 6), debtId: 2),
      ]);
      expect(ledgerTotals(l).balance, 11700);
      expect(spendableTotals(l).balance, 9700,
          reason: 'what is owed is not yours to spend; what you lent is gone');
    });

    test('what each debt still stands at', () {
      final out = debtOutstanding([
        _move(DebtDirection.lent, 500, DateTime(2026, 7, 5)),
        _move(DebtDirection.lent, -200, DateTime(2026, 7, 9)),
        _move(DebtDirection.borrowed, 9000, DateTime(2026, 7, 5),
            external: true, debtId: 2),
      ]);
      expect(out, {1: 300, 2: 9000},
          reason: 'an external loan is still owed');
    });
  });

  group('the home card', () {
    test('borrowing raises the balance but not «المتبقي»', () {
      // A deficit carried in: last cycle overspent, so this salary is partly
      // spoken for and «المتبقي» is capped at the balance (50).
      final rows = [
        _txn(TxnType.expense, 950, DateTime(2026, 6, 20)),
        _txn(TxnType.income, 1000, DateTime(2026, 7, 1)),
      ];
      final borrowed = [
        _move(DebtDirection.borrowed, 2000, DateTime(2026, 7, 3)),
      ];
      final before =
          DashboardSummary.from(rows, const [], const [], _july, debts: const []);
      final after =
          DashboardSummary.from(rows, const [], const [], _july, debts: borrowed);

      expect(after.balance, before.balance + 2000);
      expect(after.monthRemaining, before.monthRemaining,
          reason: 'a loan must not read as money left to spend');
      expect(after.monthRemaining, 50);
    });

    test('neither direction is spending or income', () {
      final rows = [_txn(TxnType.income, 1000, DateTime(2026, 7, 1))];
      final debts = [
        _move(DebtDirection.lent, 400, DateTime(2026, 7, 2)),
        _move(DebtDirection.borrowed, 900, DateTime(2026, 7, 3), debtId: 2),
      ];
      final d = DashboardSummary.from(rows, const [], const [], _july,
          debts: debts);
      expect(d.monthSpent, 0);
      expect(d.monthExpenses, isEmpty);
    });

    test('borrowed money alone does not count as the salary landing', () {
      final d = DashboardSummary.from(const [], const [], const [], _july,
          debts: [_move(DebtDirection.borrowed, 5000, DateTime(2026, 7, 3))]);
      expect(d.incomeReceivedThisMonth, isFalse,
          reason: 'no savings prompt for a loan');
    });
  });

  group('the weekly budget', () {
    final now = DateTime(2026, 7, 20); // week of 15–21 July (calendar fallback)

    // A salary on the 1st keeps the same 1 July cycle as the calendar
    // fallback, and gives the budget a real base to work from.
    final salary = [
      RecurrenceRule(
        id: 1,
        title: 'راتب',
        amount: 10000,
        categoryId: 9,
        type: TxnType.income,
        frequency: Frequency.monthly,
        interval: 1,
        startDate: DateTime(2026, 1, 1),
        active: true,
      ),
    ];

    WeeklyBudgetStatus status(List<TxnRow> rows, List<DebtMovementRow> debts) =>
        weeklyBudgetStatus(
          rows: rows,
          incomeRules: salary,
          expenseRules: const [],
          contributions: const [],
          investments: const [],
          debts: debts,
          now: now,
        );

    // Little money left after a big fixed obligation (not discretionary, so
    // it does not lower the adaptive budget), so the balance cap is what sets
    // the budget — the case where a loan could wrongly raise it.
    //
    // And a small deficit carried in from June, so the BALANCE (400 at week
    // start) is below what is left of this cycle's income (1000). That is
    // the only case where the balance sets the cap — and so the only case
    // where counting a loan as spendable would raise the budget.
    final tight = [
      _txn(TxnType.expense, 600, DateTime(2026, 6, 20)),
      _txn(TxnType.income, 10000, DateTime(2026, 7, 1)),
      _txn(TxnType.expense, 9000, DateTime(2026, 7, 2), recurrenceId: 5),
    ];

    test('lending this week is not spending this week', () {
      final base = status(tight, const []);
      final lent = status(
          tight, [_move(DebtDirection.lent, 100, DateTime(2026, 7, 16))]);
      expect(lent.spent, base.spent);
    });

    test('money lent before the week lowers the cap', () {
      final base = status(tight, const []);
      final lent = status(
          tight, [_move(DebtDirection.lent, 300, DateTime(2026, 7, 10))]);
      expect(base.budget, greaterThan(0),
          reason: 'the fixture must leave a budget to lower');
      expect(lent.budget, lessThan(base.budget));
    });

    test('borrowing never raises it, and repaying never lowers it', () {
      final base = status(tight, const []);
      expect(base.budget, greaterThan(0));
      final borrowed = status(tight, [
        _move(DebtDirection.borrowed, 5000, DateTime(2026, 7, 10)),
      ]);
      expect(borrowed.budget, base.budget,
          reason: 'a loan is not spending money');

      final repaidMidWeek = status(tight, [
        _move(DebtDirection.borrowed, 5000, DateTime(2026, 7, 10)),
        _move(DebtDirection.borrowed, -1000, DateTime(2026, 7, 17)),
      ]);
      expect(repaidMidWeek.budget, base.budget,
          reason: 'the week\'s budget holds still for a repayment');
    });

    test('home and stats agree with debts in the data', () {
      final period = financialPeriod(salary, now);
      final debts = [
        _move(DebtDirection.lent, 300, DateTime(2026, 7, 10)),
        _move(DebtDirection.borrowed, 5000, DateTime(2026, 7, 11), debtId: 2),
      ];
      final home = status(tight, debts);
      final stats = StatisticsSummary.from(
          tight, const [], salary, const [], now, period,
          debts: debts);
      expect(stats.recommendedWeekly, closeTo(home.budget, 1e-9));
    });
  });

  group('the database', () {
    late AppDatabase db;
    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
    });

    test('a debt opens with its loan, and deleting it takes its history',
        () async {
      final id = await db.debtDao.addDebt(
        person: 'فهد',
        direction: DebtDirection.lent,
        amount: 500,
        date: DateTime(2026, 7, 5),
      );
      await db.debtDao.addMovement(
          debtId: id, amount: -200, date: DateTime(2026, 7, 9));
      final rows = await db.debtDao.watchAllMovements().first;
      expect(debtOutstanding(rows), {id: 300});

      await db.debtDao.deleteDebt(id);
      expect(await db.debtDao.getAllMovements(), isEmpty);
    });

    test('a debt must open with a positive amount', () {
      expect(
        () => db.debtDao.addDebt(
            person: 'x',
            direction: DebtDirection.lent,
            amount: 0,
            date: DateTime(2026, 7, 5)),
        throwsArgumentError,
      );
    });

    test('the badge and reminders see debts too', () async {
      // computeWeeklyBudget is what the badge and notifications use; it loads
      // debts itself, so a loan must not raise the figure there either.
      await db.recurrenceDao.add(
          title: 'راتب',
          amount: 10000,
          categoryId: 9,
          type: TxnType.income,
          frequency: Frequency.monthly,
          startDate: DateTime(2026, 1, 1));
      // A deficit carried in from June — see the weekly-budget group above.
      await db.transactionDao.add(
          amount: 600,
          categoryId: 1,
          type: TxnType.expense,
          date: DateTime(2026, 6, 20));
      await db.transactionDao.add(
          amount: 10000,
          categoryId: 9,
          type: TxnType.income,
          date: DateTime(2026, 7, 1));
      // A big fixed obligation, so the balance cap is what sets the budget.
      final rentId = await db.recurrenceDao.add(
          title: 'إيجار',
          amount: 9000,
          categoryId: 1,
          type: TxnType.expense,
          frequency: Frequency.yearly,
          startDate: DateTime(2026, 7, 2));
      final rent = (await db.recurrenceDao.activeRules())
          .firstWhere((r) => r.id == rentId);
      await db.transactionDao.insertGenerated(rent, DateTime(2026, 7, 2));
      final now = DateTime(2026, 7, 20);
      final before = await computeWeeklyBudget(db, now);
      expect(before.recommended, greaterThan(0));
      await db.debtDao.addDebt(
        person: 'أخي',
        direction: DebtDirection.borrowed,
        amount: 5000,
        date: DateTime(2026, 7, 10),
      );
      final after = await computeWeeklyBudget(db, now);
      expect(after.recommended, before.recommended);
    });

    test('debts survive backup and restore', () async {
      final id = await db.debtDao.addDebt(
        person: 'فهد',
        direction: DebtDirection.borrowed,
        amount: 2000,
        date: DateTime(2026, 7, 5),
        external: true,
      );
      await db.debtDao.addMovement(
          debtId: id, amount: -500, date: DateTime(2026, 7, 9), note: 'نقدًا');

      final target = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(target.close);
      await restoreBackupJson(target, await buildBackupJson(db));

      final debts = await target.debtDao.getAllDebts();
      expect(debts.single.person, 'فهد');
      expect(debts.single.direction, DebtDirection.borrowed);
      final moves = await target.debtDao.getAllMovements();
      expect(moves.map((m) => m.amount), containsAll([2000.0, -500.0]));
      expect(moves.firstWhere((m) => m.amount == 2000).external, isTrue);
      expect(moves.firstWhere((m) => m.amount == -500).note, 'نقدًا');
    });

    test('a pre-v16 backup restores with no debts', () async {
      await db.debtDao.addDebt(
        person: 'فهد',
        direction: DebtDirection.lent,
        amount: 500,
        date: DateTime(2026, 7, 5),
      );
      final map =
          jsonDecode(await buildBackupJson(db)) as Map<String, dynamic>;
      map.remove('debts');
      map.remove('debtMovements');

      final target = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(target.close);
      await restoreBackupJson(target, jsonEncode(map));
      expect(await target.debtDao.getAllDebts(), isEmpty);
    });
  });
}
