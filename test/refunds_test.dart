import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floos/data/backup.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/bank_sms.dart';
import 'package:floos/domain/category_breakdown.dart';
import 'package:floos/domain/financial_period.dart';
import 'package:floos/domain/import_review.dart';
import 'package:floos/domain/statistics_summary.dart';
import 'package:floos/domain/weekly_budget_status.dart';

/// Refunds (schema v17): money that came back, stored as a negative expense in
/// the purchase's category, linked to the purchase when there is one.

/// A refund in the bank's own format. No real refund message has been
/// collected yet; this follows the purchase format in fixtures/bank_sms with
/// the «مرتجع» keyword the parser classifies on.
const _refundSms = 'مرتجع شراء عبر نقاط بيع SAR 30\n'
    'بطاقة 1672* مدى- ApplePay\n'
    'من RED BOX\n'
    'في 10:15 26-09-14';
const _purchaseSms = 'شراء عبر نقاط بيع SAR 30\n'
    'بطاقة 1672* مدى- ApplePay\n'
    'من RED BOX\n'
    'في 18:57 26-09-12';

void main() {
  late AppDatabase db;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
  });

  const food = 1; // seeded expense category
  final day = DateTime(2026, 9, 12);

  Future<int> purchase({double amount = 200, int? recurrenceId}) async {
    final id = await db.transactionDao.add(
        amount: amount,
        categoryId: food,
        type: TxnType.expense,
        date: day,
        note: 'RED BOX');
    if (recurrenceId != null) {
      await (db.update(db.transactions)..where((t) => t.id.equals(id)))
          .write(TransactionsCompanion(recurrenceId: Value(recurrenceId)));
    }
    return id;
  }

  Future<List<Txn>> all() => (db.select(db.transactions)
        ..orderBy([(t) => OrderingTerm.asc(t.id)]))
      .get();

  group('recording a refund', () {
    test('is a negative expense in the purchase\'s category, linked to it',
        () async {
      final id = await purchase();
      await db.transactionDao.addRefund(
          purchaseId: id, amount: 50, date: DateTime(2026, 9, 20));
      final refund = (await all()).last;
      expect(refund.amount, -50);
      expect(refund.type, TxnType.expense);
      expect(refund.categoryId, food);
      expect(refund.refundOf, id);
      expect(refund.note, 'RED BOX');
      expect(refund.date, DateTime(2026, 9, 20),
          reason: 'dated when the money came back, not the purchase');
    });

    test('partial refunds add up, and never past the purchase', () async {
      final id = await purchase();
      await db.transactionDao
          .addRefund(purchaseId: id, amount: 50, date: day);
      expect(await db.transactionDao.unrefunded(id), 150);
      await expectLater(
          db.transactionDao.addRefund(purchaseId: id, amount: 151, date: day),
          throwsArgumentError);
      await db.transactionDao
          .addRefund(purchaseId: id, amount: 150, date: day);
      expect(await db.transactionDao.unrefunded(id), 0);
    });

    test('refuses zero, a refund of a refund, income and recurring rows',
        () async {
      final id = await purchase();
      await expectLater(
          db.transactionDao.addRefund(purchaseId: id, amount: 0, date: day),
          throwsArgumentError);
      final refundId = await db.transactionDao
          .addRefund(purchaseId: id, amount: 10, date: day);
      await expectLater(
          db.transactionDao
              .addRefund(purchaseId: refundId, amount: 5, date: day),
          throwsArgumentError);
      final income = await db.transactionDao.add(
          amount: 100, categoryId: 9, type: TxnType.income, date: day);
      await expectLater(
          db.transactionDao.addRefund(purchaseId: income, amount: 5, date: day),
          throwsArgumentError);

      final ruleId = await db.recurrenceDao.add(
          title: 'اشتراك',
          amount: 40,
          categoryId: food,
          type: TxnType.expense,
          frequency: Frequency.monthly,
          startDate: DateTime(2026, 1, 1));
      final generated = await purchase(amount: 40, recurrenceId: ruleId);
      await expectLater(
          db.transactionDao
              .addRefund(purchaseId: generated, amount: 40, date: day),
          throwsArgumentError);
    });

    test('deleting the purchase keeps the refund, unlinked', () async {
      final id = await purchase();
      await db.transactionDao.addRefund(purchaseId: id, amount: 50, date: day);
      await db.transactionDao.deleteById(id);
      final left = await all();
      expect(left.single.amount, -50);
      expect(left.single.refundOf, isNull,
          reason: 'the money still came back');
    });

    test('a standalone refund needs no purchase', () async {
      await db.transactionDao.addStandaloneRefund(
          amount: 75, categoryId: food, date: day, note: 'قديم');
      final r = (await all()).single;
      expect(r.amount, -75);
      expect(r.refundOf, isNull);
      await expectLater(
          db.transactionDao.addStandaloneRefund(
              amount: 75, categoryId: 9, date: day),
          throwsArgumentError,
          reason: 'income categories do not take refunds');
    });

    test('editing a refund keeps it within the purchase', () async {
      final id = await purchase();
      final r1 = await db.transactionDao
          .addRefund(purchaseId: id, amount: 50, date: day);
      await db.transactionDao
          .addRefund(purchaseId: id, amount: 100, date: day);
      await expectLater(
          db.transactionDao.updateRefund(
              id: r1, amount: 101, date: day, categoryId: food),
          throwsArgumentError);
      await db.transactionDao
          .updateRefund(id: r1, amount: 100, date: day, categoryId: food);
      expect(await db.transactionDao.unrefunded(id), 0);
    });

    test('a refund cannot be split', () async {
      final id = await purchase();
      final r = await db.transactionDao
          .addRefund(purchaseId: id, amount: 50, date: day);
      await expectLater(
          db.transactionDao.saveSplit(r,
              parts: [
                (amount: 25, categoryId: food),
                (amount: 25, categoryId: food),
              ],
              date: day),
          throwsArgumentError);
    });
  });

  group('the streams know what was refunded', () {
    test('across the whole ledger', () async {
      final id = await purchase();
      await db.transactionDao.addRefund(purchaseId: id, amount: 50, date: day);
      final rows = await db.transactionDao.watchAllWithCategory().first;
      expect(rows.firstWhere((r) => r.txn.id == id).refunded, 50);
      expect(rows.firstWhere((r) => r.txn.id != id).isRefund, isTrue);
    });

    test('in a cycle view, even when the refund lands in a later cycle',
        () async {
      final id = await purchase(); // 12 Sep
      await db.transactionDao.addRefund(
          purchaseId: id, amount: 200, date: DateTime(2026, 10, 3));
      final september = await db.transactionDao
          .watchForRange(DateTime(2026, 9, 1), DateTime(2026, 10, 1))
          .first;
      expect(september.single.refunded, 200,
          reason: 'the September purchase shows as fully refunded');
    });
  });

  group('the money', () {
    Category cat({CategoryKind kind = CategoryKind.essential}) => Category(
        id: food,
        name: 'طعام',
        iconKey: 'k',
        colorValue: 0,
        type: TxnType.expense,
        kind: kind,
        archived: false,
        sortOrder: 0);
    TxnRow row(double amount, DateTime date, {int? refundOf}) => TxnRow(
          txn: Txn(
              id: amount.hashCode ^ date.hashCode,
              amount: amount,
              categoryId: food,
              type: TxnType.expense,
              date: date,
              refundOf: refundOf,
              createdAt: date),
          category: cat(),
        );

    test('a refund this week lowers what was spent this week', () {
      final now = DateTime(2026, 7, 20); // week of 15–21 July
      WeeklyBudgetStatus status(List<TxnRow> rows) => weeklyBudgetStatus(
            rows: rows,
            incomeRules: const [],
            expenseRules: const [],
            contributions: const [],
            investments: const [],
            debts: const [],
            now: now,
          );
      final bought = [row(200, DateTime(2026, 7, 16))];
      final refunded = [...bought, row(-50, DateTime(2026, 7, 18))];
      expect(status(bought).spent, 200);
      expect(status(refunded).spent, 150);
    });

    test('a refund is not counted as a purchase', () {
      final rows = [
        row(200, DateTime(2026, 7, 16)),
        row(100, DateTime(2026, 7, 17)),
        row(-50, DateTime(2026, 7, 18)),
      ];
      final stat = categoryBreakdown(rows).single;
      expect(stat.total, 250);
      expect(stat.count, 2);
      expect(stat.average, 125);
    });

    test('stats: counts skip refunds, and a refund-only day spent nothing',
        () {
      final now = DateTime(2026, 7, 20);
      final period = financialPeriod(const [], now); // 1 Jul – 1 Aug
      StatisticsSummary stats(List<TxnRow> rows) => StatisticsSummary.from(
          rows, const [], const [], const [], now, period,
          debts: const []);
      final bought = [row(200, DateTime(2026, 7, 16))];
      final s = stats([
        ...bought,
        row(-50, DateTime(2026, 7, 18)), // the only entry that day
      ]);
      expect(s.txnCountThisMonth, 1);
      expect(s.spentThisMonth, 150);
      expect(s.noSpendDays, stats(bought).noSpendDays,
          reason: 'the 18th, with only a refund, spent nothing');
    });
  });

  group('import', () {
    test('a refund message is a refund, even when the party has an expense '
        'rule (the live bug)', () async {
      // Before this, the parser classified the message but nothing read the
      // classification: the rule "RED BOX → food" turned the money coming
      // back into a second purchase.
      final rule = PartyRule(
        id: 1,
        partyKey: 'red box',
        rawParty: 'RED BOX',
        disposition: PartyDisposition.expense,
        categoryId: food,
        createdAt: day,
      );
      final drafts = parseBankSms(_refundSms, now: DateTime(2026, 9, 20));
      expect(drafts.single.kind, BankTxnKind.refund);
      final reviewed = reviewDrafts(
        drafts: drafts,
        ledgerFingerprints: const {},
        recurringCharges: const [],
        lookupRule: (_) => rule,
      );
      final batch = await db.importBatchDao.commitImport([
        ResolvedImportRow(
          amount: reviewed.single.message.amount!,
          date: reviewed.single.message.at!,
          party: 'RED BOX',
          displayName: null,
          disposition: PartyDisposition.expense,
          categoryId: food,
          ruleAlreadyExisted: true,
          refund: true,
        ),
      ]);
      final written = (await all()).single;
      expect(written.amount, -30, reason: 'money back, not a purchase');
      expect(written.importBatchId, batch);
      expect((await db.importBatchDao.latest())!.totalAmount, -30);
    });

    test('a purchase and its same-day refund are not duplicates', () {
      final refundSameDay = _refundSms.replaceFirst('26-09-14', '26-09-12');
      final drafts = parseBankSms('$_purchaseSms\n$refundSameDay',
          now: DateTime(2026, 9, 20));
      final reviewed = reviewDrafts(
        drafts: drafts,
        ledgerFingerprints: const {},
        recurringCharges: const [],
        lookupRule: (_) => null,
      );
      expect(reviewed.map((r) => r.status),
          everyElement(DraftStatus.fresh));
    });

    test('an already-imported refund is a duplicate on re-paste', () async {
      final id = await purchase(amount: 30);
      await db.transactionDao.addRefund(
          purchaseId: id, amount: 30, date: DateTime(2026, 9, 14, 10, 15));
      final reviewed = reviewDrafts(
        drafts: parseBankSms(_refundSms, now: DateTime(2026, 9, 20)),
        ledgerFingerprints: ledgerFingerprints(await all()),
        recurringCharges: const [],
        lookupRule: (_) => null,
      );
      expect(reviewed.single.status, DraftStatus.duplicateOfLedger);
    });

    test('a refund never collides with a recurring charge', () {
      final reviewed = reviewDrafts(
        drafts: parseBankSms(_refundSms, now: DateTime(2026, 9, 20)),
        ledgerFingerprints: const {},
        recurringCharges: [
          RecurringCharge(amount: 30, date: DateTime(2026, 9, 14))
        ],
        lookupRule: (_) => null,
      );
      expect(reviewed.single.status, DraftStatus.fresh);
    });

    test('finds the purchase a refund is for', () async {
      final older = await purchase(amount: 30);
      await (db.update(db.transactions)..where((t) => t.id.equals(older)))
          .write(TransactionsCompanion(date: Value(DateTime(2026, 8, 1))));
      final recent = await purchase(amount: 30); // 12 Sep
      await purchase(amount: 10); // too small to be refunded 30
      final ledger = await all();

      final target = findRefundTarget(ledger,
          amount: 30, date: DateTime(2026, 9, 14), label: 'RED BOX');
      expect(target?.id, recent, reason: 'the most recent that fits');

      expect(
          findRefundTarget(ledger,
              amount: 30, date: DateTime(2026, 9, 14), label: 'Jahez'),
          isNull,
          reason: 'another merchant');
      expect(
          findRefundTarget(ledger,
              amount: 30, date: DateTime(2027, 1, 1), label: 'RED BOX'),
          isNull,
          reason: 'past the 90-day window');

      await db.transactionDao
          .addRefund(purchaseId: recent, amount: 30, date: day);
      final after = findRefundTarget(await all(),
          amount: 30, date: DateTime(2026, 9, 14), label: 'RED BOX');
      expect(after?.id, older,
          reason: 'a purchase already fully refunded is skipped');
    });
  });

  group('backup', () {
    test('refunds survive, even when listed before their purchase', () async {
      final id = await purchase();
      await db.transactionDao.addRefund(purchaseId: id, amount: 50, date: day);
      final map =
          jsonDecode(await buildBackupJson(db)) as Map<String, dynamic>;
      // Put the refund first: restore must still satisfy the foreign key.
      (map['transactions'] as List).sort((a, b) => ((b as Map)['id'] as int)
          .compareTo((a as Map)['id'] as int));

      final target = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(target.close);
      await restoreBackupJson(target, jsonEncode(map));
      final rows = await target.select(target.transactions).get();
      expect(rows.firstWhere((t) => t.amount < 0).refundOf, id);
    });

    test('a pre-v17 backup restores with no links', () async {
      await db.transactionDao.addStandaloneRefund(
          amount: 20, categoryId: food, date: day);
      final map =
          jsonDecode(await buildBackupJson(db)) as Map<String, dynamic>;
      for (final t in map['transactions'] as List) {
        (t as Map<String, dynamic>).remove('refundOf');
      }
      final target = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(target.close);
      await restoreBackupJson(target, jsonEncode(map));
      expect((await target.select(target.transactions).get()).single.refundOf,
          isNull);
    });
  });
}
