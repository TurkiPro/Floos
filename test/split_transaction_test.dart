import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floos/data/backup.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/bank_sms.dart' show txnFingerprint;
import 'package:floos/domain/import_review.dart' show ledgerFingerprints;

/// Splitting one purchase across categories (schema v15).
void main() {
  late AppDatabase db;
  late int groceries, household;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    groceries = 1; // a seeded expense category
    household = await db.categoryDao.add(
      name: 'منزل',
      iconKey: 'home',
      colorValue: 0xFF000000,
      type: TxnType.expense,
    );
  });

  final day = DateTime(2026, 11, 2, 18, 5);

  Future<int> aPurchase({double amount = 420, int? batch}) async {
    final id = await db.transactionDao.add(
      amount: amount,
      categoryId: groceries,
      type: TxnType.expense,
      date: day,
      note: 'بنده',
    );
    if (batch != null) {
      await (db.update(db.transactions)..where((t) => t.id.equals(id)))
          .write(TransactionsCompanion(importBatchId: Value(batch)));
    }
    return id;
  }

  Future<List<Txn>> all() => (db.select(db.transactions)
        ..orderBy([(t) => OrderingTerm.asc(t.id)]))
      .get();

  test('a split becomes ordinary rows that add up to the purchase', () async {
    final id = await aPurchase();
    await db.transactionDao.saveSplit(id,
        parts: [
          (amount: 300, categoryId: groceries),
          (amount: 120, categoryId: household),
        ],
        date: day,
        note: 'بنده');

    final rows = await all();
    expect(rows, hasLength(2));
    expect(rows.map((r) => r.amount), [300, 120]);
    expect(rows.map((r) => r.categoryId), [groceries, household]);
    expect(rows.every((r) => r.splitGroupId == id), isTrue,
        reason: 'the group is named by the row that was split');
    expect(rows.first.id, id, reason: 'the original keeps its id');
    expect(rows.every((r) => r.date == day && r.note == 'بنده'), isTrue);
    expect(rows.every((r) => r.type == TxnType.expense), isTrue);
  });

  test('parts that do not add up are refused, and nothing changes', () async {
    final id = await aPurchase();
    await expectLater(
      db.transactionDao.saveSplit(id,
          parts: [
            (amount: 300, categoryId: groceries),
            (amount: 100, categoryId: household),
          ],
          date: day),
      throwsArgumentError,
    );
    final rows = await all();
    expect(rows.single.amount, 420);
    expect(rows.single.splitGroupId, isNull);
  });

  test('a recurring row cannot be split', () async {
    final ruleId = await db.recurrenceDao.add(
      title: 'إيجار',
      amount: 1000,
      categoryId: groceries,
      type: TxnType.expense,
      frequency: Frequency.monthly,
      startDate: DateTime(2026, 1, 1),
    );
    final rule = (await db.recurrenceDao.activeRules())
        .firstWhere((r) => r.id == ruleId);
    await db.transactionDao.insertGenerated(rule, DateTime(2026, 11, 1));
    final generated = (await all()).single;
    await expectLater(
      db.transactionDao.saveSplit(generated.id,
          parts: [
            (amount: 500, categoryId: groceries),
            (amount: 500, categoryId: household),
          ],
          date: generated.date),
      throwsArgumentError,
    );
  });

  test('income and single-part splits are refused', () async {
    final income = await db.transactionDao.add(
        amount: 100,
        categoryId: 9,
        type: TxnType.income,
        date: day);
    await expectLater(
      db.transactionDao.saveSplit(income,
          parts: [
            (amount: 50, categoryId: groceries),
            (amount: 50, categoryId: household),
          ],
          date: day),
      throwsArgumentError,
    );
    final id = await aPurchase();
    await expectLater(
      db.transactionDao.saveSplit(id,
          parts: [(amount: 420, categoryId: household)], date: day),
      throwsArgumentError,
    );
  });

  test('re-splitting replaces the parts; unsplit restores one row', () async {
    final id = await aPurchase();
    await db.transactionDao.saveSplit(id,
        parts: [
          (amount: 300, categoryId: groceries),
          (amount: 120, categoryId: household),
        ],
        date: day);
    final secondPart = (await all()).last.id;

    // Re-split from the OTHER part — either part opens the whole purchase.
    await db.transactionDao.saveSplit(secondPart,
        parts: [
          (amount: 200, categoryId: groceries),
          (amount: 100, categoryId: household),
          (amount: 120, categoryId: groceries),
        ],
        date: day);
    expect((await all()).map((r) => r.amount), [200, 100, 120]);

    await db.transactionDao.unsplit(id);
    final rows = await all();
    expect(rows, hasLength(1));
    expect(rows.single.id, id);
    expect(rows.single.amount, 420);
    expect(rows.single.categoryId, groceries);
    expect(rows.single.splitGroupId, isNull);
  });

  test('every part of an imported purchase goes when the import is undone',
      () async {
    final batch =
        await db.importBatchDao.create(rowCount: 1, totalAmount: 420);
    final id = await aPurchase(batch: batch);
    await db.transactionDao.saveSplit(id,
        parts: [
          (amount: 300, categoryId: groceries),
          (amount: 120, categoryId: household),
        ],
        date: day);
    expect((await all()).every((r) => r.importBatchId == batch), isTrue);

    await db.importBatchDao.undo(batch);
    expect(await all(), isEmpty);
  });

  test('a swipe-deleted part comes back into its group on undo', () async {
    final id = await aPurchase();
    await db.transactionDao.saveSplit(id,
        parts: [
          (amount: 300, categoryId: groceries),
          (amount: 120, categoryId: household),
        ],
        date: day);
    final part = (await all()).last;
    await db.transactionDao.deleteById(part.id);
    await db.transactionDao.restore(part);
    expect((await db.transactionDao.splitParts(id)).map((r) => r.amount),
        [300, 120]);
  });

  test('splits survive backup and restore', () async {
    final id = await aPurchase();
    await db.transactionDao.saveSplit(id,
        parts: [
          (amount: 300, categoryId: groceries),
          (amount: 120, categoryId: household),
        ],
        date: day);

    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(target.close);
    await restoreBackupJson(target, await buildBackupJson(db));
    final parts = await target.transactionDao.splitParts(id);
    expect(parts.map((r) => r.amount), [300, 120]);
  });

  test('a pre-v15 backup restores with no splits', () async {
    await aPurchase();
    final map = jsonDecode(await buildBackupJson(db)) as Map<String, dynamic>;
    for (final t in map['transactions'] as List) {
      (t as Map<String, dynamic>).remove('splitGroupId');
    }
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(target.close);
    await restoreBackupJson(target, jsonEncode(map));
    final rows = await target.select(target.transactions).get();
    expect(rows.single.splitGroupId, isNull);
  });
  test('re-pasting the message for a split purchase is still a duplicate',
      () async {
    // The import fingerprints the ledger by (amount, day, note). After a split
    // no row carries the 420 the bank reported, so without the group
    // fingerprint the same message would be imported a second time.
    final id = await aPurchase();
    await db.transactionDao.saveSplit(id,
        parts: [
          (amount: 300, categoryId: groceries),
          (amount: 120, categoryId: household),
        ],
        date: day,
        note: 'بنده');

    final prints = ledgerFingerprints(await all());
    expect(prints,
        contains(txnFingerprint(amount: 420, date: day, party: 'بنده')));
    expect(prints,
        contains(txnFingerprint(amount: 120, date: day, party: 'بنده')),
        reason: 'each part is still a row of its own');
  });
}
