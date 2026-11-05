import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';

void main() {
  late AppDatabase db;
  late int goalId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    goalId = await db.savingsDao.addGoal(name: 'سيارة', targetAmount: 50000);
  });

  Future<SavingsContribution> only() async =>
      (await db.select(db.savingsContributions).get()).single;

  group('planned', () {
    test('defaults to false, so existing withdrawals keep counting', () async {
      await db.savingsDao.addContribution(
          goalId: goalId, amount: -100, date: DateTime(2026, 11, 1));
      expect((await only()).planned, isFalse);
    });

    test('can never be set on a deposit', () async {
      // "The goal used as intended" only describes money coming OUT.
      await db.savingsDao.addContribution(
        goalId: goalId,
        amount: 100,
        date: DateTime(2026, 11, 1),
        planned: true,
      );
      expect((await only()).planned, isFalse);
    });

    test('editing a withdrawal into a deposit drops it', () async {
      final id = await db.savingsDao.addContribution(
        goalId: goalId,
        amount: -100,
        date: DateTime(2026, 11, 1),
        planned: true,
      );
      await db.savingsDao.updateContribution(
        id,
        goalId: goalId,
        amount: 100,
        date: DateTime(2026, 11, 1),
        external: false,
        planned: true,
      );
      expect((await only()).planned, isFalse);
    });
  });

  group('undoing a swipe-delete returns the SAME row', () {
    test('a contribution keeps planned, external and its import batch',
        () async {
      final batch =
          await db.importBatchDao.create(rowCount: 1, totalAmount: 100);
      await db.into(db.savingsContributions).insert(
            SavingsContributionsCompanion.insert(
              goalId: goalId,
              amount: -100,
              date: DateTime(2026, 11, 1),
              external: const Value(true),
              planned: const Value(true),
              importBatchId: Value(batch),
            ),
          );
      final original = await only();

      await db.savingsDao.deleteContribution(original.id);
      await db.savingsDao.restoreContribution(original);

      final back = await only();
      expect(back.planned, isTrue,
          reason: 'or a planned withdrawal is re-scored as a lapse');
      expect(back.external, isTrue);
      expect(back.importBatchId, batch,
          reason: 'undo used to drop this, orphaning the row from its import');
    });

    test('a transaction keeps its import batch', () async {
      final batch =
          await db.importBatchDao.create(rowCount: 1, totalAmount: 30);
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            amount: 30,
            categoryId: 1,
            type: TxnType.expense,
            date: DateTime(2026, 11, 1),
            importBatchId: Value(batch),
          ));
      final original = (await db.select(db.transactions).get()).single;

      await db.transactionDao.deleteById(original.id);
      await db.transactionDao.restore(original);

      final back = (await db.select(db.transactions).get()).single;
      expect(back.importBatchId, batch);
    });

    test('so undoing the import afterwards still removes it', () async {
      // The consequence that actually mattered: before the fix, a row that had
      // been swiped away and restored survived "undo this import".
      final batch =
          await db.importBatchDao.create(rowCount: 1, totalAmount: 30);
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            amount: 30,
            categoryId: 1,
            type: TxnType.expense,
            date: DateTime(2026, 11, 1),
            importBatchId: Value(batch),
          ));
      final original = (await db.select(db.transactions).get()).single;
      await db.transactionDao.deleteById(original.id);
      await db.transactionDao.restore(original);

      await db.importBatchDao.undo(batch);

      expect(await db.select(db.transactions).get(), isEmpty);
    });
  });
}
