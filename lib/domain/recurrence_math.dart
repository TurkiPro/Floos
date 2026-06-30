import '../data/enums.dart';

/// Strips the time component; all recurrence math works on whole dates.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Adds [months] to [base], clamping the day to the target month's length
/// (Jan 31 + 1 month -> Feb 28/29). Always measured from [base], so a
/// long-running monthly rule never drifts off its anchor day.
DateTime addMonths(DateTime base, int months) {
  final total = (base.month - 1) + months;
  final year = base.year + (total ~/ 12);
  final month = (total % 12) + 1;
  final dim = _daysInMonth(year, month);
  final day = base.day <= dim ? base.day : dim;
  return DateTime(year, month, day);
}

/// Adds [years] to [base], clamping Feb 29 -> Feb 28 in non-leap years.
DateTime addYears(DateTime base, int years) {
  final year = base.year + years;
  final dim = _daysInMonth(year, base.month);
  final day = base.day <= dim ? base.day : dim;
  return DateTime(year, base.month, day);
}

/// The nth occurrence (n = 0 is the first) of a rule anchored at [base].
/// Uses DateTime constructor arithmetic throughout so it is DST-safe.
DateTime occurrence({
  required Frequency freq,
  required int interval,
  required DateTime base,
  required int n,
}) {
  final step = interval < 1 ? 1 : interval;
  switch (freq) {
    case Frequency.daily:
      return DateTime(base.year, base.month, base.day + step * n);
    case Frequency.weekly:
      return DateTime(base.year, base.month, base.day + 7 * step * n);
    case Frequency.monthly:
      return addMonths(base, step * n);
    case Frequency.yearly:
      return addYears(base, step * n);
  }
}

/// All occurrence dates in (`lastMaterialized`, `until`], or [start, until] when
/// `lastMaterialized` is null.
///
/// This is the core of the whole design. Instead of relying on a background task
/// to *create* rows on a schedule — which iOS suspension and Android Doze will
/// silently drop — we evaluate the rule lazily and deterministically every time
/// the app runs. Advancing the marker past `last` makes repeated calls idempotent,
/// so nothing is ever double-created and nothing is ever missed.
List<DateTime> occurrencesBetween({
  required DateTime startDate,
  required Frequency frequency,
  int interval = 1,
  DateTime? endDate,
  DateTime? lastMaterialized,
  required DateTime until,
}) {
  final base = dateOnly(startDate);
  final end = endDate == null ? null : dateOnly(endDate);
  final last = lastMaterialized == null ? null : dateOnly(lastMaterialized);
  final cap = dateOnly(until);

  final out = <DateTime>[];
  const safety = 100000; // guard against a pathological/misconfigured rule
  for (var n = 0; n < safety; n++) {
    final o = occurrence(freq: frequency, interval: interval, base: base, n: n);
    if (o.isAfter(cap)) break;
    if (end != null && o.isAfter(end)) break;
    if (last == null || o.isAfter(last)) out.add(o);
  }
  return out;
}

/// The first occurrence strictly after [afterExclusive] (respecting [endDate]),
/// or null if there are no more. Handy for "next due" labels in the UI.
DateTime? nextOccurrence({
  required DateTime startDate,
  required Frequency frequency,
  int interval = 1,
  DateTime? endDate,
  required DateTime afterExclusive,
}) {
  final base = dateOnly(startDate);
  final end = endDate == null ? null : dateOnly(endDate);
  final after = dateOnly(afterExclusive);
  const safety = 100000;
  for (var n = 0; n < safety; n++) {
    final o = occurrence(freq: frequency, interval: interval, base: base, n: n);
    if (end != null && o.isAfter(end)) return null;
    if (o.isAfter(after)) return o;
  }
  return null;
}
