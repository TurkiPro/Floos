import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/dashboard_summary.dart';
import 'package:floos/domain/financial_period.dart';
import 'package:floos/domain/ledger_balance.dart';

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

SavingsContribution _save(double amount, DateTime date,
        {bool external = false, bool planned = false}) =>
    SavingsContribution(
        id: 1,
        goalId: 1,
        amount: amount,
        date: date,
        external: external,
        planned: planned);

Investment _invest(double amount, DateTime date, {bool external = false}) =>
    Investment(
        id: 1, name: 'x', amount: amount, date: date, external: external);

/// Every kind of entry the balance knows about, so the formula is pinned in
/// one place.
final _ledger = LedgerInputs(
  rows: [
    _txn(TxnType.income, 10000, DateTime(2026, 7, 1)),
    _txn(TxnType.expense, 1200, DateTime(2026, 7, 5)),
    _txn(TxnType.expense, 300, DateTime(2026, 7, 13)), // the week of the 13th
    _txn(TxnType.income, 500, DateTime(2026, 7, 14)), // income this week
  ],
  contributions: [
    _save(1000, DateTime(2026, 7, 2)),
    _save(5000, DateTime(2026, 7, 3), external: true), // never in the balance
    _save(-200, DateTime(2026, 7, 10), planned: true), // back to the balance
    _save(-700, DateTime(2026, 7, 11), external: true), // taken out elsewhere
  ],
  investments: [
    _invest(2000, DateTime(2026, 7, 4)),
    _invest(9000, DateTime(2026, 7, 4), external: true),
  ],
  debts: const [],
);

void main() {
  test('balance = income − spending − internal savings − internal investments',
      () {
    final t = ledgerTotals(_ledger);
    expect(t.inflows, 10500);
    // 1200 + 300 spent, 1000 − 200 saved, 2000 invested.
    expect(t.outflows, 4300);
    expect(t.balance, 6200);
  });

  test('"before" excludes an entry dated on the day itself', () {
    final t = ledgerTotals(_ledger, before: DateTime(2026, 7, 13));
    expect(t.outflows, 4000, reason: 'the 300 on the 13th is not before it');
    expect(t.inflows, 10000);
  });

  test('the week-start balance freezes outflows but not income', () {
    // Outflows before the 13th (4000), all income so far (10500).
    expect(balanceAtWeekStart(_ledger, DateTime(2026, 7, 13)), 6500);
  });

  test('the home card reports exactly this balance', () {
    final summary = DashboardSummary.from(
      _ledger.rows,
      _ledger.contributions,
      _ledger.investments,
      FinancialPeriod(DateTime(2026, 7, 1), DateTime(2026, 8, 1)),
      debts: const [],
    );
    expect(summary.balance, ledgerTotals(_ledger).balance);
  });
}
