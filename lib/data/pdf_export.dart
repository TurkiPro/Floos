import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'database.dart';
import 'enums.dart';

/// A human-readable PDF statement of every transaction, newest first, in a
/// right-to-left layout using the bundled Tajawal font so Arabic shapes
/// correctly. Pure Dart (the `pdf` package) — it writes the bytes to a file the
/// caller hands to the OS share sheet, exactly like the CSV and backup exports.
/// The file never leaves the user's control; no server is involved.
Future<File> writeTransactionsPdf(AppDatabase db) async {
  final rows = await db.transactionDao.watchAllWithCategory().first;
  final money = NumberFormat('#,##0.00');
  final dateFmt = DateFormat('yyyy-MM-dd');

  final base =
      pw.Font.ttf(await rootBundle.load('assets/fonts/Tajawal-Regular.ttf'));
  final bold =
      pw.Font.ttf(await rootBundle.load('assets/fonts/Tajawal-Bold.ttf'));

  var totalIncome = 0.0, totalExpense = 0.0;
  for (final r in rows) {
    if (r.txn.type == TxnType.income) {
      totalIncome += r.txn.amount;
    } else {
      totalExpense += r.txn.amount;
    }
  }

  final sorted = [...rows]..sort((a, b) => b.txn.date.compareTo(a.txn.date));

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      theme: pw.ThemeData.withFont(base: base, bold: bold),
      textDirection: pw.TextDirection.rtl,
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        pw.Header(
          level: 0,
          child: pw.Text('فلوس — كشف الحركات',
              style: pw.TextStyle(font: bold, fontSize: 20)),
        ),
        pw.Text('تاريخ التصدير: ${dateFmt.format(DateTime.now())}'),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('إجمالي الدخل: ${money.format(totalIncome)} ر.س'),
            pw.Text('إجمالي المصروف: ${money.format(totalExpense)} ر.س'),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(font: bold),
          cellAlignment: pw.Alignment.centerRight,
          headerAlignment: pw.Alignment.centerRight,
          headers: const ['التاريخ', 'الفئة', 'النوع', 'المبلغ', 'ملاحظة'],
          data: [
            for (final r in sorted)
              [
                dateFmt.format(r.txn.date),
                r.category.name,
                r.txn.type == TxnType.income ? 'دخل' : 'مصروف',
                money.format(r.txn.amount),
                r.txn.note ?? '',
              ],
          ],
        ),
      ],
    ),
  );

  final dir = await getApplicationDocumentsDirectory();
  final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  final file = File(p.join(dir.path, 'floos_$stamp.pdf'));
  await file.writeAsBytes(await doc.save());
  return file;
}
