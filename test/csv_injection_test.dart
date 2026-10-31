import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/data/export.dart';

/// The CSV is built to be opened in a spreadsheet, and every major one executes
/// a cell that begins with =, +, - or @.
///
/// The note column carries merchant strings lifted out of received bank SMS, so
/// what lands in a cell is no longer only what the user typed.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
  });

  Future<String> csvWithNote(String note) async {
    await db.transactionDao.add(
      amount: 30,
      categoryId: 1,
      type: TxnType.expense,
      date: DateTime(2026, 10, 31),
      note: note,
    );
    return buildTransactionsCsv(db);
  }

  for (final payload in const [
    '=1+1',
    '+1234',
    '-2+3',
    '@SUM(A1:A9)',
    '=cmd|\'/c calc\'!A0',
  ]) {
    test('a note starting with ${payload[0]} is not left executable', () async {
      final csv = await csvWithNote(payload);
      expect(csv, contains("'$payload"),
          reason: 'the cell must be prefixed so it reads as text');
      // The raw payload must never appear at the start of a cell.
      expect(csv, isNot(contains(',$payload')));
    });
  }

  test('ordinary text is left exactly as it was', () async {
    final csv = await csvWithNote('قهوة الصباح');
    expect(csv, contains('قهوة الصباح'));
    expect(csv, isNot(contains("'قهوة")));
  });

  test('a payload that also needs quoting gets both treatments', () async {
    final csv = await csvWithNote('=HYPERLINK("http://x","y")');
    // Prefixed AND wrapped, with the inner quotes doubled.
    expect(csv, contains('"\'=HYPERLINK(""http://x"",""y"")"'));
  });

  test('amounts are untouched — a negative is a number, not a formula',
      () async {
    await db.transactionDao.add(
      amount: 30,
      categoryId: 1,
      type: TxnType.expense,
      date: DateTime(2026, 10, 31),
    );
    final csv = await buildTransactionsCsv(db);
    expect(csv, isNot(contains("'30")));
    expect(csv, isNot(contains("'-")));
  });
}
