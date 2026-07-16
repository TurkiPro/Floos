import '../data/database.dart';
import '../data/enums.dart';
import 'recurrence_math.dart';

/// One day's discretionary spend in one top-level category, for the stacked
/// day-bar chart (and its legend).
class DaySlice {
  final int categoryId; // top-level
  final String name;
  final int colorValue;
  final double amount;
  const DaySlice(this.categoryId, this.name, this.colorValue, this.amount);
}

class DaySpend {
  final DateTime date;
  final List<DaySlice> slices; // biggest first
  const DaySpend(this.date, this.slices);
  double get total => slices.fold(0.0, (s, e) => s + e.amount);
}

/// How one salary-day-anchored week of the current cycle went against the weekly
/// budget. The first week begins on the cycle start (payday); the last week and
/// the in-progress current week are partial, so the budget is pro-rated by the
/// days actually elapsed in the window.
class WeekPerformance {
  final DateTime weekStart; // the cycle-anchored week start
  final DateTime windowEnd; // exclusive, clamped to today/cycle end
  final int index; // 1-based within the cycle
  final double spent; // discretionary (non-recurring) spend in the window
  final double budget; // pro-rated weekly budget for the window's days
  final bool current; // the in-progress week
  final List<DaySpend> days; // per-day discretionary breakdown, full week

  const WeekPerformance({
    required this.weekStart,
    required this.windowEnd,
    required this.index,
    required this.spent,
    required this.budget,
    required this.current,
    required this.days,
  });

  bool get over => spent > budget;
  double get delta => spent - budget; // + over, − under
}

/// Breaks the current cycle [periodStart, periodEnd) into salary-day-anchored
/// 7-day weeks up to today, pairing each with its discretionary spend, a
/// pro-rated slice of [weeklyBudget], and a per-day category breakdown. Recurring
/// obligations are excluded, like the weekly-budget baseline itself.
List<WeekPerformance> weeklyPerformance({
  required List<TxnRow> rows,
  required Map<int, Category> byId,
  required double weeklyBudget,
  required DateTime now,
  required DateTime periodStart,
  required DateTime periodEnd,
}) {
  final today = dateOnly(now);
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  final cycleStart = dateOnly(periodStart);
  final cycleEnd = dateOnly(periodEnd); // exclusive
  final upper = tomorrow.isBefore(cycleEnd) ? tomorrow : cycleEnd;

  final out = <WeekPerformance>[];
  var ws = cycleStart;
  var idx = 1;
  while (ws.isBefore(upper)) {
    final we = DateTime(ws.year, ws.month, ws.day + 7);
    final fullWeekEnd = we.isBefore(cycleEnd) ? we : cycleEnd; // week's own end
    final windowEnd = we.isBefore(upper) ? we : upper; // clamped to today
    final days = windowEnd.difference(ws).inDays;
    final budget = weeklyBudget * days / 7;

    var spent = 0.0;
    // dayKey -> top-category id -> amount, for the days of this week. Grouping by
    // top category (not raw colour) keeps each bar segment one distinct category
    // that the legend can name.
    final byDay = <int, Map<int, double>>{};
    for (final r in rows) {
      if (r.txn.type != TxnType.expense) continue;
      if (r.txn.recurrenceId != null) continue; // exclude obligations
      final d = dateOnly(r.txn.date);
      if (d.isBefore(ws) || !d.isBefore(fullWeekEnd)) continue;
      final dayKey = d.difference(ws).inDays;
      if (d.isBefore(windowEnd)) spent += r.txn.amount;
      final topId = r.category.parentId ?? r.category.id;
      (byDay[dayKey] ??= <int, double>{})[topId] =
          (byDay[dayKey]?[topId] ?? 0) + r.txn.amount;
    }

    // A slot per day of the (full) week, empty ones included so the chart keeps
    // a fixed 7-column shape.
    final weekLen = fullWeekEnd.difference(ws).inDays;
    final daySpends = <DaySpend>[];
    for (var i = 0; i < weekLen; i++) {
      final date = DateTime(ws.year, ws.month, ws.day + i);
      final slices = (byDay[i] ?? const <int, double>{}).entries.map((e) {
        final cat = byId[e.key];
        return DaySlice(
            e.key, cat?.name ?? '—', cat?.colorValue ?? 0xFF9E9E9E, e.value);
      }).toList()
        ..sort((a, b) => b.amount.compareTo(a.amount));
      daySpends.add(DaySpend(date, slices));
    }

    out.add(WeekPerformance(
      weekStart: ws,
      windowEnd: windowEnd,
      index: idx,
      spent: spent,
      budget: budget,
      current: windowEnd == upper && upper == tomorrow,
      days: daySpends,
    ));
    ws = we;
    idx++;
  }
  return out;
}
