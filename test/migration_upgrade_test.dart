import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:floos/data/database.dart';

/// Exercises the real upgrade path against a hand-built v4 database — the one
/// thing the rest of the suite can't cover, because every other test starts at
/// the current schema. Builds a pre-foreign-key v4 file (so it can hold an
/// orphaned recurrence link, which enforcement would otherwise reject), then
/// opens it through AppDatabase and asserts the whole v4→current migration
/// chain (FK enforcement + SET NULL, the budgets table, the external-deposit
/// column) preserves data and applies each change.
void main() {
  test('v4 database upgrades to the current schema, preserving data', () async {
    final dir = Directory.systemTemp.createTempSync('floos_migration');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/floos.sqlite';

    // --- Build a v4 database with raw SQL (foreign keys left OFF) ---
    final db4 = raw.sqlite3.open(path);
    db4.execute('''
      CREATE TABLE categories (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL, icon_key TEXT NOT NULL, color_value INTEGER NOT NULL,
        type INTEGER NOT NULL, parent_id INTEGER REFERENCES categories(id),
        kind INTEGER NOT NULL DEFAULT 0, archived INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE recurrence_rules (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL,
        amount REAL NOT NULL, category_id INTEGER NOT NULL REFERENCES categories(id),
        type INTEGER NOT NULL, frequency INTEGER NOT NULL,
        interval INTEGER NOT NULL DEFAULT 1, start_date INTEGER NOT NULL,
        end_date INTEGER, last_materialized INTEGER,
        active INTEGER NOT NULL DEFAULT 1, note TEXT);
      CREATE TABLE transactions (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, amount REAL NOT NULL,
        category_id INTEGER NOT NULL REFERENCES categories(id),
        type INTEGER NOT NULL, date INTEGER NOT NULL, note TEXT,
        recurrence_id INTEGER REFERENCES recurrence_rules(id),
        created_at INTEGER NOT NULL);
      CREATE TABLE savings_goals (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
        target_amount REAL NOT NULL, target_date INTEGER,
        archived INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE savings_contributions (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        goal_id INTEGER NOT NULL REFERENCES savings_goals(id),
        amount REAL NOT NULL, date INTEGER NOT NULL, note TEXT);
    ''');
    db4.execute(
        "INSERT INTO categories (id, name, icon_key, color_value, type) "
        "VALUES (1, 'طعام', 'food', 0, 0);");
    db4.execute(
        "INSERT INTO recurrence_rules (id, title, amount, category_id, type, frequency, start_date) "
        "VALUES (1, 'اشتراك', 50, 1, 0, 2, 0);");
    // Transaction 1: valid link to rule 1.
    db4.execute(
        "INSERT INTO transactions (id, amount, category_id, type, date, recurrence_id, created_at) "
        "VALUES (1, 50, 1, 0, 0, 1, 0);");
    // Transaction 2: orphaned link to a rule that doesn't exist (only possible
    // pre-enforcement). The v4→v5 migration must null this.
    db4.execute(
        "INSERT INTO transactions (id, amount, category_id, type, date, recurrence_id, created_at) "
        "VALUES (2, 20, 1, 0, 0, 999, 0);");
    db4.execute('PRAGMA user_version = 4;');
    db4.close();

    // --- Open through drift: triggers onUpgrade(_, 4, 6) then beforeOpen ---
    final db = AppDatabase.forTesting(NativeDatabase(File(path)));
    addTearDown(db.close);

    // Force the database open (drift is lazy).
    final txns = await db.transactionDao.watchRecent().first;

    // Data preserved through the transactions table rebuild.
    expect(txns, hasLength(2), reason: 'both rows survive the migration');
    final t1 = txns.firstWhere((r) => r.txn.id == 1);
    final t2 = txns.firstWhere((r) => r.txn.id == 2);
    expect(t1.txn.recurrenceId, 1, reason: 'valid link preserved');
    expect(t2.txn.recurrenceId, isNull, reason: 'orphan link nulled (v4→v5)');

    // Foreign keys are enforced now.
    final fk = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(fk.data.values.first, 1);

    // The v5→v6 table exists and works.
    await db.budgetDao.setBudget(1, 500);
    final budgets = await db.budgetDao.getAll();
    expect(budgets.single.amount, 500);

    // The v6→v7 column exists: a savings goal + an external contribution.
    final goalId = await db.savingsDao.addGoal(name: 'هدف', targetAmount: 1000);
    await db.savingsDao.addContribution(
        goalId: goalId, amount: 50, date: DateTime(2026, 7, 1));
    await db.savingsDao.addContribution(
        goalId: goalId, amount: 70, date: DateTime(2026, 7, 2), external: true);
    final contribs = await db.savingsDao.watchContributions(goalId).first;
    expect(
        contribs.map((c) => c.external).toList(), containsAll([true, false]));

    // Post-migration ON DELETE SET NULL is in effect.
    await db.recurrenceDao.deleteById(1);
    final after = await db.transactionDao.watchRecent().first;
    expect(after.firstWhere((r) => r.txn.id == 1).txn.recurrenceId, isNull,
        reason: 'deleting a rule nulls its transactions post-migration');
  });

  // The exact path a store user on 1.0.1 (schema 7) takes to 1.1.0 (schema 12):
  // v8 override columns, v10 reflections table, v11 investments table, and the
  // v12 last_paid_date column + back-fill. Builds a real v7 database with data
  // and asserts it survives and every added feature works.
  test('a v7 (1.0.1) database upgrades to the current schema', () async {
    final dir = Directory.systemTemp.createTempSync('floos_v7');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/floos.sqlite';

    // A date value the way it's stored on disk; the exact epoch scale doesn't
    // matter to the assertions (they compare values drift itself reads back).
    final salaryStamp = DateTime(2026, 7, 1).millisecondsSinceEpoch ~/ 1000;

    final db7 = raw.sqlite3.open(path);
    db7.execute('''
      CREATE TABLE categories (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL, icon_key TEXT NOT NULL, color_value INTEGER NOT NULL,
        type INTEGER NOT NULL, parent_id INTEGER REFERENCES categories(id),
        kind INTEGER NOT NULL DEFAULT 0, archived INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE recurrence_rules (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL,
        amount REAL NOT NULL, category_id INTEGER NOT NULL REFERENCES categories(id),
        type INTEGER NOT NULL, frequency INTEGER NOT NULL,
        interval INTEGER NOT NULL DEFAULT 1, start_date INTEGER NOT NULL,
        end_date INTEGER, last_materialized INTEGER,
        active INTEGER NOT NULL DEFAULT 1, note TEXT);
      CREATE TABLE transactions (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, amount REAL NOT NULL,
        category_id INTEGER NOT NULL REFERENCES categories(id),
        type INTEGER NOT NULL, date INTEGER NOT NULL, note TEXT,
        recurrence_id INTEGER REFERENCES recurrence_rules(id) ON DELETE SET NULL,
        created_at INTEGER NOT NULL);
      CREATE TABLE savings_goals (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
        target_amount REAL NOT NULL, target_date INTEGER,
        archived INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE savings_contributions (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        goal_id INTEGER NOT NULL REFERENCES savings_goals(id),
        amount REAL NOT NULL, date INTEGER NOT NULL, note TEXT,
        external INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE category_budgets (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        category_id INTEGER NOT NULL UNIQUE REFERENCES categories(id),
        amount REAL NOT NULL);
    ''');
    db7.execute(
        "INSERT INTO categories (id, name, icon_key, color_value, type) "
        "VALUES (1, 'طعام', 'food', 0, 0), (9, 'راتب', 'salary', 0, 1);");
    // A monthly salary rule with a materialized transaction — the v12 back-fill
    // must set its last_paid_date from that transaction.
    db7.execute(
        "INSERT INTO recurrence_rules (id, title, amount, category_id, type, frequency, start_date, last_materialized) "
        "VALUES (1, 'راتب', 6000, 9, 1, 2, $salaryStamp, $salaryStamp);");
    db7.execute(
        "INSERT INTO transactions (id, amount, category_id, type, date, recurrence_id, created_at) "
        "VALUES (1, 6000, 9, 1, $salaryStamp, 1, $salaryStamp);");
    db7.execute(
        "INSERT INTO transactions (id, amount, category_id, type, date, created_at) "
        "VALUES (2, 50, 1, 0, $salaryStamp, $salaryStamp);");
    db7.execute(
        "INSERT INTO savings_goals (id, name, target_amount) VALUES (1, 'هدف', 1000);");
    db7.execute(
        "INSERT INTO savings_contributions (id, goal_id, amount, date, external) "
        "VALUES (1, 1, 200, $salaryStamp, 0), (2, 1, 5000, $salaryStamp, 1);");
    db7.execute(
        "INSERT INTO category_budgets (id, category_id, amount) VALUES (1, 1, 500);");
    db7.execute('PRAGMA user_version = 7;');
    db7.close();

    final db = AppDatabase.forTesting(NativeDatabase(File(path)));
    addTearDown(db.close);

    // Data survived the 7 -> 12 chain.
    final txns = await db.transactionDao.watchRecent().first;
    expect(txns, hasLength(2));
    final t1 = txns.firstWhere((r) => r.txn.id == 1);
    expect(t1.txn.recurrenceId, 1);
    expect((await db.budgetDao.getAll()).single.amount, 500);
    final contribs = await db.savingsDao.watchContributions(1).first;
    expect(
        contribs.map((c) => c.external).toList(), containsAll([true, false]));

    // v12: last_paid_date back-filled from the rule's most recent transaction.
    final rule =
        (await db.recurrenceDao.activeRules()).firstWhere((r) => r.id == 1);
    expect(rule.lastPaidDate, t1.txn.date,
        reason: 'v12 back-fills last_paid_date from the ledger');
    // v8: the override columns exist and read as null.
    expect(rule.nextOverrideDate, isNull);

    // v10 reflections + v11 investments tables exist and work.
    await db.weeklyReflectionDao.setNote(DateTime(2026, 7, 1), 'ملاحظة');
    expect((await db.weeklyReflectionDao.watchAll().first), isNotEmpty);
    await db.investmentDao
        .add(name: 'سهم', amount: 100, date: DateTime(2026, 7, 1));
    expect((await db.investmentDao.watchAll().first), isNotEmpty);
  });
}
