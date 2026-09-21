import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';

/// Undo deletes rows from a live financial ledger, so the thing under test is
/// not "does it delete" but "does it delete *only* what its own import wrote".
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
  });

  Future<int> importedTxn(int batchId,
      {double amount = 30, DateTime? date}) async {
    return db.into(db.transactions).insert(TransactionsCompanion.insert(
          amount: amount,
          categoryId: 1,
          type: TxnType.expense,
          date: date ?? DateTime(2026, 9, 12),
          importBatchId: Value(batchId),
        ));
  }

  Future<int> handTypedTxn({double amount = 30, DateTime? date}) async {
    return db.into(db.transactions).insert(TransactionsCompanion.insert(
          amount: amount,
          categoryId: 1,
          type: TxnType.expense,
          date: date ?? DateTime(2026, 9, 12),
        ));
  }

  Future<int> importedContribution(int batchId, int goalId) async {
    return db
        .into(db.savingsContributions)
        .insert(SavingsContributionsCompanion.insert(
          goalId: goalId,
          amount: 100,
          date: DateTime(2026, 9, 18),
          importBatchId: Value(batchId),
        ));
  }

  Future<int> txnCount() async =>
      (await db.select(db.transactions).get()).length;

  test('latest() returns the most recent batch, or null', () async {
    expect(await db.importBatchDao.latest(), isNull);
    await db.importBatchDao.create(rowCount: 3, totalAmount: 100);
    final second = await db.importBatchDao.create(rowCount: 2, totalAmount: 50);
    expect((await db.importBatchDao.latest())!.id, second);
  });

  test('undo removes the batch rows and nothing else', () async {
    final batch = await db.importBatchDao.create(rowCount: 2, totalAmount: 60);
    await importedTxn(batch);
    await importedTxn(batch);
    // Same day, same amount, typed by hand — must survive.
    final typed = await handTypedTxn();

    expect(await txnCount(), 3);
    await db.importBatchDao.undo(batch);

    final left = await db.select(db.transactions).get();
    expect(left, hasLength(1));
    expect(left.single.id, typed);
    expect(await db.select(db.importBatches).get(), isEmpty);
  });

  test('undo removes imported savings contributions too', () async {
    final goalId =
        await db.savingsDao.addGoal(name: 'سيارة', targetAmount: 1000);
    final batch = await db.importBatchDao.create(rowCount: 1, totalAmount: 100);
    await importedContribution(batch, goalId);

    expect(await db.select(db.savingsContributions).get(), hasLength(1));
    await db.importBatchDao.undo(batch);
    expect(await db.select(db.savingsContributions).get(), isEmpty);
  });

  test('undoing the latest batch leaves an older one untouched', () async {
    final older = await db.importBatchDao.create(rowCount: 1, totalAmount: 30);
    final olderTxn = await importedTxn(older);
    final newer = await db.importBatchDao.create(rowCount: 1, totalAmount: 40);
    await importedTxn(newer, amount: 40);

    await db.importBatchDao.undo(newer);

    final left = await db.select(db.transactions).get();
    expect(left, hasLength(1));
    expect(left.single.id, olderTxn);
    expect(await db.select(db.importBatches).get(), hasLength(1));
  });

  test('undo forgets rules that batch first taught', () async {
    final batch = await db.importBatchDao.create(rowCount: 1, totalAmount: 30);
    await db.partyRuleDao.remember(
      rawParty: 'RED BOX',
      disposition: PartyDisposition.expense,
      categoryId: 1,
      createdByBatchId: batch,
    );
    expect(await db.partyRuleDao.getAll(), hasLength(1));

    await db.importBatchDao.undo(batch);

    // Otherwise "undo because I miscategorized it, then re-import" would
    // re-apply the same wrong category from the rule the bad import created.
    expect(await db.partyRuleDao.getAll(), isEmpty);
  });

  test('undo keeps rules it merely re-used', () async {
    final first = await db.importBatchDao.create(rowCount: 1, totalAmount: 30);
    await db.partyRuleDao.remember(
      rawParty: 'RED BOX',
      disposition: PartyDisposition.expense,
      categoryId: 1,
      createdByBatchId: first,
    );

    // A later import sees the same merchant and re-saves it. Ownership must
    // stay with the batch that created it.
    final second = await db.importBatchDao.create(rowCount: 1, totalAmount: 30);
    await db.partyRuleDao.remember(
      rawParty: 'RED BOX',
      disposition: PartyDisposition.expense,
      categoryId: 1,
      createdByBatchId: second,
    );

    await db.importBatchDao.undo(second);

    final rules = await db.partyRuleDao.getAll();
    expect(rules, hasLength(1));
    expect(rules.single.createdByBatchId, first);
  });

  test('countsFor matches what undo actually removes', () async {
    final goalId =
        await db.savingsDao.addGoal(name: 'سيارة', targetAmount: 1000);
    final batch = await db.importBatchDao.create(rowCount: 3, totalAmount: 160);
    await importedTxn(batch);
    await importedTxn(batch, amount: 30);
    await importedContribution(batch, goalId);

    final counts = await db.importBatchDao.countsFor(batch);
    expect(counts.txns, 2);
    expect(counts.contributions, 1);

    await db.importBatchDao.undo(batch);
    expect(await txnCount(), 0);
    expect(await db.select(db.savingsContributions).get(), isEmpty);
  });

  test('countsFor reflects a row deleted by hand since the import', () async {
    final batch = await db.importBatchDao.create(rowCount: 2, totalAmount: 60);
    final one = await importedTxn(batch);
    await importedTxn(batch);
    await db.transactionDao.deleteById(one);

    // The stored rowCount still says 2; the confirmation must not promise to
    // remove a row that is already gone.
    final batchRow = await db.importBatchDao.latest();
    expect(batchRow!.rowCount, 2);
    expect((await db.importBatchDao.countsFor(batch)).txns, 1);
  });

  test('ignoredCount is recorded but writes nothing', () async {
    final batch = await db.importBatchDao.create(
      rowCount: 1,
      totalAmount: 30,
      ignoredCount: 2,
    );
    await importedTxn(batch);

    final row = await db.importBatchDao.latest();
    expect(row!.ignoredCount, 2);
    // Two top-ups were parsed and deliberately not booked.
    expect(await txnCount(), 1);
  });
}
