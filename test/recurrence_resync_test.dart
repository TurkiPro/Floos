import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/recurrence_engine.dart';

/// resync heals a rule whose "last generated" marker drifted ahead of an
/// occurrence that was never actually created (the reported obligation bug),
/// and it never duplicates an occurrence that already exists.
void main() {
  final asOf = DateTime(2026, 7, 16);

  Future<int> monthlyObligation(AppDatabase db, DateTime start) =>
      db.recurrenceDao.add(
        title: 'إيجار',
        amount: 2000,
        categoryId: 1,
        type: TxnType.expense,
        frequency: Frequency.monthly,
        startDate: start,
      );

  test('backfills a missing occurrence a drifted marker skipped', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final id = await monthlyObligation(db, DateTime(2026, 6, 26));
    // Reproduce the bug: marker reset to today, nothing generated for June 26.
    await db.recurrenceDao.setLastMaterialized(id, asOf);
    expect(await db.transactionDao.watchRecent().first, isEmpty);

    final created = await RecurrenceEngine(db).resync(id, asOf: asOf);

    expect(created, 1);
    final txns = await db.transactionDao.watchRecent().first;
    expect(txns.single.txn.date, DateTime(2026, 6, 26));
  });

  test('never duplicates an occurrence that already exists', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final id = await monthlyObligation(db, DateTime(2026, 6, 26));
    final rule =
        (await db.recurrenceDao.activeRules()).firstWhere((r) => r.id == id);
    await db.transactionDao.insertGenerated(rule, DateTime(2026, 6, 26));

    final created = await RecurrenceEngine(db).resync(id, asOf: asOf);

    expect(created, 0, reason: 'June 26 is already there');
    expect((await db.transactionDao.watchRecent().first).length, 1);
  });

  test('backfills every missing month from an older start', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // Started three months back; nothing generated yet.
    final id = await monthlyObligation(db, DateTime(2026, 4, 26));
    final created = await RecurrenceEngine(db).resync(id, asOf: asOf);

    // Apr 26, May 26, Jun 26 (Jul 26 is after asOf).
    expect(created, 3);
    final dates = (await db.transactionDao.watchRecent().first)
        .map((r) => r.txn.date)
        .toList()
      ..sort();
    expect(dates, [
      DateTime(2026, 4, 26),
      DateTime(2026, 5, 26),
      DateTime(2026, 6, 26),
    ]);
  });
}
