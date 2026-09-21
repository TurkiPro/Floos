import 'parse_amount.dart';

/// Parses a pasted batch of Saudi bank notification SMS into draft
/// transactions, so a month of spending can be entered by pasting instead of
/// retyping each row and cross-checking amounts and dates against the Messages
/// app.
///
/// This is pure: no I/O, no database, no network. It knows nothing about
/// categories or goals — deciding what a merchant *means* is the party-rules
/// layer's job. All this does is read what the bank said.
///
/// Two things about real bank SMS drive the whole design:
///
/// **Not every message is spending.** `إضافة اموال` (topping up a card or
/// wallet) and `حوالة صادرة` (an outgoing transfer) move the user's own money.
/// Importing them as expenses inflates spending — and the top-up case double
/// counts, because money loaded onto a card is spent later and reported again
/// by its own message. Hence [BankTxnKind]: classification matters more here
/// than extraction does.
///
/// **The balance line is a trap.** Messages carry `الرصيد 7,930` right next to
/// an amount of `70.00`, and `بطاقة 1672*` / `حساب *1000` contain four-digit
/// numbers. Anything that scans for "the first number" files a 7,930 riyal
/// expense. The amount is only ever read from a line that is not known
/// metadata.
///
/// Formats vary *within* a single bank — the currency can come before or after
/// the amount, the date before or after the time, and one sender omits the
/// space after its Arabic keywords entirely (`لدىAPPLE`). Every rule below is
/// there because a real message broke the obvious version of it.

/// What a bank message says happened. Only [expense] and [income] are
/// spending/earning; the rest exist so the importer can refuse to book them.
enum BankTxnKind {
  /// A purchase — `شراء`.
  expense,

  /// Money loaded onto a card or wallet — `إضافة اموال`. The user's own money
  /// moving. Booking this double counts the purchases that follow it.
  topup,

  /// An outgoing transfer — `حوالة`/`تحويل`. Could be savings, a bill, or a
  /// person; only the user knows, so the importer asks once and remembers.
  transferOut,

  /// Salary or a deposit — `راتب`/`إيداع`.
  income,

  /// A refund or reversal — `مرتجع`/`استرجاع`.
  refund,

  /// Nothing recognisable (an OTP, a promotion, a balance notice). Never
  /// booked without the user saying what it is.
  unknown,
}

/// Machine-readable reasons a draft needs a human look. Kept as constants so
/// tests and the review UI agree on the spelling.
abstract final class BankSmsIssue {
  static const noAmount = 'NO_AMOUNT';
  static const noDate = 'NO_DATE';
  static const noParty = 'NO_PARTY';
  static const unclassified = 'UNCLASSIFIED';

  /// The parsed date is in the future or implausibly old, which usually means
  /// the day/year fields were read in the wrong order.
  static const dateOutOfWindow = 'DATE_OUT_OF_WINDOW';
}

/// One message's worth of extracted fields. Every field is nullable because a
/// bank can change its template at any time: a draft that fails to parse comes
/// back with [issues] set and [raw] intact so the UI can show it for manual
/// entry, rather than being dropped silently.
class BankMessage {
  /// The original lines, joined. Shown when parsing fell short.
  final String raw;
  final double? amount;

  /// The merchant (`من`/`لدى`) or transfer destination (`إلى`), with the
  /// bank's `SA /` country prefix and truncation marker removed.
  final String? party;

  /// The bank cut the name off with a trailing `*` (`SALAT ASIA*`). The
  /// truncation is stable, so the short form is still a usable lookup key.
  final bool partyTruncated;
  final DateTime? at;

  /// Last four digits of the card, when the message names one. Some messages
  /// say only `فيزا` and give no number at all.
  final String? card;

  /// The running balance, captured onto its own field purely so it is
  /// provably not being read as [amount].
  ///
  /// Do not reason across messages with this: the corpus uses `رصيد` for two
  /// different quantities — an account balance on one card, the remaining
  /// value on a prepaid card on another.
  final double? balance;
  final BankTxnKind kind;
  final List<String> issues;

  const BankMessage({
    required this.raw,
    required this.amount,
    required this.party,
    required this.partyTruncated,
    required this.at,
    required this.card,
    required this.balance,
    required this.kind,
    required this.issues,
  });

  /// True when there is enough here to offer the user a pre-filled row.
  bool get isUsable =>
      amount != null && at != null && kind != BankTxnKind.unknown;
}

