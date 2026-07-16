import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';

/// Tap-to-edit lets a transaction's date/amount/etc. be corrected in place —
/// e.g. fixing the day a salary actually landed for the current or a past month.
void main() {
  test('updateFields edits in place without changing id or recurrence link',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // A generated (recurring) salary occurrence, so we can prove the link and
    // id survive an edit.
    final ruleId = await db.recurrenceDao.add(
      title: 'راتب',
      amount: 9000,
      categoryId: 9, // any income category id
      type: TxnType.income,
      frequency: Frequency.monthly,
      startDate: DateTime(2026, 7, 1),
    );
    final rule = (await db.recurrenceDao.activeRules())
        .firstWhere((r) => r.id == ruleId);
    await db.transactionDao.insertGenerated(rule, DateTime(2026, 7, 27));
    final before = (await db.transactionDao.watchRecent().first).single.txn;

    // Salary actually landed two days early, and was 9,050 this month.
    await db.transactionDao.updateFields(
      id: before.id,
      amount: 9050,
      categoryId: before.categoryId,
      type: before.type,
      date: DateTime(2026, 7, 25),
      note: 'وصل مبكرًا',
    );

    final after = (await db.transactionDao.watchRecent().first).single.txn;
    expect(after.id, before.id);
    expect(after.date, DateTime(2026, 7, 25));
    expect(after.amount, 9050);
    expect(after.note, 'وصل مبكرًا');
    expect(after.recurrenceId, ruleId, reason: 'the rule link must survive');
    expect(after.type, TxnType.income);
  });

  test('a generated transaction carries the rule name as its note', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final ruleId = await db.recurrenceDao.add(
      title: 'نتفلكس',
      amount: 56,
      categoryId: 1,
      type: TxnType.expense,
      frequency: Frequency.monthly,
      startDate: DateTime(2026, 7, 1),
    );
    final rule = (await db.recurrenceDao.activeRules())
        .firstWhere((r) => r.id == ruleId);
    await db.transactionDao.insertGenerated(rule, DateTime(2026, 7, 1));

    final txn = (await db.transactionDao.watchRecent().first).single.txn;
    expect(txn.note, 'نتفلكس',
        reason: 'the obligation name shows in the list, not just its category');
  });
}
