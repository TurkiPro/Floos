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

/// A (year, month) pair identifying a calendar month, independent of day.
/// Backs the "browse every month" feature.
class MonthKey {
  final int year;
  final int month;
  const MonthKey({required this.year, required this.month});

  @override
  bool operator ==(Object other) =>
      other is MonthKey && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

/// Every distinct (year, month) present in [dates], newest first.
List<MonthKey> distinctMonthsDesc(List<DateTime> dates) {
  final seen = <MonthKey>{};
  for (final d in dates) {
    seen.add(MonthKey(year: d.year, month: d.month));
  }
  final list = seen.toList()
    ..sort((a, b) =>
        a.year != b.year ? b.year - a.year : b.month - a.month);
  return list;
}

const _arabicMonthNames = [
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

/// Arabic month name + year, e.g. "يوليو 2026". Hardcoded rather than a
/// locale-tagged `DateFormat` for the same reason as [dayLabel] above: the app
/// never calls `initializeDateFormatting('ar')`.
String monthLabel(MonthKey key) {
  return '${_arabicMonthNames[key.month - 1]} ${key.year}';
}

// DateTime.weekday is 1 = Monday … 7 = Sunday.
const _arabicDayNames = [
  'الإثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];

/// Arabic weekday name, e.g. "الجمعة".
String dayName(DateTime day) => _arabicDayNames[day.weekday - 1];

/// Arabic weekday name from a raw `DateTime.weekday` value (1 = Monday).
String dayNameForWeekday(int weekday) => _arabicDayNames[weekday - 1];

/// Weekday + day-of-month + Arabic month, prefixed with اليوم/أمس when it
/// applies, e.g. "اليوم • الجمعة، 3 يوليو" or "الأربعاء، 1 يوليو".
String dayFullLabel(DateTime day, {required DateTime today}) {
  final d = DateTime(day.year, day.month, day.day);
  final t = DateTime(today.year, today.month, today.day);
  final diff = t.difference(d).inDays;
  final base = '${dayName(d)}، ${d.day} ${_arabicMonthNames[d.month - 1]}';
  if (diff == 0) return 'اليوم • $base';
  if (diff == 1) return 'أمس • $base';
  return base;
}
