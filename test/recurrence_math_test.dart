import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/recurrence_math.dart';

void main() {
  group('addMonths', () {
    test('clamps day 31 to shorter months', () {
      expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(addMonths(DateTime(2026, 1, 31), 3), DateTime(2026, 4, 30));
    });

    test('measures from the anchor so it never drifts', () {
      // Jan 31 -> Feb (clamped 28) -> but +2 from Jan is March 31, not 28.
      expect(addMonths(DateTime(2026, 1, 31), 2), DateTime(2026, 3, 31));
    });

    test('rolls over the year boundary', () {
      expect(addMonths(DateTime(2026, 11, 15), 3), DateTime(2027, 2, 15));
    });
  });

  group('addYears', () {
    test('clamps Feb 29 to Feb 28 in non-leap years', () {
      expect(addYears(DateTime(2024, 2, 29), 1), DateTime(2025, 2, 28));
    });

    test('keeps Feb 29 on the next leap year', () {
      expect(addYears(DateTime(2024, 2, 29), 4), DateTime(2028, 2, 29));
    });
  });

  group('occurrencesBetween', () {
    test('monthly generates one row per month within range', () {
      final out = occurrencesBetween(
        startDate: DateTime(2026, 1, 15),
        frequency: Frequency.monthly,
        until: DateTime(2026, 4, 20),
      );
      expect(out, [
        DateTime(2026, 1, 15),
        DateTime(2026, 2, 15),
        DateTime(2026, 3, 15),
        DateTime(2026, 4, 15),
      ]);
    });

    test('weekly respects interval (bi-weekly)', () {
      final out = occurrencesBetween(
        startDate: DateTime(2026, 1, 1),
        frequency: Frequency.weekly,
        interval: 2,
        until: DateTime(2026, 1, 31),
      );
      expect(out, [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 15),
        DateTime(2026, 1, 29),
      ]);
    });

    test('endDate is inclusive and caps the series', () {
      final out = occurrencesBetween(
        startDate: DateTime(2026, 1, 1),
        frequency: Frequency.daily,
        endDate: DateTime(2026, 1, 3),
        until: DateTime(2026, 12, 31),
      );
      expect(out, [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 2),
        DateTime(2026, 1, 3),
      ]);
    });

    test('nothing is produced before the start date', () {
      final out = occurrencesBetween(
        startDate: DateTime(2026, 6, 1),
        frequency: Frequency.monthly,
        until: DateTime(2026, 3, 1),
      );
      expect(out, isEmpty);
    });

    test('lastMaterialized excludes already-created occurrences', () {
      final out = occurrencesBetween(
        startDate: DateTime(2026, 1, 15),
        frequency: Frequency.monthly,
        lastMaterialized: DateTime(2026, 2, 15),
        until: DateTime(2026, 4, 20),
      );
      expect(out, [DateTime(2026, 3, 15), DateTime(2026, 4, 15)]);
    });

    test('is idempotent: advancing the marker yields no duplicates', () {
      const freq = Frequency.monthly;
      final start = DateTime(2026, 1, 10);

      // First pass through March.
      final pass1 = occurrencesBetween(
        startDate: start,
        frequency: freq,
        until: DateTime(2026, 3, 31),
      );
      // Marker advances to the last one produced.
      final marker = pass1.last;
      // Second pass a month later should only add April, never repeat.
      final pass2 = occurrencesBetween(
        startDate: start,
        frequency: freq,
        lastMaterialized: marker,
        until: DateTime(2026, 4, 30),
      );
      expect(pass1, [
        DateTime(2026, 1, 10),
        DateTime(2026, 2, 10),
        DateTime(2026, 3, 10),
      ]);
      expect(pass2, [DateTime(2026, 4, 10)]);
      expect(pass1.toSet().intersection(pass2.toSet()), isEmpty);
    });

    test('monthly day-31 rule clamps each short month independently', () {
      final out = occurrencesBetween(
        startDate: DateTime(2026, 1, 31),
        frequency: Frequency.monthly,
        until: DateTime(2026, 4, 30),
      );
      expect(out, [
        DateTime(2026, 1, 31),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 31),
        DateTime(2026, 4, 30),
      ]);
    });
  });

  group('nextOccurrence', () {
    test('returns the first occurrence strictly after the given date', () {
      final next = nextOccurrence(
        startDate: DateTime(2026, 1, 15),
        frequency: Frequency.monthly,
        afterExclusive: DateTime(2026, 2, 15),
      );
      expect(next, DateTime(2026, 3, 15));
    });

    test('returns null once past the end date', () {
      final next = nextOccurrence(
        startDate: DateTime(2026, 1, 1),
        frequency: Frequency.monthly,
        endDate: DateTime(2026, 3, 1),
        afterExclusive: DateTime(2026, 3, 1),
      );
      expect(next, isNull);
    });
  });
}
