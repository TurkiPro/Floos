import 'package:hijri/hijri_calendar.dart';

import 'date_grouping.dart';

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
  final t = DateTime(today.year, today.month, today.day);
  final diff = t.difference(d).inDays;
  final h = HijriCalendar.fromDate(d);
  final base = '${dayName(d)}، ${h.hDay} ${_hijriMonths[h.hMonth - 1]}';
  if (diff == 0) return 'اليوم • $base';
  if (diff == 1) return 'أمس • $base';
  return base;
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
