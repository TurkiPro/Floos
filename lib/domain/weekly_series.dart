import '../data/database.dart';
import '../data/enums.dart';
import 'recurrence_math.dart';

/// Total spend in one Saturday-aligned week, for the weekly bar chart.
class WeekTotal {
  final DateTime weekStart;
  final double total;
  const WeekTotal(this.weekStart, this.total);
}

/// Total expense spend per week for the last [weeks] weeks, oldest → newest,
/// ending with the week that starts at [anchorWeekStart] (the salary-day-anchored
/// current week). Every expense counts (recurring included) — this is the "how
/// much did I spend each week" rhythm, not the discretionary budget line.
List<WeekTotal> weeklySpendSeries({
  required List<TxnRow> rows,
  required DateTime anchorWeekStart,
  int weeks = 12,
}) {
  final thisWeek = dateOnly(anchorWeekStart);
  final firstWeek =
      DateTime(thisWeek.year, thisWeek.month, thisWeek.day - 7 * (weeks - 1));
  final totals = List<double>.filled(weeks, 0);
  for (final r in rows) {
    if (r.txn.type != TxnType.expense) continue;
    final d = dateOnly(r.txn.date);
    if (d.isBefore(firstWeek)) continue;
    final idx = d.difference(firstWeek).inDays ~/ 7;
    if (idx < 0 || idx >= weeks) continue;
    totals[idx] += r.txn.amount;
  }
  return [
    for (var i = 0; i < weeks; i++)
      WeekTotal(
        DateTime(firstWeek.year, firstWeek.month, firstWeek.day + 7 * i),
        totals[i],
      ),
  ];
}
