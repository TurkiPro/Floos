/// Decides what the app already knows about each parsed bank message, before
/// any of it reaches the ledger.
///
/// Pure: it takes plain lists rather than a database, so the rules that protect
/// the ledger are testable without a device.
///
/// Nothing here rejects a draft. Every message comes back, and anything that
/// looks like a duplicate is marked and left unchecked for the user to
/// override. Silently dropping a row is the one failure mode that would make
/// the whole feature untrustworthy.
library;

import '../data/database.dart';
import 'bank_sms.dart';

/// Why a draft might not want importing.
enum DraftStatus {
  /// Not seen before — safe to import.
  fresh,

  /// A transaction with this amount, day and party is already in the ledger.
  /// Re-pasting an overlapping range is the normal case, not the exception.
  duplicateOfLedger,

  /// The same message appears earlier in this same paste.
  duplicateInPaste,

  /// The recurrence engine has already booked this charge, or is about to.
  recurrenceCollision,
}

/// A charge the recurrence engine owns — either one it has already
/// materialized, or the next occurrence of an active rule.
///
/// This exists because the importer is the *second* writer to the transactions
/// ledger. `README.md` calls the recurrence engine the sole writer of generated
/// rows; a subscription that has a rule AND arrives as a bank SMS would
/// otherwise be booked twice, silently, every month.
class RecurringCharge {
  final double amount;
  final DateTime date;
  const RecurringCharge({required this.amount, required this.date});
}

/// One parsed message plus what the app knows about it.
class ReviewedDraft {
  final BankMessage message;
  final DraftStatus status;

  /// The remembered decision for this party, if there is one. When set, the
  /// row arrives already resolved — which is what turns a long review into
  /// scrolling and confirming.
  final PartyRule? rule;

  const ReviewedDraft({
    required this.message,
    required this.status,
    required this.rule,
  });

  /// Only fresh rows are checked by default. Everything else is shown, dimmed,
  /// with its reason.
  bool get suggestedForImport =>
      status == DraftStatus.fresh && message.isUsable;
}

/// How close a draft has to be to a recurring charge to count as the same one.
/// A bank posts a subscription a day or two either side of its nominal date.
const _recurrenceWindow = Duration(days: 3);

/// Classifies [drafts] against the ledger, the recurrence engine and the
/// remembered party rules.
///
/// Returns them sorted by [BankMessage.at] — paste order is not chronological
/// (a real sample has 22:27 filed before 00:33 of the same day), and a second
/// paste merged with a first has no meaningful order at all. Drafts that failed
/// to parse a date sort last, since there is nothing to order them by.
List<ReviewedDraft> reviewDrafts({
  required List<BankMessage> drafts,
  required Set<String> ledgerFingerprints,
  required List<RecurringCharge> recurringCharges,
  required PartyRule? Function(String party) lookupRule,
}) {
  final sorted = [...drafts]..sort((a, b) {
      final at = a.at;
      final bt = b.at;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return at.compareTo(bt);
    });

  final seenInPaste = <String>{};
  final out = <ReviewedDraft>[];

  for (final message in sorted) {
    final rule = message.party == null ? null : lookupRule(message.party!);
    final amount = message.amount;
    final at = message.at;

    // Without an amount and a date there is nothing to compare, so it can only
    // be fresh — it will be carrying issues and needs manual attention anyway.
    if (amount == null || at == null) {
      out.add(ReviewedDraft(
        message: message,
        status: DraftStatus.fresh,
        rule: rule,
      ));
      continue;
    }

    // Fingerprint on the label the import would actually WRITE, not the bank's
    // raw string. Once a party has been given a display name, that name is what
    // lands in the transaction note — so comparing raw parties here would miss
    // every duplicate for exactly the merchants the user has bothered to name.
    final display = rule?.displayName?.trim();
    final label =
        (display != null && display.isNotEmpty) ? display : message.party;

    final fingerprint = txnFingerprint(
      amount: amount,
      date: at,
      party: label,
    );

    final DraftStatus status;
    if (ledgerFingerprints.contains(fingerprint)) {
      status = DraftStatus.duplicateOfLedger;
    } else if (seenInPaste.contains(fingerprint)) {
      status = DraftStatus.duplicateInPaste;
    } else if (_collidesWithRecurrence(amount, at, recurringCharges)) {
      status = DraftStatus.recurrenceCollision;
    } else {
      status = DraftStatus.fresh;
    }
    seenInPaste.add(fingerprint);

    out.add(ReviewedDraft(message: message, status: status, rule: rule));
  }

  return out;
}

bool _collidesWithRecurrence(
  double amount,
  DateTime at,
  List<RecurringCharge> charges,
) {
  for (final charge in charges) {
    if ((charge.amount - amount).abs() >= 0.005) continue;
    final gap = charge.date.difference(at).abs();
    if (gap <= _recurrenceWindow) return true;
  }
  return false;
}
