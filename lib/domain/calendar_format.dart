import 'package:hijri/hijri_calendar.dart';

import 'date_grouping.dart';
import 'financial_period.dart';

// Hardcoded like the Gregorian names in date_grouping.dart -- the app never
// initialises ICU date formatting, so no locale-tagged formatter is used.
const _hijriMonths = [
  'محرم',
  'صفر',
  'ربيع الأول',
  'ربيع الآخر',
  'جمادى الأولى',
  'جمادى الآخرة',
  'رجب',
  'شعبان',
  'رمضان',
  'شوال',
  'ذو القعدة',
  'ذو الحجة',
];

/// Month + year in the selected calendar, e.g. "يوليو 2026" or "محرم 1448هـ".
String monthLabelFor(MonthKey key, {required bool hijri}) {
  if (!hijri) return monthLabel(key);
  final h = HijriCalendar.fromDate(DateTime(key.year, key.month, 15));
  return '${_hijriMonths[h.hMonth - 1]} ${h.hYear}هـ';
}

/// Weekday + date in the selected calendar, keeping the اليوم/أمس prefix.
/// Gregorian: "اليوم • الإثنين، 13 يوليو".
/// Hijri:     "اليوم • الإثنين، 27 ذو الحجة".
String dayFullLabelFor(
  DateTime day, {
  required DateTime today,
  required bool hijri,
}) {
  if (!hijri) return dayFullLabel(day, today: today);

  final d = DateTime(day.year, day.month, day.day);
  // UTC midnights for the day-difference so a DST day can't truncate inDays.
  final diff = DateTime.utc(today.year, today.month, today.day)
      .difference(DateTime.utc(day.year, day.month, day.day))
      .inDays;
  final h = HijriCalendar.fromDate(d);
  final base = '${dayName(d)}، ${h.hDay} ${_hijriMonths[h.hMonth - 1]}';
  if (diff == 0) return 'اليوم • $base';
  if (diff == 1) return 'أمس • $base';
  return base;
}

/// Day + month name in the selected calendar, e.g. "27 يوليو" / "27 ذو الحجة".
String dayMonthFor(DateTime date, {required bool hijri}) {
  if (!hijri) return '${date.day} ${gregorianMonthName(date.month)}';
  final h = HijriCalendar.fromDate(date);
  return '${h.hDay} ${_hijriMonths[h.hMonth - 1]}';
}

/// A salary cycle's label. When the cycle lines up with a whole calendar month
/// (starts on the 1st, ends on the 1st of the next), it's just the month name —
/// no confusion. Otherwise it's the inclusive date range, e.g.
/// "27 يوليو – 27 أغسطس 2026", so a cycle that straddles two months reads
/// unambiguously.
String cycleLabelFor(FinancialPeriod period, {required bool hijri}) {
  final start =
      DateTime(period.start.year, period.start.month, period.start.day);
  final end = DateTime(period.end.year, period.end.month, period.end.day);
  final nextMonth = DateTime(start.year, start.month + 1, 1);
  if (start.day == 1 && end == nextMonth) {
    return monthLabelFor(MonthKey(year: start.year, month: start.month),
        hijri: hijri);
  }
  final lastDay = end.subtract(const Duration(days: 1));
  final year = hijri ? HijriCalendar.fromDate(lastDay).hYear : lastDay.year;
  final suffix = hijri ? 'هـ' : '';
  return '${dayMonthFor(start, hijri: hijri)} – '
      '${dayMonthFor(lastDay, hijri: hijri)} $year$suffix';
}

/// Short date in the selected calendar, e.g. "2026-08-01" or "1448-02-27هـ".
String shortDateFor(DateTime date, {required bool hijri}) {
  if (!hijri) {
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '${date.year}-$m-$d';
  }
  final h = HijriCalendar.fromDate(date);
  final m = h.hMonth.toString().padLeft(2, '0');
  final d = h.hDay.toString().padLeft(2, '0');
  return '${h.hYear}-$m-$dهـ';
}
