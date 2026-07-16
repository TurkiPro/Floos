import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floos/data/database.dart';

/// A deposit added to a savings goal is now removable by swipe-to-delete, with
/// an Undo. These cover the data integrity of that path; the SnackBar plumbing
/// itself is framework behaviour.
void main() {
  test('deleting a contribution drops it from the ledger and the total',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final goalId =
        await db.savingsDao.addGoal(name: 'سيارة', targetAmount: 1000);
    await db.savingsDao.addContribution(
        goalId: goalId, amount: 200, date: DateTime(2026, 7, 1));
    final id = await db.savingsDao.addContribution(
        goalId: goalId, amount: 300, date: DateTime(2026, 7, 5));

    expect(await db.savingsDao.watchTotal(goalId).first, 500);

    await db.savingsDao.deleteContribution(id);

    expect((await db.savingsDao.watchContributions(goalId).first).length, 1);
    expect(await db.savingsDao.watchTotal(goalId).first, 200);
  });

  test('restore resurrects a deleted contribution byte-for-byte', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final goalId = await db.savingsDao.addGoal(name: 'سفر', targetAmount: 5000);
    await db.savingsDao.addContribution(
      goalId: goalId,
      amount: 750,
      date: DateTime(2026, 6, 20),
      note: 'هدية العيد',
      external: true,
    );
    final c = (await db.savingsDao.watchContributions(goalId).first).single;

    await db.savingsDao.deleteContribution(c.id);
    expect(await db.savingsDao.watchContributions(goalId).first, isEmpty);

    await db.savingsDao.restoreContribution(c);
    final back = (await db.savingsDao.watchContributions(goalId).first).single;
    expect(back.id, c.id);
    expect(back.amount, 750);
    expect(back.date, c.date);
    expect(back.note, 'هدية العيد');
    expect(back.external, isTrue,
        reason: 'the external flag must survive undo');
    expect(await db.savingsDao.watchTotal(goalId).first, 750);
  });
}
