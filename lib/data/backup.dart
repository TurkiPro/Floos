import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database.dart';
import 'enums.dart';

/// Local, full-fidelity backup of the whole database as a single JSON string —
/// every row of every table, so it can be restored byte-for-byte on another
/// device. This is deliberately *not* the analysis CSV in `export.dart` (which
/// is lossy: no goals, no rules, no category tree). The file never leaves the
/// user's control; there is no server involved.
///
/// Restore semantics are **replace**: [restoreBackupJson] wipes the database
/// and re-inserts the backup wholesale, preserving primary keys so every
/// foreign key (a sub-category's parent, a transaction's category/rule, a
/// contribution's goal) still resolves. "Restore a backup" means "make this
/// device look like the backup", and replace is the only semantics that does
/// that without duplicate/identity headaches. It runs inside a single
/// transaction, so a malformed file leaves the existing data untouched.
///
/// This is a spike/POC: no UI, no file I/O, no encryption. See
/// `plans/004-backup-restore-design.md` for the format contract and open
/// questions.

/// The backup format version. Bump when the shape changes; a future importer
/// branches on this to read older files.
const backupFormatVersion = 1;

int _ms(DateTime d) => d.millisecondsSinceEpoch;
DateTime _date(Object? v) => DateTime.fromMillisecondsSinceEpoch(v as int);
DateTime? _dateOrNull(Object? v) => v == null ? null : _date(v);

Future<String> buildBackupJson(AppDatabase db) async {
  final categories = await db.select(db.categories).get();
  final rules = await db.select(db.recurrenceRules).get();
  final txns = await db.select(db.transactions).get();
  final goals = await db.select(db.savingsGoals).get();
  final contributions = await db.select(db.savingsContributions).get();
  final budgets = await db.select(db.categoryBudgets).get();

  final map = {
    'version': backupFormatVersion,
    'exportedAt': _ms(DateTime.now()),
    'categories': [
      for (final c in categories)
        {
          'id': c.id,
          'name': c.name,
          'iconKey': c.iconKey,
          'colorValue': c.colorValue,
          'type': c.type.index,
          'parentId': c.parentId,
          'kind': c.kind.index,
          'archived': c.archived,
          'sortOrder': c.sortOrder,
        },
    ],
    'recurrenceRules': [
      for (final r in rules)
        {
          'id': r.id,
          'title': r.title,
          'amount': r.amount,
          'categoryId': r.categoryId,
          'type': r.type.index,
          'frequency': r.frequency.index,
          'interval': r.interval,
          'startDate': _ms(r.startDate),
          'endDate': r.endDate == null ? null : _ms(r.endDate!),
          'lastMaterialized':
              r.lastMaterialized == null ? null : _ms(r.lastMaterialized!),
          'active': r.active,
          'note': r.note,
        },
    ],
    'transactions': [
      for (final t in txns)
        {
          'id': t.id,
          'amount': t.amount,
          'categoryId': t.categoryId,
          'type': t.type.index,
          'date': _ms(t.date),
          'note': t.note,
          'recurrenceId': t.recurrenceId,
          'createdAt': _ms(t.createdAt),
        },
    ],
    'savingsGoals': [
      for (final g in goals)
        {
          'id': g.id,
          'name': g.name,
          'targetAmount': g.targetAmount,
          'targetDate': g.targetDate == null ? null : _ms(g.targetDate!),
          'archived': g.archived,
          'createdAt': _ms(g.createdAt),
        },
    ],
    'savingsContributions': [
      for (final c in contributions)
        {
          'id': c.id,
          'goalId': c.goalId,
          'amount': c.amount,
          'date': _ms(c.date),
          'note': c.note,
          'external': c.external,
        },
    ],
    'categoryBudgets': [
      for (final b in budgets)
        {
          'id': b.id,
          'categoryId': b.categoryId,
          'amount': b.amount,
        },
    ],
  };

  return const JsonEncoder.withIndent('  ').convert(map);
}

/// Writes the backup JSON to the app documents directory and returns the file.
/// The caller hands it to the OS share sheet — where it goes from there (Files,
/// iCloud, Drive, AirDrop) is the user's choice and custody. Mirrors
/// export.dart's exportTransactionsCsvToFile.
Future<File> writeBackupFile(AppDatabase db) async {
  final json = await buildBackupJson(db);
  final dir = await getApplicationDocumentsDirectory();
  final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  final file = File(p.join(dir.path, 'floos_backup_$stamp.json'));
  await file.writeAsString(json);
  return file;
}

/// Thrown when a backup file can't be parsed or fails validation. The database
/// is left untouched (the restore runs in a transaction that rolls back).
class BackupFormatException implements Exception {
  final String message;
  BackupFormatException(this.message);
  @override
  String toString() => 'BackupFormatException: $message';
}

