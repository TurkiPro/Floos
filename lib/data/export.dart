import 'dart:io';

import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/period_summary.dart';
import 'database.dart';
import 'enums.dart';

String _csvField(String? v) {
  final s = v ?? '';
  if (s.contains(',') ||
      s.contains('"') ||
      s.contains('\n') ||
      s.contains('\r')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

/// Long-format CSV built for analysis, not for eyeballing:
/// one row per transaction, ISO dates, amounts as plain numbers (no ر.س in the
/// cell, so the column stays numeric), category id and name in separate columns,
/// and a recurrence_id so generated rows are distinguishable. Prefixed with a
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
      'id,date,type,amount,category_id,category_name,recurrence_id,note');
  for (final t in txns) {
    final cat = cats[t.categoryId];
    final row = [
      t.id.toString(),
      fmt.format(t.date),
      t.type == TxnType.expense ? 'expense' : 'income',
      t.amount.toString(),
      t.categoryId.toString(),
      _csvField(cat?.name),
      t.recurrenceId?.toString() ?? '',
      _csvField(t.note),
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

/// The statistics as a spreadsheet: one section of per-month rows and one of
/// per-year rows, each with income / spent / saved / remaining / savings rate.
/// Same conventions as the transaction export (numeric cells, UTF-8 BOM).
Future<String> buildStatsCsv(AppDatabase db) async {
  final rows = await db.transactionDao.watchAllWithCategory().first;
  final contributions = await db.savingsDao.watchAllContributions().first;

  final buf = StringBuffer();
  buf.write('﻿'); // BOM

  void section(String period, List<PeriodSummary> summaries) {
    buf.writeln('$period,income,spent,saved,remaining,savings_rate');
    for (final s in summaries) {
      final label = s.month == null
          ? '${s.year}'
          : '${s.year}-${s.month.toString().padLeft(2, '0')}';
      final rate = s.savingsRate;
      buf.writeln([
        label,
        s.income.toStringAsFixed(2),
        s.spent.toStringAsFixed(2),
        s.saved.toStringAsFixed(2),
        s.remaining.toStringAsFixed(2),
        rate == null ? '' : (rate * 100).toStringAsFixed(1),
      ].join(','));
    }
  }

  section('month', monthlySummaries(rows, contributions));
  buf.writeln();
  section('year', yearlySummaries(rows, contributions));

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
