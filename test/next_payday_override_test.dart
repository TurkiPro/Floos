import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/recurrence_engine.dart';

/// The one-shot next-payday override: a single occurrence's date is shifted
/// (salary a day or two early/late) without changing the recurring schedule,
/// and the engine must never drop or double-create the occurrence.
void main() {
  Future<int> monthlyIncome(AppDatabase db) async {
    final id = await db.recurrenceDao.add(
      title: 'راتب',
      amount: 9000,
      categoryId: 1,
      type: TxnType.income,
      frequency: Frequency.monthly,
      startDate: DateTime(2026, 7, 15),
    );
    // Pretend July already materialized, so August is the next occurrence.
    await db.recurrenceDao.setLastMaterialized(id, DateTime(2026, 7, 15));
    return id;
  }

  Future<List<DateTime>> genDates(AppDatabase db) async {
    final rows = await db.select(db.transactions).get();
    final dates = rows.map((t) => t.date).toList()..sort();
    return dates;
  }

  test('delayed payday: materializes on the override date, once', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final id = await monthlyIncome(db);

    // August 15th salary delayed to the 18th.
    await db.recurrenceDao.setNextPaydayOverride(
        id, DateTime(2026, 8, 15), DateTime(2026, 8, 18));

    // On the 16th (past the scheduled day, before the delayed day): nothing yet.
    await RecurrenceEngine(db).catchUp(asOf: DateTime(2026, 8, 16));
    expect(await genDates(db), isEmpty);
    expect((await db.recurrenceDao.activeRules()).single.nextOverrideDate,
        isNotNull);

    // On the 18th: created, dated the 18th, and the override is consumed.
    await RecurrenceEngine(db).catchUp(asOf: DateTime(2026, 8, 18));
    expect(await genDates(db), [DateTime(2026, 8, 18)]);
    expect(
        (await db.recurrenceDao.activeRules()).single.nextOverrideDate, isNull);

    // September rolls on normally — no duplicate August 15th.
    await RecurrenceEngine(db).catchUp(asOf: DateTime(2026, 9, 20));
    expect(await genDates(db), [DateTime(2026, 8, 18), DateTime(2026, 9, 15)]);
  });

  test('early payday: materializes early, no scheduled duplicate later',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final id = await monthlyIncome(db);

    // August 15th salary arrives early, on the 13th.
    await db.recurrenceDao.setNextPaydayOverride(
        id, DateTime(2026, 8, 15), DateTime(2026, 8, 13));

    await RecurrenceEngine(db).catchUp(asOf: DateTime(2026, 8, 13));
    expect(await genDates(db), [DateTime(2026, 8, 13)]);
    final rule = (await db.recurrenceDao.activeRules()).single;
    expect(rule.nextOverrideDate, isNull, reason: 'override consumed');
    expect(rule.lastMaterialized, DateTime(2026, 8, 15),
        reason: 'marker sits at the scheduled slot so it can\'t recreate it');
    expect(rule.lastPaidDate, DateTime(2026, 8, 13),
        reason: 'the period anchors to the actual early payday, not the slot');

    // The scheduled 15th must NOT produce a second August salary.
    await RecurrenceEngine(db).catchUp(asOf: DateTime(2026, 8, 20));
    expect(await genDates(db), [DateTime(2026, 8, 13)]);

    // September still lands normally.
    await RecurrenceEngine(db).catchUp(asOf: DateTime(2026, 9, 20));
    expect(await genDates(db), [DateTime(2026, 8, 13), DateTime(2026, 9, 15)]);
  });

  test('no override behaves exactly as before', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await monthlyIncome(db);

    await RecurrenceEngine(db).catchUp(asOf: DateTime(2026, 9, 20));
    expect(await genDates(db), [DateTime(2026, 8, 15), DateTime(2026, 9, 15)]);
    // With no override, the actual paid date equals the scheduled slot.
    final rule = (await db.recurrenceDao.activeRules()).single;
    expect(rule.lastPaidDate, DateTime(2026, 9, 15));
    expect(rule.lastMaterialized, DateTime(2026, 9, 15));
  });
}
