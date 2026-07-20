import '../data/database.dart';

/// A movement of money between the current balance and a savings goal or an
/// investment. The balance page shows these so a drop/rise in the balance —
/// besides income and spending — is explained by where the money went (or came
/// from). [amount] is signed from the BALANCE's point of view: money put into
/// savings/investments is negative (it left the balance); a withdrawal/sell is
/// positive (it came back). Standalone (external) savings/investment entries
/// never touched the balance, so they're excluded.
class BalanceTransfer {
  final DateTime date;
  final double amount; // balance view: negative = out, positive = back in
  final String label; // e.g. "إلى الادخار: سيارة جديدة"
  final bool savings; // savings (true) vs investment (false), for the icon
  const BalanceTransfer({
    required this.date,
    required this.amount,
    required this.label,
    required this.savings,
  });
}

/// Builds the balance-affecting transfers (newest first) from savings
/// contributions and investments. External entries are excluded — they never
/// moved money in or out of the balance.
List<BalanceTransfer> balanceTransfers({
  required List<SavingsContribution> contributions,
  required List<Investment> investments,
  required Map<int, String> goalNames,
}) {
  final out = <BalanceTransfer>[];
  for (final c in contributions) {
    if (c.external) continue;
    final name = goalNames[c.goalId] ?? 'الادخار';
    out.add(BalanceTransfer(
      date: c.date,
      // A deposit (c.amount > 0) took money OUT of the balance.
      amount: -c.amount,
      label: c.amount < 0 ? 'من الادخار: $name' : 'إلى الادخار: $name',
      savings: true,
    ));
  }
  for (final inv in investments) {
    if (inv.external) continue;
    out.add(BalanceTransfer(
      date: inv.date,
      amount: -inv.amount,
      label: inv.amount < 0
          ? 'من الاستثمار: ${inv.name}'
          : 'إلى الاستثمار: ${inv.name}',
      savings: false,
    ));
  }
  out.sort((a, b) => b.date.compareTo(a.date));
  return out;
}
