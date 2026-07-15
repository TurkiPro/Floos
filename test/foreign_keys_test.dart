import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';

void main() {
  test('foreign_keys pragma is on for a fresh connection', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(row.data.values.first, 1);
  });

  test('deleting a rule nulls its transactions recurrenceId (SET NULL)',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // Category id 1 (طعام) is seeded on create.
    final ruleId = await db.recurrenceDao.add(
      title: 'اشتراك',
      amount: 50,
      categoryId: 1,
      type: TxnType.expense,
      frequency: Frequency.monthly,
      startDate: DateTime(2026, 1, 1),
    );
    final rule = (await db.recurrenceDao.activeRules())
        .firstWhere((r) => r.id == ruleId);
    await db.transactionDao.insertGenerated(rule, DateTime(2026, 2, 1));

    // Sanity: the transaction points at the rule.
    var txns = await db.transactionDao.watchRecent().first;
    expect(txns.single.txn.recurrenceId, ruleId);

    // Delete the rule — the transaction must survive, its link nulled.
    await db.recurrenceDao.deleteById(ruleId);

    txns = await db.transactionDao.watchRecent().first;
    expect(txns, hasLength(1),
        reason: 'the generated transaction is kept, not cascaded away');
    expect(txns.single.txn.recurrenceId, isNull,
        reason: 'the dangling rule link is nulled');
  });

  test(
      'a category referenced by a transaction cannot be hard-deleted (RESTRICT)',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.transactionDao.add(
      amount: 10,
      categoryId: 1,
      type: TxnType.expense,
      date: DateTime(2026, 3, 1),
    );

    // Categories are archived in normal use, never deleted; enforcement guards
    // against a future bug doing a raw delete.
    Future<void> rawDelete() =>
        db.customStatement('DELETE FROM categories WHERE id = 1');
    await expectLater(rawDelete(), throwsA(anything));
  });
}