Future<void> restoreBackupJson(AppDatabase db, String jsonString) async {
  final Object? parsed;
  try {
    parsed = jsonDecode(jsonString);
  } catch (e) {
    throw BackupFormatException('not valid JSON: $e');
  }
  if (parsed is! Map<String, dynamic>) {
    throw BackupFormatException('top level is not an object');
  }
  // Bind to a typed local: `rowsOf` closes over this, and a closure capturing
  // the nullable `parsed` would defeat type promotion.
  final Map<String, dynamic> root = parsed;
  final version = root['version'];
  if (version != backupFormatVersion) {
    throw BackupFormatException(
        'unsupported backup version: $version (expected $backupFormatVersion)');
  }
  for (final key in [
    'categories',
    'recurrenceRules',
    'transactions',
    'savingsGoals',
    'savingsContributions',
  ]) {
    if (root[key] is! List) {
      throw BackupFormatException('missing or invalid section: $key');
    }
  }

  List<Map<String, dynamic>> rowsOf(String key) =>
      (root[key] as List).cast<Map<String, dynamic>>();

  // categoryBudgets is read leniently: a pre-v6 backup file has no such section
  // and must restore as "no budgets" rather than fail validation.
  final budgetRows = root['categoryBudgets'] is List
      ? (root['categoryBudgets'] as List).cast<Map<String, dynamic>>()
      : const <Map<String, dynamic>>[];

  // Everything in one transaction: any failure (bad row, dangling FK) rolls the
  // whole thing back and the pre-existing data survives.
  await db.transaction(() async {
    // Wipe children before parents so FK enforcement is satisfied; delete
    // sub-categories before top-level for the self-reference. Budgets go first
    // — the category CASCADE would drop them anyway, but an explicit delete
    // keeps the wipe order self-documenting.
    await db.delete(db.categoryBudgets).go();
    await db.delete(db.transactions).go();
    await db.delete(db.savingsContributions).go();
    await db.delete(db.recurrenceRules).go();
    await db.delete(db.savingsGoals).go();
    await (db.delete(db.categories)..where((c) => c.parentId.isNotNull())).go();
    await db.delete(db.categories).go();

    // Insert parents before children in FK-safe order.
    final categories = rowsOf('categories');
    for (final topLevel in [true, false]) {
      for (final c in categories) {
        if ((c['parentId'] == null) != topLevel) continue;
        await db.into(db.categories).insert(CategoriesCompanion.insert(
              id: Value(c['id'] as int),
              name: c['name'] as String,
              iconKey: c['iconKey'] as String,
              colorValue: c['colorValue'] as int,
              type: TxnType.values[c['type'] as int],
              parentId: Value(c['parentId'] as int?),
              kind: Value(CategoryKind.values[c['kind'] as int]),
              archived: Value(c['archived'] as bool),
              sortOrder: Value(c['sortOrder'] as int),
            ));
      }
    }

    for (final r in rowsOf('recurrenceRules')) {
      await db.into(db.recurrenceRules).insert(RecurrenceRulesCompanion.insert(
            id: Value(r['id'] as int),
            title: r['title'] as String,
            amount: r['amount'] as double,
            categoryId: r['categoryId'] as int,
            type: TxnType.values[r['type'] as int],
            frequency: Frequency.values[r['frequency'] as int],
            interval: Value(r['interval'] as int),
            startDate: _date(r['startDate']),
            endDate: Value(_dateOrNull(r['endDate'])),
            lastMaterialized: Value(_dateOrNull(r['lastMaterialized'])),
            active: Value(r['active'] as bool),
            note: Value(r['note'] as String?),
          ));
    }

    for (final g in rowsOf('savingsGoals')) {
      await db.into(db.savingsGoals).insert(SavingsGoalsCompanion.insert(
            id: Value(g['id'] as int),
            name: g['name'] as String,
            targetAmount: g['targetAmount'] as double,
            targetDate: Value(_dateOrNull(g['targetDate'])),
            archived: Value(g['archived'] as bool),
            createdAt: Value(_date(g['createdAt'])),
          ));
    }

    for (final t in rowsOf('transactions')) {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: Value(t['id'] as int),
            amount: t['amount'] as double,
            categoryId: t['categoryId'] as int,
            type: TxnType.values[t['type'] as int],
            date: _date(t['date']),
            note: Value(t['note'] as String?),
            recurrenceId: Value(t['recurrenceId'] as int?),
            createdAt: Value(_date(t['createdAt'])),
          ));
    }

    for (final c in rowsOf('savingsContributions')) {
      await db
          .into(db.savingsContributions)
          .insert(SavingsContributionsCompanion.insert(
            id: Value(c['id'] as int),
            goalId: c['goalId'] as int,
            amount: c['amount'] as double,
            date: _date(c['date']),
            note: Value(c['note'] as String?),
            // Lenient: pre-v7 files have no external flag (default false).
            external: Value(c['external'] as bool? ?? false),
          ));
    }

    // Budgets reference categories, so insert them after the categories loop.
    for (final b in budgetRows) {
      await db.into(db.categoryBudgets).insert(CategoryBudgetsCompanion.insert(
            id: Value(b['id'] as int),
            categoryId: b['categoryId'] as int,
            amount: b['amount'] as double,
          ));
    }
  });
}