/// Arabic keywords are matched at the start of a line, so a keyword that is a
/// *prefix* of a longer word would swallow the wrong line. This was not
/// hypothetical: `في` ("in", the timestamp marker) is a prefix of `فيزا`
/// ("Visa"), which is the line carrying the amount — a bare `^في` in the
/// metadata skip-list silently ate the amount of every Visa message. Requiring
/// the keyword not to run into another Arabic letter fixes the whole class.
const _arBoundary = r'(?![\u0600-\u06FF])';

/// A new message starts at a line opening with a transaction verb. Pasted
/// batches arrive concatenated with no separator of any kind.
final _opener =
    RegExp(r'^(شراء|حوالة|إيداع|سحب|مرتجع|استرجاع|تحويل|إضافة|راتب)');

/// Lines the amount is never read from. `المبلغ` is deliberately absent: on a
/// transfer that line *is* the amount.
// NB: concatenated, not interpolated — these patterns are raw strings, where
// `$_arBoundary` would stay literal text and the `$` would read as end-of-line.
final _notAmount =
    RegExp(r'^(البطاقة|بطاقة|حساب|من|لدى|إلى|في|الرصيد|رصيد)' + _arBoundary);

// Both orders occur, sometimes from the same bank: "SAR 30" and "36.05 SAR".
final _sarThenAmount = RegExp(r'SAR\s*([\d,٠-٩۰-۹]+(?:[.٫][\d٠-٩۰-۹]+)?)');
final _amountThenSar = RegExp(r'([\d,٠-٩۰-۹]+(?:[.٫][\d٠-٩۰-۹]+)?)\s*SAR');

/// `\s*` not `\s+`, and `:?` — one sender writes `لدىAPPLE` with no space, and
/// another writes `إلى : **7772` with a space before the colon.
final _party = RegExp(r'^(?:من|لدى|إلى)' + _arBoundary + r'\s*:?\s*(.+)$');

final _ymd4 = RegExp(r'(\d{4})-(\d{2})-(\d{2})'); // 2026-08-16
final _ymd2 = RegExp(r'(\d{2})-(\d{2})-(\d{2})'); // 26-09-12, year first
final _hm = RegExp(r'(\d{1,2}):(\d{2})');

/// `(?:ال)?` must be a group. Written as `ال?بطاقة` it reads "alef, optional
/// lam, بطاقة" and never matches a bare `بطاقة` — which failed silently,
/// leaving the card empty on most rows with no error at all.
final _card = RegExp(r'(?:ال)?بطاقة[^\d]*(\d{4})');

final _balance =
    RegExp(r'^(?:الرصيد|رصيد)' + _arBoundary + r'\s*:?\s*([\d,]+(?:\.\d+)?)');

/// Strips the `SA /` or `SA/` country prefix the credit-card messages carry.
final _countryPrefix = RegExp(r'^SA\s*/\s*');

/// Splits [raw] into messages and extracts a draft from each.
///
/// Never throws. Anything unparseable comes back as a [BankMessage] carrying
/// [issues] and its [raw] text, because silently dropping a row is the one
/// failure mode that would make the whole feature untrustworthy.
///
/// [now] is injectable so the plausibility window in [_sanityCheck] is
/// deterministic under test.
List<BankMessage> parseBankSms(String raw, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  return _chunk(raw).map((lines) => _parseOne(lines, reference)).toList();
}

/// Groups lines into per-message blocks. Blank lines go first, because a
/// forwarded batch may or may not have them and they carry no information.
List<List<String>> _chunk(String raw) {
  final lines =
      raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final out = <List<String>>[];
  for (final line in lines) {
    if (out.isEmpty || _opener.hasMatch(line)) {
      out.add(<String>[line]);
    } else {
      out.last.add(line);
    }
  }
  return out;
}

