import '../data/database.dart';
import '../data/enums.dart';
import 'recurrence_math.dart';

/// One recurring obligation due before the next payday: the [rule] and the [date]
/// its next charge lands.
class UpcomingCommitment {
  final RecurrenceRule rule;
  final DateTime date;
  const UpcomingCommitment(this.rule, this.date);
}

/// The active recurring EXPENSE obligations whose next occurrence falls on or
/// after today and before [cycleEnd] (the next payday) — what's still due to
/// leave the account this cycle, soonest first. Override-aware, mirroring the
/// obligations screen's own next-date logic. An obligation already materialised
/// this cycle has its next occurrence in the *following* cycle, so it correctly
/// drops out. Only the next single occurrence per rule is considered, which is
/// exact for monthly obligations (a sub-monthly rule shows just its soonest).
List<UpcomingCommitment> upcomingCommitments(
  List<RecurrenceRule> expenseRules,
  DateTime now,
  DateTime cycleEnd,
) {
  final today = dateOnly(now);
  final end = dateOnly(cycleEnd);
  final out = <UpcomingCommitment>[];
  for (final r in expenseRules) {
    if (r.type != TxnType.expense || !r.active) continue;
    final next = r.nextOverrideDate != null
        ? dateOnly(r.nextOverrideDate!)
        : nextOccurrence(
            startDate: r.startDate,
            frequency: r.frequency,
            interval: r.interval,
            endDate: r.endDate,
            afterExclusive: r.lastMaterialized ??
                dateOnly(r.startDate).subtract(const Duration(days: 1)),
          );
    if (next == null) continue;
    final d = dateOnly(next);
    if (d.isBefore(today) || !d.isBefore(end)) continue;
    out.add(UpcomingCommitment(r, d));
  }
  out.sort((a, b) => a.date.compareTo(b.date));
  return out;
}

/// The total amount due across [items] — what's about to leave the account.
double upcomingTotal(List<UpcomingCommitment> items) =>
    items.fold(0, (sum, c) => sum + c.rule.amount);
