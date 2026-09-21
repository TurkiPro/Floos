import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/bank_sms.dart';
import 'package:floos/domain/import_review.dart';

void main() {
  final now = DateTime(2026, 9, 21);

  List<BankMessage> load(String name) => parseBankSms(
        File('test/fixtures/bank_sms/$name').readAsStringSync(),
        now: now,
      );

  late List<BankMessage> sample1;
  late List<BankMessage> sample2;

  setUp(() {
    sample1 = load('sample_01.txt');
    sample2 = load('sample_02.txt');
  });

  List<ReviewedDraft> review(
    List<BankMessage> drafts, {
    Set<String> ledger = const {},
    List<RecurringCharge> recurring = const [],
    PartyRule? Function(String)? lookup,
  }) =>
      reviewDrafts(
        drafts: drafts,
        ledgerFingerprints: ledger,
        recurringCharges: recurring,
        lookupRule: lookup ?? (_) => null,
      );

  Set<String> fingerprintsOf(List<BankMessage> drafts) => {
        for (final m in drafts)
          if (m.amount != null && m.at != null)
            txnFingerprint(amount: m.amount!, date: m.at!, party: m.party),
      };

  group('first import', () {
    test('everything is fresh against an empty ledger', () {
      final reviewed = review([...sample1, ...sample2]);
      expect(reviewed, hasLength(13));
      expect(
        reviewed.every((r) => r.status == DraftStatus.fresh),
        isTrue,
      );
    });

    test('results are sorted by parsed time, not paste order', () {
      final reviewed = review(sample1);
      final parties = reviewed.map((r) => r.message.party).toList();
      // AMAZON SA (00:33) sits after Keeta (22:27) in the file but before it
      // in time.
      expect(parties.indexOf('AMAZON SA'), lessThan(parties.indexOf('Keeta')));
      final times = reviewed.map((r) => r.message.at!).toList();
      for (var i = 1; i < times.length; i++) {
        expect(times[i].isBefore(times[i - 1]), isFalse);
      }
    });
  });

  group('duplicates', () {
    test('re-pasting the same batch marks every row as already in the ledger',
        () {
      // The overlapping-paste case, which happens on every real import.
      final reviewed = review(sample1, ledger: fingerprintsOf(sample1));
      expect(reviewed, hasLength(8));
      expect(
        reviewed.every((r) => r.status == DraftStatus.duplicateOfLedger),
        isTrue,
      );
      expect(reviewed.any((r) => r.suggestedForImport), isFalse,
          reason: 'nothing is checked by default on a full re-paste');
    });

    test('a partially overlapping paste keeps the new rows fresh', () {
      final reviewed = review(
        [...sample1, ...sample2],
        ledger: fingerprintsOf(sample1),
      );
      final dupes =
          reviewed.where((r) => r.status == DraftStatus.duplicateOfLedger);
      final fresh = reviewed.where((r) => r.status == DraftStatus.fresh);
      expect(dupes, hasLength(8));
      expect(fresh, hasLength(5));
    });

    test('the same message twice in one paste flags only the second', () {
      final reviewed = review([...sample1, ...sample1]);
      expect(
        reviewed.where((r) => r.status == DraftStatus.duplicateInPaste),
        hasLength(8),
      );
      expect(
          reviewed.where((r) => r.status == DraftStatus.fresh), hasLength(8));
    });

    test('nothing is ever dropped', () {
      final reviewed = review(sample1, ledger: fingerprintsOf(sample1));
      expect(reviewed, hasLength(sample1.length),
          reason: 'duplicates are shown and unchecked, never removed');
      expect(reviewed.every((r) => r.message.raw.isNotEmpty), isTrue);
    });
  });

  group('recurrence collision', () {
    test('a charge the engine already booked is flagged', () {
      // The APPLE subscription: 89.99 on 12 Sep. If a recurrence rule also
      // produces it, importing would book it twice — silently, every month.
      final reviewed = review(
        sample2,
        recurring: [
          RecurringCharge(amount: 89.99, date: DateTime(2026, 9, 12)),
        ],
      );
      final apple = reviewed.firstWhere((r) => r.message.amount == 89.99);
      expect(apple.status, DraftStatus.recurrenceCollision);
      expect(apple.suggestedForImport, isFalse);
    });

    test('tolerates a bank posting a day or two off', () {
      final reviewed = review(
        sample2,
        recurring: [
          RecurringCharge(amount: 89.99, date: DateTime(2026, 9, 14)),
        ],
      );
      expect(
        reviewed.firstWhere((r) => r.message.amount == 89.99).status,
        DraftStatus.recurrenceCollision,
      );
    });

    test('the same amount in a different month does not collide', () {
      final reviewed = review(
        sample2,
        recurring: [
          RecurringCharge(amount: 89.99, date: DateTime(2026, 8, 1)),
        ],
      );
      expect(
        reviewed.firstWhere((r) => r.message.amount == 89.99).status,
        DraftStatus.fresh,
      );
    });

    test('a different amount on the same day does not collide', () {
      final reviewed = review(
        sample2,
        recurring: [
          RecurringCharge(amount: 34.99, date: DateTime(2026, 9, 12)),
        ],
      );
      expect(
        reviewed.firstWhere((r) => r.message.amount == 89.99).status,
        DraftStatus.fresh,
      );
    });
  });

  group('remembered rules', () {
    test('a known party arrives pre-resolved', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.partyRuleDao.remember(
        rawParty: 'RED BOX',
        disposition: PartyDisposition.expense,
        categoryId: 1,
        displayName: 'ريد بوكس',
      );
      final rules = {
        for (final r in await db.partyRuleDao.getAll()) r.rawParty: r,
      };

      final reviewed = review(sample1, lookup: (p) => rules[p]);
      final redBox = reviewed.firstWhere((r) => r.message.party == 'RED BOX');
      expect(redBox.rule, isNotNull);
      expect(redBox.rule!.displayName, 'ريد بوكس');
      expect(redBox.suggestedForImport, isTrue);

      // An unknown merchant still needs a decision.
      expect(
          reviewed.firstWhere((r) => r.message.party == 'Keeta').rule, isNull);
    });

    test('a renamed party still matches its own ledger row', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      // First import: the user names KR-133 something readable. commitImport
      // writes that name as the transaction note.
      await db.importBatchDao.commitImport([
        ResolvedImportRow(
          amount: 70,
          date: DateTime(2026, 9, 14, 19, 14),
          party: 'KR-133',
          displayName: 'مطعم الحارة',
          disposition: PartyDisposition.expense,
          categoryId: 1,
        ),
      ]);
      final stored = (await db.select(db.transactions).get()).single;
      final ledger = {
        txnFingerprint(
          amount: stored.amount,
          date: stored.date,
          party: stored.note,
        ),
      };
      final rules = {
        for (final r in await db.partyRuleDao.getAll()) r.rawParty: r,
      };

      // Re-pasting the same message must still be recognised, even though the
      // bank says "KR-133" and the ledger says "مطعم الحارة".
      final reviewed = review(sample1, ledger: ledger, lookup: (p) => rules[p]);
      final row = reviewed.firstWhere((r) => r.message.party == 'KR-133');
      expect(row.status, DraftStatus.duplicateOfLedger);
      expect(row.suggestedForImport, isFalse);
    });
  });

  group('unparseable drafts', () {
    test('survive review carrying their issues, and are not auto-checked', () {
      final junk = parseBankSms('رمز التحقق 1234 لا تشاركه', now: now);
      final reviewed = review(junk);
      expect(reviewed, hasLength(1));
      expect(reviewed.single.status, DraftStatus.fresh);
      expect(reviewed.single.message.issues, isNotEmpty);
      expect(reviewed.single.suggestedForImport, isFalse,
          reason: 'an unusable draft must not be silently imported');
    });
  });
}
