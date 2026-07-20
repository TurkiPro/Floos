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
        id: 1, goalId: 1, amount: amount, date: date, external: external);

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
