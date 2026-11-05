import 'dart:io';

import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/period_summary.dart';
import 'database.dart';
import 'enums.dart';

/// Characters that make Excel, Sheets and Numbers treat a cell as a formula
/// rather than as text.
const _formulaTriggers = {'=', '+', '-', '@', '\t', '\r'};

String _csvField(String? v) {
  var s = v ?? '';
  // Neutralise formula injection before quoting. A cell beginning with one of
  // these is executed by every major spreadsheet, and this file is explicitly
  // built to be opened in one.
  //
  // This used to be self-inflicted only — your own category names and notes.
  // It is not any more: the bank-message importer writes merchant strings
  // taken from received SMS into the note column, so the content of a cell can
  // now be chosen by whoever sent the message. A leading quote is the standard
  // mitigation and is stripped again on import by the same spreadsheets.
  //
  // Only names and notes pass through here; amounts are written with
  // toStringAsFixed, so a negative number never reaches this and never gets a
  // quote in front of it.
  if (s.isNotEmpty && _formulaTriggers.contains(s[0])) {
    s = "'$s";
  }
  if (s.contains(',') ||
      s.contains('"') ||
      s.contains('\n') ||
      s.contains('\r')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

/// Long-format CSV built for analysis, not for eyeballing:
/// one row per transaction, ISO dates, amounts as plain numbers (no ⃁ in the
/// cell, so the column stays numeric), category id and name in separate columns,
/// a recurrence_id so generated rows are distinguishable, and a split_group_id
/// tying together the parts of a split purchase. Prefixed with a
/// UTF-8 BOM so Excel renders the Arabic correctly.
Future<String> buildTransactionsCsv(AppDatabase db) async {
  final fmt = DateFormat('yyyy-MM-dd');
  final txns = await (db.select(db.transactions)
        ..orderBy([(t) => OrderingTerm.asc(t.date)]))
      .get();
  final cats = {for (final c in await db.categoryDao.getAll()) c.id: c};

  final buf = StringBuffer();
  buf.write('\uFEFF'); // BOM
  buf.writeln(
      'id,date,type,amount,category_id,category_name,recurrence_id,note,'
      'split_group_id,refund_of');
  for (final t in txns) {
    final cat = cats[t.categoryId];
    final row = [
      t.id.toString(),
      fmt.format(t.date),
      // A refund is a negative expense in the ledger; say so, so a sheet
      // filtering on "expense" is not left guessing at the sign.
      t.type == TxnType.income
          ? 'income'
          : t.amount < 0
              ? 'refund'
              : 'expense',
      t.amount.toString(),
      t.categoryId.toString(),
      _csvField(cat?.name),
      t.recurrenceId?.toString() ?? '',
      _csvField(t.note),
      // Rows sharing a value are parts of one purchase split across
      // categories; each part is a real expense in its own category.
      t.splitGroupId?.toString() ?? '',
      t.refundOf?.toString() ?? '',
    ];
    buf.writeln(row.join(','));
  }
  return buf.toString();
}

/// Writes the CSV to the app documents directory and returns the file path.
/// (Add `share_plus` to surface a share sheet — see README. The raw SQLite file
/// lives next to it at floos.sqlite if you'd rather query the DB directly.)
Future<String> exportTransactionsCsvToFile(AppDatabase db) async {
  final csv = await buildTransactionsCsv(db);
  final dir = await getApplicationDocumentsDirectory();
  final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  final file = File(p.join(dir.path, 'floos_export_$stamp.csv'));
  await file.writeAsString(csv);
  return file.path;
}

/// The statistics as a spreadsheet: one row per salary cycle, oldest first,
/// with income / spent / saved / remaining / savings rate. Same conventions as
/// the transaction export (numeric cells, ISO dates, UTF-8 BOM).
///
/// Grouped by salary cycle, never by calendar month: the cycle is the app's
/// only period unit, and a calendar-month row splits one salary across two
/// rows — the month it landed in looks rich and the next one looks broke.
Future<String> buildStatsCsv(AppDatabase db, {DateTime? now}) async {
  final rows = await db.transactionDao.watchAllWithCategory().first;
  final contributions = await db.savingsDao.watchAllContributions().first;
  final incomeRules = await db.recurrenceDao.watchByType(TxnType.income).first;
  return statsCsvFor(
      cycleSummaries(rows, contributions, incomeRules, now ?? DateTime.now()));
}

/// The CSV text for [cycles] (newest first, as [cycleSummaries] returns them).
/// `cycle_end` is the cycle's last day, inclusive — the period's own end is
/// exclusive (the next payday), which reads as an off-by-one in a sheet.
String statsCsvFor(List<CycleSummary> cycles) {
  final fmt = DateFormat('yyyy-MM-dd');
  final buf = StringBuffer();
  buf.write('\uFEFF'); // BOM
  buf.writeln(
      'cycle_start,cycle_end,income,spent,saved,remaining,savings_rate');
  for (final s in cycles.reversed) {
    final end = s.period.end;
    final lastDay = DateTime(end.year, end.month, end.day - 1);
    final rate = s.savingsRate;
    buf.writeln([
      fmt.format(s.period.start),
      fmt.format(lastDay),
      s.income.toStringAsFixed(2),
      s.spent.toStringAsFixed(2),
      s.saved.toStringAsFixed(2),
      s.remaining.toStringAsFixed(2),
      rate == null ? '' : (rate * 100).toStringAsFixed(1),
    ].join(','));
  }
  return buf.toString();
}

/// Writes the stats CSV to the app documents directory; returns the path.
Future<String> exportStatsCsvToFile(AppDatabase db) async {
  final csv = await buildStatsCsv(db);
  final dir = await getApplicationDocumentsDirectory();
  final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  final file = File(p.join(dir.path, 'floos_stats_$stamp.csv'));
  await file.writeAsString(csv);
  return file.path;
}
