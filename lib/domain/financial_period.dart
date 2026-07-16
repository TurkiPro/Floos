import '../data/database.dart';
import '../data/enums.dart';
import 'recurrence_math.dart';

/// The current financial period — salary-day to salary-day — anchored on the
/// largest active recurring income. The home dashboard's "this month" figures
/// use this instead of the calendar month, so the salary you were just paid
/// counts toward the period you're actually living in (and an obligation dated
/// late last month falls inside it). Falls back to the calendar month when
/// there is no recurring income yet, or it hasn't started.
class FinancialPeriod {
  final DateTime start; // inclusive
  final DateTime end; // exclusive
  const FinancialPeriod(this.start, this.end);

  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);
}

FinancialPeriod financialPeriod(
    List<RecurrenceRule> incomeRules, DateTime now) {
  final today = dateOnly(now);
  final calendar = FinancialPeriod(
    DateTime(now.year, now.month, 1),
    DateTime(now.year, now.month + 1, 1),
  );

  // The "salary": the largest active recurring income defines the cycle.
  RecurrenceRule? salary;
  for (final r in incomeRules) {
    if (r.type != TxnType.income || !r.active) continue;
    if (salary == null || r.amount > salary.amount) salary = r;
  }
  if (salary == null) return calendar;

  final start = _latestOnOrBefore(salary, today);
  if (start == null) return calendar; // the salary rule hasn't started yet

  final end = nextOccurrence(
        startDate: salary.startDate,
        frequency: salary.frequency,
        interval: salary.interval,
        endDate: salary.endDate,
        afterExclusive: today,
      ) ??
      // The salary rule has ended — cap a month out from the last payday.
      DateTime(start.year, start.month + 1, start.day);
  return FinancialPeriod(start, end);
}

/// The latest occurrence of [rule] on or before [cap], or null if the rule
/// starts after [cap].
DateTime? _latestOnOrBefore(RecurrenceRule rule, DateTime cap) {
  final base = dateOnly(rule.startDate);
  if (base.isAfter(cap)) return null;
  final end = rule.endDate == null ? null : dateOnly(rule.endDate!);
  DateTime? last;
  const safety = 100000;
  for (var n = 0; n < safety; n++) {
    final o = occurrence(
        freq: rule.frequency, interval: rule.interval, base: base, n: n);
    if (o.isAfter(cap)) break;
    if (end != null && o.isAfter(end)) break;
    last = o;
  }
  return last;
}
