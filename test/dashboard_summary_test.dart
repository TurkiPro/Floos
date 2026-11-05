import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/dashboard_summary.dart';
import 'package:floos/domain/financial_period.dart';

// A fixed period (calendar July 2026) so the current-period split is
// deterministic. The salary-cycle derivation itself is covered in
// financial_period_test.dart.
final july = FinancialPeriod(DateTime(2026, 7, 1), DateTime(2026, 8, 1));

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

SavingsContribution _contrib(double amount, DateTime date,
        {bool external = false}) =>
    SavingsContribution(
        id: 1,
        goalId: 1,
        amount: amount,
        date: date,
        external: external,
        planned: false);

Investment _inv(double amount, {bool external = false}) => Investment(
      id: 1,
      name: 'x',
      amount: amount,
      date: DateTime(2026, 7, 5),
      external: external,
    );

void main() {
  group('DashboardSummary.from', () {
    test('balance is all income - all expense - all savings across months', () {
      final rows = [
        _income(1000, DateTime(2026, 7, 1)),
        _income(500, DateTime(2026, 5, 1)),
        _expense(200, DateTime(2026, 7, 3)),
        _expense(100, DateTime(2026, 4, 20)),
      ];
      final contributions = [
        _contrib(300, DateTime(2026, 7, 2)),
        _contrib(50, DateTime(2026, 3, 10)),
      ];

      final d = DashboardSummary.from(
          rows, contributions, const <Investment>[], july);

      // 1500 income - 300 expense - 350 savings.
      expect(d.balance, 850);
      expect(d.savingsTotal, 350);
    });

    test('month figures isolate the current month', () {
      final rows = [
        _income(1000, DateTime(2026, 7, 1)), // this month
        _income(999, DateTime(2026, 6, 1)), // other month, ignored for month
        _expense(200, DateTime(2026, 7, 3)), // this month
        _expense(77, DateTime(2026, 6, 15)), // other month, ignored for month
      ];
      final contributions = [
        _contrib(300, DateTime(2026, 7, 2)), // this month
        _contrib(40, DateTime(2026, 6, 9)), // other month, ignored for month
      ];

      final d = DashboardSummary.from(
          rows, contributions, const <Investment>[], july);

      // monthIncome 1000 - monthSpent 200 - monthSaved 300.
      expect(d.monthRemaining, 500);
      expect(d.monthSpent, 200);
      expect(d.monthSaved, 300);
      // But the all-time balance still counts the other-month rows:
      // 1999 income - 277 expense - 340 savings.
      expect(d.balance, 1382);
    });

    test('incomeReceivedThisMonth is false without income this month', () {
      final rows = [
        _income(1000, DateTime(2026, 6, 1)), // last month only
        _expense(50, DateTime(2026, 7, 4)),
      ];
      final d =
          DashboardSummary.from(rows, const [], const <Investment>[], july);
      expect(d.incomeReceivedThisMonth, isFalse);
    });

    test('incomeReceivedThisMonth is true with income this month', () {
      final rows = [_income(1000, DateTime(2026, 7, 10))];
      final d =
          DashboardSummary.from(rows, const [], const <Investment>[], july);
      expect(d.incomeReceivedThisMonth, isTrue);
    });

    test('monthExpenses holds only this-month expenses, excluding income', () {
      final thisMonthExpense = _expense(200, DateTime(2026, 7, 3));
      final rows = [
        _income(1000, DateTime(2026, 7, 1)), // income excluded
        thisMonthExpense,
        _expense(77, DateTime(2026, 6, 15)), // other month excluded
      ];
      final d =
          DashboardSummary.from(rows, const [], const <Investment>[], july);
      expect(d.monthExpenses, hasLength(1));
      expect(d.monthExpenses.single.txn.amount, 200);
      expect(d.monthExpenses.single.txn.type, TxnType.expense);
    });

    test('external deposits add to the total but not reduce the balance', () {
      final rows = [_income(1000, DateTime(2026, 7, 1))];
      final contributions = [
        _contrib(200, DateTime(2026, 7, 2)), // internal: from income
        _contrib(5000, DateTime(2026, 7, 3), external: true), // pre-existing
      ];
      final d = DashboardSummary.from(
          rows, contributions, const <Investment>[], july);
      // Total saved counts both; balance only subtracts the internal 200.
      expect(d.savingsTotal, 5200);
      expect(d.balance, 1000 - 0 - 200); // 800, external not subtracted
      // This month's split counts only the income-derived deposit.
      expect(d.monthSaved, 200);
      expect(d.monthRemaining, 1000 - 0 - 200);
    });

    test('a withdrawal (negative deposit) returns money to the balance', () {
      final rows = [_income(1000, DateTime(2026, 7, 1))];
      final contributions = [
        _contrib(300, DateTime(2026, 7, 2)), // deposit into savings
        _contrib(-100, DateTime(2026, 7, 20)), // withdraw back to the balance
      ];
      final d = DashboardSummary.from(
          rows, contributions, const <Investment>[], july);
      // Net saved is 200; the withdrawal flows back into the spendable balance.
      expect(d.savingsTotal, 200);
      expect(d.balance, 800); // 1000 - 0 - 200
      expect(d.monthSaved, 200);
      expect(d.monthRemaining, 800);
    });

    test('an external withdrawal leaves savings without entering the balance',
        () {
      // Money taken out of a goal and spent or moved elsewhere directly — the
      // car fund paying for the car, a transfer to an untracked account. The
      // goal must drop; the balance must NOT rise, because the money never
      // arrived in it.
      final rows = [_income(1000, DateTime(2026, 7, 1))];
      final contributions = [
        _contrib(300, DateTime(2026, 7, 2)), // deposited from the balance
        _contrib(-100, DateTime(2026, 7, 20), external: true), // left elsewhere
      ];
      final d = DashboardSummary.from(
          rows, contributions, const <Investment>[], july);

      expect(d.savingsTotal, 200, reason: 'the goal really is 100 lighter');
      expect(d.balance, 700,
          reason: '1000 − 300 deposited; the withdrawal never came back');
      // Unlike a normal withdrawal, it doesn't count as un-saving this cycle.
      expect(d.monthSaved, 300);
    });

    test(
        'a normal and an external withdrawal of the same amount differ only '
        'in the balance', () {
      final rows = [_income(1000, DateTime(2026, 7, 1))];
      final deposit = _contrib(300, DateTime(2026, 7, 2));

      final toBalance = DashboardSummary.from(
          rows,
          [deposit, _contrib(-100, DateTime(2026, 7, 20))],
          const <Investment>[],
          july);
      final elsewhere = DashboardSummary.from(
          rows,
          [deposit, _contrib(-100, DateTime(2026, 7, 20), external: true)],
          const <Investment>[],
          july);

      expect(elsewhere.savingsTotal, toBalance.savingsTotal);
      expect(toBalance.balance - elsewhere.balance, 100,
          reason: 'the 100 lands in the balance in one case only');
    });

    test('non-external investments reduce the balance; standalone ones do not',
        () {
      final rows = [_income(1000, DateTime(2026, 7, 1))];
      final investments = [
        _inv(200), // money moved from the balance into the portfolio
        _inv(5000, external: true), // standalone, pre-existing money
      ];
      final d = DashboardSummary.from(rows, const [], investments, july);
      expect(d.investedTotal, 5200); // both count toward the portfolio
      expect(d.balance, 1000 - 0 - 200); // only the non-external 200 leaves
    });

    group('a deficit carried in from last cycle', () {
      test('is taken out of what this cycle has left', () {
        // Last cycle ended 1,203.58 overdrawn; this cycle's salary lands and
        // 80 is spent. The salary immediately pays off that deficit, so it was
        // never "remaining" — reporting the full 19,339 would claim more money
        // exists than does.
        final rows = [
          _income(19419.00, DateTime(2026, 7, 1)),
          _expense(80.00, DateTime(2026, 7, 2)),
          // Last cycle: spent more than came in.
          _income(19419.00, DateTime(2026, 6, 1)),
          _expense(20622.58, DateTime(2026, 6, 15)),
        ];

        final d =
            DashboardSummary.from(rows, const [], const <Investment>[], july);

        expect(d.balance, closeTo(18135.42, 0.005));
        expect(d.monthRemaining, closeTo(18135.42, 0.005),
            reason: 'capped at the real balance, not 19,339');
        expect(d.monthSpent, 80.00);
      });

      test('never makes remaining exceed the balance', () {
        final rows = [
          _income(1000, DateTime(2026, 7, 1)),
          _expense(2000, DateTime(2026, 6, 10)),
        ];
        final d =
            DashboardSummary.from(rows, const [], const <Investment>[], july);
        expect(d.monthRemaining, lessThanOrEqualTo(d.balance));
      });
    });

    test('a carried-in surplus is not added to this cycle', () {
      // The opposite direction is left alone on purpose: leftover money from
      // previous cycles is real, and «الرصيد» shows it, but it is not this
      // cycle's income and this card splits this cycle's income.
      final rows = [
        _income(5000, DateTime(2026, 5, 1)), // untouched from an older cycle
        _income(1000, DateTime(2026, 7, 1)),
        _expense(200, DateTime(2026, 7, 3)),
      ];
      final d =
          DashboardSummary.from(rows, const [], const <Investment>[], july);

      expect(d.balance, 5800);
      expect(d.monthRemaining, 800, reason: '1000 earned - 200 spent');
    });

    test('no cap before this cycle\'s income has landed', () {
      // Pre-payday, "remaining" is just what has been spent so far. The
      // balance still holds last cycle's leftovers and is a different
      // quantity, so letting it drag this figure would be meaningless.
      final rows = [
        _income(1000, DateTime(2026, 5, 1)),
        _expense(1500, DateTime(2026, 6, 20)), // balance is now -500
        _expense(50, DateTime(2026, 7, 2)), // this cycle, before payday
      ];
      final d =
          DashboardSummary.from(rows, const [], const <Investment>[], july);

      expect(d.incomeReceivedThisMonth, isFalse);
      expect(d.balance, -550);
      expect(d.monthRemaining, -50, reason: 'this cycle only, uncapped');
    });

    test('savings this cycle still reduce what is left', () {
      final rows = [
        _income(1000, DateTime(2026, 7, 1)),
        _expense(200, DateTime(2026, 7, 3)),
      ];
      final d = DashboardSummary.from(rows,
          [_contrib(300, DateTime(2026, 7, 4))], const <Investment>[], july);

      expect(d.monthRemaining, 500);
      expect(d.balance, 500);
    });

    test('empty input yields all zeros and an empty month list', () {
      final d =
          DashboardSummary.from(const [], const [], const <Investment>[], july);
      expect(d.balance, 0);
      expect(d.savingsTotal, 0);
      expect(d.investedTotal, 0);
      expect(d.monthRemaining, 0);
      expect(d.monthSpent, 0);
      expect(d.monthSaved, 0);
      expect(d.monthExpenses, isEmpty);
      expect(d.incomeReceivedThisMonth, isFalse);
    });
  });
}
