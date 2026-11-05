# Plan 023: Search and filter every transaction

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> **No schema change.** This is a pure domain filter plus one screen. If you
> find yourself editing `lib/data/tables.dart`, STOP.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW (read-only over existing data)
- **Depends on**: —
- **Category**: feature (batch 5)
- **Planned at**: commit `f54f113`, 2026-11-05

## Why this matters

There is no way to find a transaction. The only search field in the app is in
the icon picker. "Did I already log that 87 SAR from Jahez?", "how much went to
Careem over the last three cycles?" and "where is the rent I logged twice?"
all mean scrolling cycle by cycle through `MonthDetailScreen`.

It is also the other half of the cross-checking pain that started batch 4: the
import catches duplicates going *in*; search is how the user checks the ledger
by hand.

## Design

### Domain — `lib/domain/txn_search.dart` (new, pure)

```dart
class TxnQuery {
  final String text;              // free text; may be an amount
  final TxnType? type;            // null = both
  final Set<int> categoryIds;     // top-level ids; empty = all
  final SearchRange range;        // see below
}

enum SearchRange { thisCycle, last3Cycles, last12Cycles, all }

List<TxnRow> searchTransactions(
  List<TxnRow> rows,
  TxnQuery q, {
  required Map<int, Category> categoriesById, // to resolve parents
  required List<RecurrenceRule> incomeRules,  // to resolve cycles
  required DateTime now,
});
```

- **Text match** is against the note, the category name, and the *parent*
  category name (searching «مطاعم» must find rows filed under a subcategory of
  it). Both sides go through one `normalizeForSearch(String)`:
  strip tashkeel (U+064B–U+0652) and tatweel (U+0640); unify أ إ آ → ا,
  ة → ه, ى → ي; lower-case Latin; map Arabic-Indic and Persian digits to
  ASCII; collapse whitespace. Do NOT reuse `partyKey` — it only trims and
  case-folds, deliberately, and changing it would change which saved party
  rules match.
- **Amount match**: if the whole query parses with the existing `parseAmount`
  (which already accepts Arabic-Indic digits — plan 019), a row also matches
  when `|amount − q| < 0.005`. The query is still tried as text too, so "87"
  finds a note saying "87" as well.
- **Category filter**: a selected top-level id matches its subcategories too.
- **Range is by salary cycle, never calendar month** (maintainer's hard rule).
  Resolve it with the existing `previousCycles` / `financialPeriod` helpers in
  `budget_advisor.dart` / `financial_period.dart`. Do not write new date math.
- Results are newest first.

### Screen — `lib/ui/search_screen.dart` (new)

- A text field (autofocus) plus a row of filter chips: type, categories
  (multi-select sheet reusing `category_picker.dart`), range (default
  `last12Cycles`).
- A summary line above the results: count, and **expense total and income total
  shown separately** — never a single net figure across mixed types, which
  would read as a meaningless number.
- Results grouped with the existing `groupByDay` + `DayGroupCard`, so tap-to-edit
  and swipe-to-delete-with-undo behave exactly as in `MonthDetailScreen`. Do
  not build a second row widget.
- Source stream: `transactionDao.watchAllWithCategory()` filtered in memory,
  with a 150 ms debounce on the text field. A few thousand rows is nothing; do
  not add SQL `LIKE` queries (they cannot do the Arabic normalization above).

### Entry points

- An action icon (`Icons.search`) in the `MonthsScreen` (الدورات) app bar.
- A tile «بحث في العمليات» in Settings, next to الدورات.
- **Not** in the home header unless `test/home_header_overflow_test.dart` still
  passes at its narrowest width with a third circle button — the header already
  overflowed once (v1.2.1). If it fails, leave it out and say so.

## Steps

1. Write `normalizeForSearch` and its tests first (`test/txn_search_test.dart`):
   hamza variants, taa marbuta, alef maqsura, tashkeel, tatweel, Arabic-Indic
   digits, mixed Latin case.
2. Write `searchTransactions` and tests: note match, category match, parent
   category match, amount match (incl. `٨٧` and `87.00`), type filter, each
   range at a cycle boundary (a row on the last day of the previous cycle is in
   `last3Cycles` but not `thisCycle`), ordering.
3. Build the screen; widget test (`test/search_screen_test.dart`) that types a
   query, sees the summary totals, and that swipe-delete from a result works.
   Remember the drift-in-testWidgets rule: wrap DB reads/writes in
   `tester.runAsync`, and do not close the DB at the end.
4. Wire the entry points.

## Verification

```
flutter analyze
flutter test test/txn_search_test.dart test/search_screen_test.dart
flutter test
```
All green; the full suite count rises by the new tests and nothing else changes.

## STOP conditions

- `previousCycles` cannot express "the last N cycles including the current one"
  without new date logic → STOP and report; do not add a calendar-month fallback.
- Deleting from the search results does not refresh the results or the badge →
  STOP; the delete path must be the existing one (plans 014/015), not a copy.
