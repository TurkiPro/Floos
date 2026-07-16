import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/recurrence_engine.dart';

/// Swipe-to-delete offers an Undo; these cover the data integrity of the
/// restore path (the SnackBar plumbing itself is framework behavior).
void main() {
  test('restore resurrects a deleted transaction byte-for-byte', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.transactionDao.add(
      amount: 42.5,
      categoryId: 1,
      type: TxnType.expense,
      date: DateTime(2026, 7, 10),
      note: 'قهوة',
    );
    final txn = (await db.transactionDao.watchRecent().first).single.txn;

    await db.transactionDao.deleteById(txn.id);
    expect(await db.transactionDao.watchRecent().first, isEmpty);

    await db.transactionDao.restore(txn);
    final back = (await db.transactionDao.watchRecent().first).single.txn;
    expect(back.id, txn.id);
    expect(back.amount, 42.5);
    expect(back.date, txn.date);
    expect(back.note, 'قهوة');
    expect(back.createdAt, txn.createdAt);
  });

  test('restore preserves the recurrence link', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final ruleId = await db.recurrenceDao.add(
      title: 'اشتراك',
      amount: 30,
      categoryId: 1,
      type: TxnType.expense,
      frequency: Frequency.monthly,
      startDate: DateTime(2026, 1, 1),
    );
    final rule = (await db.recurrenceDao.activeRules())
        .firstWhere((r) => r.id == ruleId);
    await db.transactionDao.insertGenerated(rule, DateTime(2026, 2, 1));
    final txn = (await db.transactionDao.watchRecent().first).single.txn;

    await db.transactionDao.deleteById(txn.id);
    await db.transactionDao.restore(txn);

    final back = (await db.transactionDao.watchRecent().first).single.txn;
    expect(back.recurrenceId, ruleId);
  });

  test('catch-up does not duplicate a restored occurrence', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final ruleId = await db.recurrenceDao.add(
      title: 'اشتراك',
      amount: 30,
      categoryId: 1,
      type: TxnType.expense,
      frequency: Frequency.monthly,
      startDate: DateTime(2026, 1, 1),
    );
    // Materialize up to today so the marker is current.
    await RecurrenceEngine(db).catchUp();
    final txn = (await db.transactionDao.watchRecent().first)
        .firstWhere((r) => r.txn.recurrenceId == ruleId)
        .txn;

    await db.transactionDao.deleteById(txn.id);
    await db.transactionDao.restore(txn);
    final before = (await db.transactionDao.watchRecent().first).length;

    await RecurrenceEngine(db).catchUp();
    final after = (await db.transactionDao.watchRecent().first).length;
    expect(after, before, reason: 'the rule marker never moved back');
  });
}
