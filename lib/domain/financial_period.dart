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

  final salary = _largestActiveIncome(incomeRules);
  if (salary == null) return calendar;

  final start = _latestOnOrBefore(salary, today);
  if (start == null) return calendar; // the salary rule hasn't started yet

  final scheduledEnd = nextOccurrence(
        startDate: salary.startDate,
        frequency: salary.frequency,
        interval: salary.interval,
        endDate: salary.endDate,
        afterExclusive: today,
      ) ??
      // The salary rule has ended — cap a month out from the last payday.
      DateTime(start.year, start.month + 1, start.day);
  // A pending next-payday override moves the actual next payday (the salary
  // landing early or late), so the period ends on it — matching the home
  // countdown and the weekly-budget days, which also honour the override.
  final override = salary.nextOverrideDate == null
      ? null
      : dateOnly(salary.nextOverrideDate!);
  final end =
      (override != null && override.isAfter(today)) ? override : scheduledEnd;
  return FinancialPeriod(start, end);
}

/// The "salary": the largest active recurring income, which anchors the cycle.
RecurrenceRule? _largestActiveIncome(List<RecurrenceRule> incomeRules) {
  RecurrenceRule? salary;
  for (final r in incomeRules) {
    if (r.type != TxnType.income || !r.active) continue;
    if (salary == null || r.amount > salary.amount) salary = r;
  }
  return salary;
}

/// When the salary next lands — the same date the financial period ends —
/// honouring a pending next-payday override. Today counts (opening the app on
/// payday still reads as "today"). Null when there's no recurring income, so the
/// home countdown and every "days until salary" figure agree with the cycle.
DateTime? nextSalaryDate(List<RecurrenceRule> incomeRules, DateTime now) {
  final salary = _largestActiveIncome(incomeRules);
  if (salary == null) return null;
  final today = dateOnly(now);
  if (salary.nextOverrideDate != null) {
    final o = dateOnly(salary.nextOverrideDate!);
    if (!o.isBefore(today)) return o; // an upcoming (or today's) override
  }
  return nextOccurrence(
    startDate: salary.startDate,
    frequency: salary.frequency,
    interval: salary.interval,
    endDate: salary.endDate,
    // Exclusive of yesterday => an occurrence dated today still counts.
    afterExclusive: DateTime(today.year, today.month, today.day - 1),
  );
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
