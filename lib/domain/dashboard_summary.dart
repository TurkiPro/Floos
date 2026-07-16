import '../data/database.dart'; // TxnRow, SavingsContribution
import '../data/enums.dart'; // TxnType

/// Everything the home dashboard shows, computed once from the two streams.
/// [balance] is money neither spent nor set aside: all income − all expenses
/// − all savings. The monthly figures split this month's income into what's
/// left, what was spent, and what was saved.
class DashboardSummary {
  final double balance;
  final double savingsTotal;
  final double monthRemaining;
  final double monthSpent;
  final double monthSaved;
  final List<TxnRow> monthExpenses;
  // Whether any income landed this month -- the trigger for the savings prompt.
  final bool incomeReceivedThisMonth;

  const DashboardSummary({
    required this.balance,
    required this.savingsTotal,
    required this.monthRemaining,
    required this.monthSpent,
    required this.monthSaved,
    required this.monthExpenses,
    required this.incomeReceivedThisMonth,
  });

  factory DashboardSummary.from(
    List<TxnRow> rows,
    List<SavingsContribution> contributions,
    DateTime now,
  ) {
    bool inMonth(DateTime d) => d.year == now.year && d.month == now.month;

    double allIncome = 0, allExpense = 0, monthIncome = 0, monthSpent = 0;
    var incomeThisMonth = false;
    final monthExpenses = <TxnRow>[];
    for (final r in rows) {
      final amount = r.txn.amount;
      if (r.txn.type == TxnType.income) {
        allIncome += amount;
        if (inMonth(r.txn.date)) {
          monthIncome += amount;
          incomeThisMonth = true;
        }
      } else {
        allExpense += amount;
        if (inMonth(r.txn.date)) {
          monthSpent += amount;
          monthExpenses.add(r);
        }
      }
    }

    // External deposits (money that already existed) count toward the total
    // saved but never reduce the balance or this month's income split.
    double allSaved = 0, internalSaved = 0, monthSaved = 0;
    for (final c in contributions) {
      allSaved += c.amount;
      if (c.external) continue;
      internalSaved += c.amount;
      if (inMonth(c.date)) monthSaved += c.amount;
    }

    return DashboardSummary(
      balance: allIncome - allExpense - internalSaved,
      savingsTotal: allSaved,
      monthRemaining: monthIncome - monthSpent - monthSaved,
      monthSpent: monthSpent,
      monthSaved: monthSaved,
      monthExpenses: monthExpenses,
      incomeReceivedThisMonth: incomeThisMonth,
    );
  }
}
