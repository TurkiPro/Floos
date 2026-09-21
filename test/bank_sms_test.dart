import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:floos/domain/bank_sms.dart';

/// These run against real bank messages in `test/fixtures/bank_sms/`, not
/// hand-written samples. That matters: both bugs the first prototype shipped
/// (`في` swallowing `فيزا`, and `ال?بطاقة` never matching a bare `بطاقة`)
/// were invisible against invented input, and the second one raised no error
/// at all — it just left a field empty.
///
/// See the fixtures README before changing anything here.
void main() {
  // The fixtures are dated Aug–Sep 2026; pin "now" so the plausibility window
  // is deterministic rather than failing once these messages age past it.
  final now = DateTime(2026, 9, 21);

  List<BankMessage> load(String name) => parseBankSms(
        File('test/fixtures/bank_sms/$name').readAsStringSync(),
        now: now,
      );

  late List<BankMessage> sample1;
  late List<BankMessage> sample2;
  late List<BankMessage> all;

  setUp(() {
    sample1 = load('sample_01.txt');
    sample2 = load('sample_02.txt');
    all = [...sample1, ...sample2]..sort((a, b) => a.at!.compareTo(b.at!));
  });

  double sumOf(List<BankMessage> rows, BankTxnKind kind) => rows
      .where((m) => m.kind == kind)
      .fold(0.0, (acc, m) => acc + (m.amount ?? 0));

  group('chunking', () {
    test('splits concatenated messages with no separator', () {
      expect(sample1, hasLength(8));
      expect(sample2, hasLength(5));
    });

    test('every fixture message parses cleanly', () {
      for (final m in all) {
        expect(m.isUsable, isTrue, reason: m.raw);
        expect(m.issues, isEmpty, reason: m.raw);
      }
    });

    test('empty input yields nothing', () {
      expect(parseBankSms('', now: now), isEmpty);
      expect(parseBankSms('   \n  \n', now: now), isEmpty);
    });
  });

  group('amounts', () {
    test('extracted in chronological order', () {
      expect(
        all.map((m) => m.amount).toList(),
        [
          35.0, 34.99, 89.99, 30.0, 60.50, 55.0, 119.90, //
          36.05, 70.0, 23.0, 41.0, 600.0, 100.0,
        ],
      );
    });

    test('currency before OR after the number', () {
      // "شراء عبر نقاط بيع SAR 30" vs "شراء إنترنت 36.05 SAR"
      expect(sample1.firstWhere((m) => m.party == 'RED BOX').amount, 30.0);
      expect(sample1.firstWhere((m) => m.party == 'Keeta').amount, 36.05);
      // "بـ SAR 70.00" vs "بـ 23 SAR"
      expect(sample1.firstWhere((m) => m.party == 'KR-133').amount, 70.0);
      expect(sample1.firstWhere((m) => m.party == 'STC').amount, 23.0);
    });

    test('المبلغ: marks the amount on a transfer', () {
      final transfer =
          sample2.firstWhere((m) => m.kind == BankTxnKind.transferOut);
      expect(transfer.amount, 100.0);
    });

    test('the running balance is never read as the amount', () {
      // The trap: "الرصيد 7,930" sits in the same message as a 70.00 purchase,
      // and "بطاقة 1672*" / "حساب *1000" are four-digit numbers too.
      final m = sample1.firstWhere((m) => m.balance == 7930.0);
      expect(m.amount, 70.0);

      final m2 = sample1.firstWhere((m) => m.balance == 7889.0);
      expect(m2.amount, 41.0);

      final m3 = sample1.firstWhere((m) => m.balance == 19919.35);
      expect(m3.amount, 23.0);
    });

    test('regression: في must not swallow فيزا', () {
      // "في" (the timestamp marker) is a prefix of "فيزا" (Visa), which is the
      // line carrying the amount. Without a letter boundary the skip-list ate
      // the amount of every Visa message.
      final visa = sample2.where((m) => m.balance == 0.40).single;
      expect(visa.amount, 34.99);
      expect(sample2.where((m) => m.balance == 0.21).single.amount, 89.99);
    });
  });

  group('classification', () {
    test('top-ups and transfers are not expenses', () {
      expect(all.where((m) => m.kind == BankTxnKind.topup), hasLength(2));
      expect(all.where((m) => m.kind == BankTxnKind.transferOut), hasLength(1));
      expect(all.where((m) => m.kind == BankTxnKind.expense), hasLength(10));
    });

    test('the money assertion: 560.43 real vs 1295.43 naive', () {
      // Booking every row as an expense inflates this period by 131% AND
      // double counts, because money loaded onto a card is spent later and
      // reported again by its own message. If this fails, classification
      // broke — not the arithmetic.
      expect(sumOf(all, BankTxnKind.expense), closeTo(560.43, 0.005));
      expect(
        all.fold<double>(0, (acc, m) => acc + m.amount!),
        closeTo(1295.43, 0.005),
      );
      expect(sumOf(all, BankTxnKind.topup), closeTo(635.0, 0.005));
      expect(sumOf(all, BankTxnKind.transferOut), closeTo(100.0, 0.005));
    });

    test('unrecognised messages are flagged, never guessed', () {
      final otp = parseBankSms('رمز التحقق 1234 لا تشاركه مع أحد', now: now);
      expect(otp.single.kind, BankTxnKind.unknown);
      expect(otp.single.issues, contains(BankSmsIssue.unclassified));
      expect(otp.single.isUsable, isFalse);
    });

    test('unparseable prose keeps its raw text instead of throwing', () {
      final junk =
          parseBankSms('مرحبا كيف حالك\nهذا ليس رسالة بنكية', now: now);
      expect(junk, isNotEmpty);
      expect(junk.first.raw, isNotEmpty);
      expect(junk.first.issues, contains(BankSmsIssue.unclassified));
    });
  });

  group('dates', () {
    test('time-first and date-first both read correctly', () {
      // "في 18:57 26-09-12" and "في 26-09-14 19:14" — same bank, both orders.
      expect(sample1.firstWhere((m) => m.party == 'RED BOX').at,
          DateTime(2026, 9, 12, 18, 57));
      expect(sample1.firstWhere((m) => m.party == 'KR-133').at,
          DateTime(2026, 9, 14, 19, 14));
    });

    test('a bare timestamp line with no في marker', () {
      final topup = sample2.firstWhere((m) => m.amount == 35.0);
      expect(topup.at, DateTime(2026, 8, 16, 2, 29));
    });

    test('two-digit years are year-first', () {
      // Both senders report 12 Sep 2026 — one as "26-09-12", one as
      // "2026-09-12". That agreement is what settles the ambiguity.
      final twoDigit = sample1.firstWhere((m) => m.party == 'RED BOX').at!;
      final fourDigit = sample2.firstWhere((m) => m.amount == 89.99).at!;
      expect(twoDigit.year, 2026);
      expect(twoDigit.month, 9);
      expect(twoDigit.day, 12);
      expect(fourDigit.year, 2026);
      expect(fourDigit.month, 9);
      expect(fourDigit.day, 12);
    });

    test('paste order is not chronological', () {
      // Keeta (22:27) appears before AMAZON SA (00:33) in the file, but not in
      // time. Anything consuming these must sort by `at`.
      final fileOrder = sample1.map((m) => m.party).toList();
      expect(
          fileOrder.indexOf('Keeta'), lessThan(fileOrder.indexOf('AMAZON SA')));
      expect(
        sample1.firstWhere((m) => m.party == 'AMAZON SA').at!,
        isBefore(sample1.firstWhere((m) => m.party == 'Keeta').at!),
      );
    });

    test('an implausible date is flagged, not filed silently', () {
      // Filing a transaction to the wrong date is the error a user would never
      // notice, so a misread must surface.
      final stale = parseBankSms(
        'شراء عبر نقاط بيع SAR 30\nمن TEST\nفي 18:57 11-09-12',
        now: now,
      ).single;
      expect(stale.issues, contains(BankSmsIssue.dateOutOfWindow));
    });
  });

  group('party', () {
    test('regression: (?:ال)?بطاقة must match a bare بطاقة', () {
      // Written as ال?بطاقة this matches "alef, optional lam, بطاقة" and never
      // matches a bare بطاقة — silently, with no error.
      expect(sample1.where((m) => m.card == '1672'), hasLength(5));
      expect(sample1.where((m) => m.card == '4629'), hasLength(2));
      expect(sample1.where((m) => m.card == '4838'), hasLength(1));
      // "البطاقة: **1672" — the other sender's spelling.
      expect(sample2.firstWhere((m) => m.amount == 35.0).card, '1672');
    });

    test('a message naming only فيزا has no card number', () {
      expect(sample2.firstWhere((m) => m.amount == 34.99).card, isNull);
    });

    test('truncated names are stripped and flagged', () {
      final m = sample1.firstWhere((m) => m.amount == 60.50);
      expect(m.party, 'SALAT ASIA');
      expect(m.partyTruncated, isTrue);
      expect(sample1.firstWhere((m) => m.amount == 55.0).party, 'Ali bin Ab');
    });

    test('the SA / country prefix is removed', () {
      expect(sample1.firstWhere((m) => m.amount == 70.0).party, 'KR-133');
      expect(sample1.firstWhere((m) => m.amount == 23.0).party, 'STC');
      expect(sample1.firstWhere((m) => m.amount == 41.0).party, 'eski kebap');
    });

    test('a missing space after the keyword still parses', () {
      // "لدىAPPLE" — this sender omits the space entirely.
      expect(sample2.firstWhere((m) => m.amount == 34.99).party, 'APPLE');
    });

    test('a transfer destination is captured like a merchant', () {
      final transfer =
          sample2.firstWhere((m) => m.kind == BankTxnKind.transferOut);
      expect(transfer.party, '**7772');
    });

    test('من and لدى are both merchant markers', () {
      expect(sample1.firstWhere((m) => m.amount == 30.0).party, 'RED BOX');
      expect(sample1.firstWhere((m) => m.amount == 119.90).party, 'AMAZON SA');
    });
  });

  group('txnFingerprint', () {
    test('ignores time of day, case and spacing', () {
      expect(
        txnFingerprint(
            amount: 30.0,
            date: DateTime(2026, 9, 12, 18, 57),
            party: 'RED BOX'),
        txnFingerprint(
            amount: 30.0, date: DateTime(2026, 9, 12, 3), party: ' red   box '),
      );
    });

    test('distinguishes amount and day', () {
      final base = txnFingerprint(
          amount: 30.0, date: DateTime(2026, 9, 12), party: 'RED BOX');
      expect(
        base,
        isNot(txnFingerprint(
            amount: 30.50, date: DateTime(2026, 9, 12), party: 'RED BOX')),
      );
      expect(
        base,
        isNot(txnFingerprint(
            amount: 30.0, date: DateTime(2026, 9, 13), party: 'RED BOX')),
      );
    });

    test('a re-pasted message collides with its own first import', () {
      final m = sample1.firstWhere((m) => m.party == 'RED BOX');
      expect(
        txnFingerprint(amount: m.amount!, date: m.at!, party: m.party),
        txnFingerprint(
            amount: 30.0, date: DateTime(2026, 9, 12), party: 'RED BOX'),
      );
    });
  });
}

/// `isBefore` as a matcher, for readability in the ordering test.
Matcher isBefore(DateTime other) => predicate<DateTime>(
      (d) => d.isBefore(other),
      'is before $other',
    );
