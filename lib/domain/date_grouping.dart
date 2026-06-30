import 'package:intl/intl.dart';

/// Arabic relative-day label: today/yesterday, or a formatted date for
/// anything older. Pure function of two DateTimes so it's unit-testable
/// without mocking DateTime.now() in the caller.
///
/// No explicit locale is passed to DateFormat here, matching the existing
/// `DateFormat('d MMM')` call in home_screen.dart -- the app never calls
/// `initializeDateFormatting('ar')`, so a locale-tagged DateFormat would
/// throw at the first date older than yesterday.
String dayLabel(DateTime day, {required DateTime today}) {
  final d = DateTime(day.year, day.month, day.day);
  final t = DateTime(today.year, today.month, today.day);
  final diff = t.difference(d).inDays;
  if (diff == 0) return 'اليوم';
  if (diff == 1) return 'أمس';
  return DateFormat('d MMM').format(d);
}

/// Groups items into day buckets, preserving the incoming order within and
/// across buckets. Generic over T via a date selector so this stays
/// dependency-free of the data layer (mirrors recurrence_math.dart's
/// purity). Relies on the caller's list already being sorted by date
/// descending (true of TransactionDao.watchRecent()) -- insertion order
/// into the backing map then equals day-descending order, so no extra sort
/// happens here.
List<MapEntry<DateTime, List<T>>> groupByDay<T>(
  List<T> items,
  DateTime Function(T) dateOf,
) {
  final out = <DateTime, List<T>>{};
  for (final item in items) {
    final d = dateOf(item);
    final key = DateTime(d.year, d.month, d.day);
    out.putIfAbsent(key, () => []).add(item);
  }
  return out.entries.toList();
}
