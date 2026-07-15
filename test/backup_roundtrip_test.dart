import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floos/data/backup.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';

/// Seeds a known set across all five tables, including the FK links that a
/// faithful backup must preserve: a sub-category under a parent, a transaction
/// generated from a rule, and a contribution against a goal.
Future<
    ({
      int subCategoryId,
      int parentCategoryId,
      int ruleId,
      int goalId,
    })> _seed(AppDatabase db) async {
  // A sub-category under the seeded parent category id 1 (طعام).
  final subId = await db.categoryDao.add(
    name: 'قهوة مختصة',
    iconKey: 'local_cafe',
    colorValue: 0xFF000000,
    type: TxnType.expense,
    parentId: 1,
    kind: CategoryKind.luxury,
  );

  final ruleId = await db.recurrenceDao.add(
    title: 'اشتراك',
    amount: 40,
    categoryId: 1,
    type: TxnType.expense,
    frequency: Frequency.monthly,
    startDate: DateTime(2026, 1, 1),
  );
  final rule =
      (await db.recurrenceDao.activeRules()).firstWhere((r) => r.id == ruleId);
  await db.transactionDao.insertGenerated(rule, DateTime(2026, 2, 1));

  final goalId = await db.savingsDao.addGoal(
    name: 'سيارة',
    targetAmount: 50000,
    targetDate: DateTime(2027, 1, 1),
  );
  await db.savingsDao.addContribution(
    goalId: goalId,
    amount: 2000,
    date: DateTime(2026, 2, 3),
    note: 'إيداع',
  );

  return (
    subCategoryId: subId,
    parentCategoryId: 1,
    ruleId: ruleId,
    goalId: goalId,
  );
}

void main() {
  test('backup round-trips every table and preserves FK links', () async {
    final source = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(source.close);
    final ids = await _seed(source);

    final json = await buildBackupJson(source);

    // Restore into a *fresh* database (simulates a new device / reinstall).
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(target.close);
    await restoreBackupJson(target, json);

    // Sub-category still points at its parent.
    final cats = await target.categoryDao.getAll();
    final sub = cats.firstWhere((c) => c.id == ids.subCategoryId);
    expect(sub.name, 'قهوة مختصة');
    expect(sub.parentId, ids.parentCategoryId);

    // The generated transaction survived and still links to its rule.
    final txns = await target.transactionDao.watchRecent().first;
    expect(txns, hasLength(1));
    expect(txns.single.txn.amount, 40);
    expect(txns.single.txn.recurrenceId, ids.ruleId);

    // Rule, goal and contribution all restored.
    final rules = await target.recurrenceDao.activeRules();
    expect(rules.any((r) => r.id == ids.ruleId && r.title == 'اشتراك'), isTrue);

    final total = await target.savingsDao.watchTotal(ids.goalId).first;
    expect(total, 2000);
  });

  test('restore replaces existing data wholesale', () async {
    final source = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(source.close);
    await _seed(source);
    final json = await buildBackupJson(source);

    // Target already has its own unrelated transaction.
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(target.close);
    await target.transactionDao.add(
      amount: 999,
      categoryId: 1,
      type: TxnType.expense,
      date: DateTime(2025, 12, 1),
    );

    await restoreBackupJson(target, json);

    // The pre-existing 999 transaction is gone; only the backup's remains.
    final txns = await target.transactionDao.watchRecent().first;
    expect(txns, hasLength(1));
    expect(txns.single.txn.amount, 40);
  });

  test('malformed JSON leaves the database untouched (rolls back)', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.transactionDao.add(
      amount: 123,
      categoryId: 1,
      type: TxnType.expense,
      date: DateTime(2026, 4, 1),
    );

    await expectLater(
      restoreBackupJson(db, '{ this is not valid json'),
      throwsA(isA<BackupFormatException>()),
    );

    // The existing data is still there.
    final txns = await db.transactionDao.watchRecent().first;
    expect(txns, hasLength(1));
    expect(txns.single.txn.amount, 123);
  });

  test('a wrong version is rejected', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await expectLater(
      restoreBackupJson(db, '{"version": 999, "categories": []}'),
      throwsA(isA<BackupFormatException>()),
    );
  });
}
