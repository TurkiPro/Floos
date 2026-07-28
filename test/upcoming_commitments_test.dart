import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/upcoming_commitments.dart';

RecurrenceRule _rule({
  required int id,
  required double amount,
  required DateTime start,
  DateTime? lastMaterialized,
  DateTime? override,
  bool active = true,
  TxnType type = TxnType.expense,
  Frequency freq = Frequency.monthly,
  int interval = 1,
}) =>
    RecurrenceRule(
      id: id,
      title: 't$id',
      amount: amount,
      categoryId: 1,
      type: type,
      frequency: freq,
      interval: interval,
      startDate: start,
      lastMaterialized: lastMaterialized,
      nextOverrideDate: override,
      active: active,
    );

void main() {
  // Current cycle: today 10 June, next payday 25 June.
  final now = DateTime(2026, 6, 10);
  final end = DateTime(2026, 6, 25);

  group('upcomingCommitments', () {
    test('lists obligations due before the next payday, soonest first', () {
      final rules = [
        // due 15 June (last paid 15 May) -> in range
        _rule(
            id: 1,
            amount: 2875,
            start: DateTime(2026, 1, 15),
            lastMaterialized: DateTime(2026, 5, 15)),
        // already paid this cycle (5 June) -> next is 5 July -> out of range
        _rule(
            id: 2,
            amount: 100,
            start: DateTime(2026, 1, 5),
            lastMaterialized: DateTime(2026, 6, 5)),
        // paused -> excluded
        _rule(
            id: 3,
            amount: 500,
            start: DateTime(2026, 1, 20),
            lastMaterialized: DateTime(2026, 5, 20),
            active: false),
        // due 20 June -> in range
        _rule(
            id: 4,
            amount: 80,
            start: DateTime(2026, 1, 20),
            lastMaterialized: DateTime(2026, 5, 20)),
      ];
      final up = upcomingCommitments(rules, now, end);
      expect(up.map((c) => c.rule.id).toList(), [1, 4]);
      expect(up.map((c) => c.date).toList(),
          [DateTime(2026, 6, 15), DateTime(2026, 6, 20)]);
      expect(upcomingTotal(up), 2955);
    });

    test('honours a next-payday override date', () {
      final rules = [
        _rule(
            id: 5,
            amount: 200,
            start: DateTime(2026, 1, 1),
            lastMaterialized: DateTime(2026, 6, 1),
            override: DateTime(2026, 6, 12)),
      ];
      final up = upcomingCommitments(rules, now, end);
      expect(up.single.date, DateTime(2026, 6, 12));
    });

    test('ignores income rules', () {
      final rules = [
        _rule(
            id: 6,
            amount: 9000,
            start: DateTime(2026, 1, 15),
            lastMaterialized: DateTime(2026, 5, 15),
            type: TxnType.income),
      ];
      expect(upcomingCommitments(rules, now, end), isEmpty);
    });

    test('empty when nothing is due before payday', () {
      expect(upcomingTotal(const []), 0);
    });
  });
}
