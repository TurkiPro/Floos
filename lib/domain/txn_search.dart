import '../data/database.dart';
import '../data/enums.dart';
import 'budget_advisor.dart' show previousCycles;
import 'financial_period.dart';
import 'parse_amount.dart';

/// How far back a search looks — always in salary cycles, never calendar
/// months (the cycle is the app's only period unit).
enum SearchRange { thisCycle, last3Cycles, last12Cycles, all }

class TxnQuery {
  /// Free text. Also tried as an amount when it is a plain number.
  final String text;

  /// Null = expenses and income.
  final TxnType? type;

  /// A category to restrict to. A top-level id also matches its
  /// subcategories; a subcategory id matches only itself.
  final int? categoryId;

  final SearchRange range;

  const TxnQuery({
    this.text = '',
    this.type,
    this.categoryId,
    this.range = SearchRange.last12Cycles,
  });

  bool get isEmpty => text.trim().isEmpty && type == null && categoryId == null;

  TxnQuery copyWith({
    String? text,
    TxnType? Function()? type,
    int? Function()? categoryId,
    SearchRange? range,
  }) =>
      TxnQuery(
        text: text ?? this.text,
        type: type != null ? type() : this.type,
        categoryId: categoryId != null ? categoryId() : this.categoryId,
        range: range ?? this.range,
      );
}

/// Folds the spellings an Arabic search should not care about onto one form,
/// so «مطاعم» finds «مَطاعِم», «اسعار» finds «أسعار», and «٨٧» finds "87".
///
/// Deliberately separate from `partyKey`, which only trims and case-folds:
/// that key decides which saved party rules match an import, and widening it
/// would change those matches.
String normalizeForSearch(String input) {
  final out = StringBuffer();
  var lastWasSpace = true; // also trims the start
  for (final r in input.runes) {
    int? c = r;
    if (r >= 0x064B && r <= 0x0652) {
      c = null; // tashkeel (fathatan … sukun)
    } else if (r == 0x0640) {
      c = null; // tatweel
    } else if (r == 0x0623 || r == 0x0625 || r == 0x0622) {
      c = 0x0627; // أ إ آ → ا
    } else if (r == 0x0629) {
      c = 0x0647; // ة → ه
    } else if (r == 0x0649) {
      c = 0x064A; // ى → ي
    } else if (r >= 0x0660 && r <= 0x0669) {
      c = 0x30 + (r - 0x0660); // Arabic-Indic digits
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      c = 0x30 + (r - 0x06F0); // Persian digits
    } else if (r >= 0x41 && r <= 0x5A) {
      c = r + 0x20; // A–Z → a–z
    }
    if (c == null) continue;
    final isSpace = c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;
    if (isSpace) {
      if (!lastWasSpace) out.writeCharCode(0x20);
      lastWasSpace = true;
    } else {
      out.writeCharCode(c);
      lastWasSpace = false;
    }
  }
  return out.toString().trimRight();
}

/// The query as an amount, when it is a plain number ("87", "٨٧", "87.50",
/// "1,200"). Not an expression: the amount fields accept "45+12", but in a
/// search box that is text, not a sum to look for.
double? _queryAmount(String text) {
  final s = normalizeAmountInput(text);
  if (!RegExp(r'^[0-9]+(\.[0-9]+)?$').hasMatch(s)) return null;
  return parseAmount(s);
}

/// The first day a search over [range] includes, or null for no limit.
DateTime? searchRangeStart(
    SearchRange range, List<RecurrenceRule> incomeRules, DateTime now) {
  int cycles;
  switch (range) {
    case SearchRange.all:
      return null;
    case SearchRange.thisCycle:
      return financialPeriod(incomeRules, now).start;
    case SearchRange.last3Cycles:
      cycles = 3;
    case SearchRange.last12Cycles:
      cycles = 12;
  }
  // The current cycle plus the (cycles − 1) before it.
  return previousCycles(incomeRules, now, cycles - 1).last.start;
}

/// Every row matching [q], newest first.
List<TxnRow> searchTransactions(
  List<TxnRow> rows,
  TxnQuery q, {
  required Map<int, Category> categoriesById,
  required List<RecurrenceRule> incomeRules,
  required DateTime now,
}) {
  final from = searchRangeStart(q.range, incomeRules, now);
  final needle = normalizeForSearch(q.text);
  final amount = needle.isEmpty ? null : _queryAmount(q.text);

  bool textMatches(TxnRow r) {
    if (needle.isEmpty) return true;
    if (amount != null && (r.txn.amount - amount).abs() < 0.005) return true;
    final parent = r.category.parentId == null
        ? null
        : categoriesById[r.category.parentId];
    for (final hay in [r.txn.note, r.category.name, parent?.name]) {
      if (hay != null && normalizeForSearch(hay).contains(needle)) return true;
    }
    return false;
  }

  final out = [
    for (final r in rows)
      if ((from == null || !r.txn.date.isBefore(from)) &&
          (q.type == null || r.txn.type == q.type) &&
          (q.categoryId == null ||
              r.category.id == q.categoryId ||
              r.category.parentId == q.categoryId) &&
          textMatches(r))
        r,
  ];
  out.sort((a, b) {
    final byDate = b.txn.date.compareTo(a.txn.date);
    return byDate != 0 ? byDate : b.txn.id.compareTo(a.txn.id);
  });
  return out;
}

/// Totals for the summary line. Kept apart on purpose: a single net figure
/// across expenses and income would be a number that means nothing.
({int count, double expense, double income}) searchTotals(List<TxnRow> rows) {
  var expense = 0.0, income = 0.0;
  for (final r in rows) {
    if (r.txn.type == TxnType.income) {
      income += r.txn.amount;
    } else {
      expense += r.txn.amount;
    }
  }
  return (count: rows.length, expense: expense, income: income);
}