BankMessage _parseOne(List<String> lines, DateTime now) {
  final issues = <String>[];
  double? amount;
  String? party;
  var partyTruncated = false;
  DateTime? at;
  String? card;
  double? balance;

  for (final line in lines) {
    if (amount == null && !_notAmount.hasMatch(line)) {
      amount = _amountIn(line);
    }
    if (party == null) {
      final match = _party.firstMatch(line);
      if (match != null) {
        var value = match.group(1)!.trim().replaceFirst(_countryPrefix, '');
        if (value.endsWith('*')) {
          partyTruncated = true;
          value = value.substring(0, value.length - 1);
        }
        value = value.trim();
        if (value.isNotEmpty) party = value;
      }
    }
    at ??= _dateTimeIn(line);
    final cardMatch = _card.firstMatch(line);
    if (cardMatch != null) card = cardMatch.group(1);
    final balanceMatch = _balance.firstMatch(line);
    if (balanceMatch != null) {
      balance = double.tryParse(balanceMatch.group(1)!.replaceAll(',', ''));
    }
  }

  final kind = _classify(lines.first);

  if (amount == null) issues.add(BankSmsIssue.noAmount);
  if (at == null) issues.add(BankSmsIssue.noDate);
  if (party == null && kind == BankTxnKind.expense) {
    issues.add(BankSmsIssue.noParty);
  }
  if (kind == BankTxnKind.unknown) issues.add(BankSmsIssue.unclassified);
  if (at != null && !_isPlausible(at, now)) {
    issues.add(BankSmsIssue.dateOutOfWindow);
  }

  return BankMessage(
    raw: lines.join('\n'),
    amount: amount,
    party: party,
    partyTruncated: partyTruncated,
    at: at,
    card: card,
    balance: balance,
    kind: kind,
    issues: issues,
  );
}

/// Reads an amount from a line already known not to be metadata, accepting the
/// currency on either side. The captured digits go through
/// [normalizeAmountInput] so an Arabic-Indic amount parses like any other.
double? _amountIn(String line) {
  final match =
      _sarThenAmount.firstMatch(line) ?? _amountThenSar.firstMatch(line);
  if (match == null) return null;
  return double.tryParse(normalizeAmountInput(match.group(1)!));
}

/// Reads the timestamp from [line], if it holds one.
///
/// Deliberately not positional: senders emit both `في 18:57 26-09-12` and
/// `في 26-09-14 19:14`, and one drops the `في` marker altogether and writes a
/// bare `2026-08-16 02:29`. The token containing `-` is the date and the token
/// containing `:` is the time, wherever they sit.
///
/// Two-digit years are year-first (`26-09-12` is 12 September 2026), confirmed
/// by the same day appearing as `2026-09-12` from another sender.
DateTime? _dateTimeIn(String line) {
  final four = _ymd4.firstMatch(line);
  final two = four == null ? _ymd2.firstMatch(line) : null;
  final date = four ?? two;
  if (date == null) return null;
  final year = four != null
      ? int.parse(date.group(1)!)
      : 2000 + int.parse(date.group(1)!);
  final month = int.parse(date.group(2)!);
  final day = int.parse(date.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final time = _hm.firstMatch(line);
  final hour = time == null ? 0 : int.parse(time.group(1)!);
  final minute = time == null ? 0 : int.parse(time.group(2)!);
  if (hour > 23 || minute > 59) return DateTime(year, month, day);
  return DateTime(year, month, day, hour, minute);
}

/// A bank SMS you are pasting is recent. A date well in the future or years in
/// the past means the fields were read in the wrong order, so flag it rather
/// than filing a transaction to a wrong date — the one error the user would
/// never notice.
bool _isPlausible(DateTime at, DateTime now) {
  if (at.isAfter(now.add(const Duration(days: 2)))) return false;
  return now.difference(at).inDays <= 400;
}

BankTxnKind _classify(String head) {
  if (head.contains('إضافة اموال') || head.contains('إضافة أموال')) {
    return BankTxnKind.topup;
  }
  if (head.contains('حوالة') || head.contains('تحويل')) {
    return BankTxnKind.transferOut;
  }
  if (head.contains('مرتجع') || head.contains('استرجاع')) {
    return BankTxnKind.refund;
  }
  if (head.contains('راتب') || head.contains('إيداع')) {
    return BankTxnKind.income;
  }
  if (head.contains('شراء')) return BankTxnKind.expense;
  return BankTxnKind.unknown;
}

/// Stable identity for duplicate detection, computable from a parsed draft and
/// from an already-stored transaction alike.
///
/// Day precision, not the timestamp: the same purchase can reach two senders
/// with different clock formats, and re-pasting an overlapping range is the
/// normal case rather than the exception.
String txnFingerprint({
  required double amount,
  required DateTime date,
  required String? party,
}) {
  final day = '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
  final cents = (amount * 100).round();
  return '$cents|$day|${normalizePartyForMatch(party ?? '')}';
}

/// Case-folded, whitespace-collapsed form used for comparing parties.
String normalizePartyForMatch(String raw) =>
    raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
