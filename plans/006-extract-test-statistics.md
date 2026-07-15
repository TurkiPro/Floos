# Plan 006: Extract and test the statistics money math

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 8edb242..HEAD -- lib/ui/statistics_screen.dart`
> If it changed since this plan was written, compare the "Current state"
> excerpt against the live code before proceeding; on a mismatch, treat it as a
> STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none (but mirrors the already-merged plan 001)
- **Category**: tests
- **Planned at**: commit `8edb242`, 2026-07-15

## Why this matters

The statistics screen shows ~25 derived money figures — spend projection,
savings rate, essentials-vs-luxuries, top categories, weekday averages, monthly
trend — all computed by `_Stats.from`, a 165-line private class inside a UI
file. Like the home dashboard was before plan 001, it cannot be tested without
extracting it, so none of these numbers has any coverage. This is a *larger*
surface than the dashboard. This plan extracts it to a pure domain type (exactly
as plan 001 did for `DashboardSummary`) and pins the calculations down with
tests, so a future change that breaks a stat fails CI instead of quietly showing
users wrong numbers.

Plan 001 already did this for the dashboard — `lib/domain/dashboard_summary.dart`
and `test/dashboard_summary_test.dart` are the exemplars to copy.

## Current state

`lib/ui/statistics_screen.dart` contains `_Stats` (the data class, fields at
lines 642–699) and `_Stats.from` (the computation, lines 701–866), plus a
private helper `_countWeekday` (lines 869–878). Crucially, `from` **already
takes `now` as a parameter** (line 701–705), so unlike the dashboard no
signature change is needed — this is a pure move + rename.

```dart
// lib/ui/statistics_screen.dart:701
static _Stats from(
  List<TxnRow> rows,
  List<SavingsContribution> contributions,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  ...
}
```

The single production caller is at line 59:

```dart
final s = _Stats.from(rows, contributions, DateTime.now());
```

The class is referenced as a **type** in nine card-builder methods (the widget
methods that render each stat card). All `_Stats` reference sites:

- line 59 — `_Stats.from(...)` call
- line 184, 238, 274, 309, 358, 401, 479, 545 — `_Stats s` parameters on the
  `_thisMonthCard` / `_paceCard` / `_weeklyBudgetCard` / `_savingsRateCard` /
  `_essentialsCard` / `_quickFactsCard` / `_topCategoriesCard` / `_trendCard`
  methods
- line 642 — `class _Stats {`
- line 672 — `const _Stats({`
- line 701 — `static _Stats from(`
- line 837 — `return _Stats(`

`_countWeekday` is referenced only at line 801 (inside `from`) and defined at
line 869 — it moves with the class.

The fields (all `final`) are: `allExpenseCount`, `spentThisMonth`,
`dailyAvgThisMonth`, `projectedThisMonth`, `lastMonthSpent`,
`projectedVsLastMonth`, `recommendedWeekly`, `currentWeeklyPace`,
`essentialThisMonth`, `luxuryThisMonth`, `monthIncome`, `monthSaved`,
`savingsRate` (nullable), `dailyAllowanceRemaining` (nullable),
`daysLeftInMonth`, `daysElapsed`, `txnCountThisMonth`, `avgTxnThisMonth`,
`biggestExpense` (`TxnRow?`), `highestDay` (`DateTime?`), `highestDayAmount`,
`noSpendDays`, `topWeekday` (`int?`), `topWeekdayAvg`, `topCategories`
(`List<MapEntry<int, double>>`), `monthlyTrend`
(`List<MapEntry<MonthKey, double>>`).

**Exemplar to copy** — plan 001 did the identical move for the dashboard:
`lib/domain/dashboard_summary.dart` (the extracted pure type) and
`test/dashboard_summary_test.dart` (its tests, which build `TxnRow`s directly
with helper constructors). Read both before starting and match their shape.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Install | `flutter pub get` | exit 0 |
| Codegen | `dart run build_runner build --delete-conflicting-outputs` | exit 0 |
| Format check | `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` | exit 0 |
| Analyze | `flutter analyze` | `No issues found!` |
| This test | `flutter test test/statistics_summary_test.dart` | all pass |
| Full suite | `flutter test` | all pass |

## Scope

**In scope**:
- `lib/domain/statistics_summary.dart` (create)
- `lib/ui/statistics_screen.dart` (modify — use the extracted type, delete the
  moved class)
- `test/statistics_summary_test.dart` (create)
- `plans/README.md` (status update)

**Out of scope** (do NOT touch):
- Any arithmetic. This is a verbatim move; do not "fix" any formula. If a test
  written to encode current behaviour fails, that's a real bug — STOP and
  report; do not change the formula or bend the test.
- The card-rendering widget methods beyond swapping the `_Stats` type name for
  the new type name.
- `lib/services/alerts_coordinator.dart` — plan 007 handles the duplicated
  formula; leave it alone here.

## Git workflow

- Branch: `advisor/006-extract-test-statistics`
- Commit style matches `git log` (imperative subject, sentence body).
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Move `_Stats` to a pure, public domain type

Create `lib/domain/statistics_summary.dart`. Move the `_Stats` class, its `from`
factory, and the `_countWeekday` helper there **verbatim**, with two changes
only:

1. Rename the type `_Stats` → `StatisticsSummary` (public). Keep `_countWeekday`
   as a private static on the class (it's only used internally).
2. Add the imports the moved code needs:
   ```dart
   import '../data/database.dart'; // TxnRow, SavingsContribution
   import '../data/enums.dart';    // TxnType, CategoryKind
   import 'date_grouping.dart';    // MonthKey
   ```

Do not change any arithmetic. `from` already takes `now`; leave its signature.

**Verify**: `flutter analyze lib/domain/statistics_summary.dart` → `No issues found!`

### Step 2: Point `statistics_screen.dart` at the extracted type

In `lib/ui/statistics_screen.dart`:

1. Add `import '../domain/statistics_summary.dart';` with the other `../domain/`
   imports (near line 8).
2. Delete the moved `_Stats` class, its `from`, and `_countWeekday`.
3. Replace every remaining `_Stats` reference with `StatisticsSummary`:
   - line 59: `_Stats.from(rows, contributions, DateTime.now())` →
     `StatisticsSummary.from(rows, contributions, DateTime.now())`
   - the nine `_Stats s` method parameters (lines 184, 238, 274, 309, 358, 401,
     479, 545) → `StatisticsSummary s`.

**Verify**:
- `grep -n "_Stats\b" lib/ui/statistics_screen.dart` → **no matches**.
- `flutter analyze` → `No issues found!`.

### Step 3: Test `StatisticsSummary.from`

Create `test/statistics_summary_test.dart`, copying the `TxnRow`/`Category`/
`SavingsContribution` helper constructors from `test/dashboard_summary_test.dart`
(you'll need a `Category` with a settable `kind` and `parentId` to exercise
essentials/luxuries and top-category rollup). Use a fixed `now`. Cover at least:

- `spentThisMonth` / `essentialThisMonth` / `luxuryThisMonth` split correctly by
  `CategoryKind`, this-month only.
- `dailyAvgThisMonth = spentThisMonth / now.day` and
  `projectedThisMonth = dailyAvg * daysInMonth`.
- `savingsRate = monthSaved / monthIncome`, and null when `monthIncome == 0`.
- `topCategories` rolls sub-category spend up to the **parent** id
  (`parentId ?? id`) and is sorted descending, capped at 5.
- `biggestExpense` is the largest this-month expense (and ignores income).
- `monthlyTrend` has exactly 6 entries, oldest→newest, ending at the current
  month.
- `projectedVsLastMonth` is 0 when last month had no spend (guard against
  divide-by-zero).
- `allExpenseCount == 0` for income-only input (drives the empty state).

**Verify**: `flutter test test/statistics_summary_test.dart` → all pass.

### Step 4: Format, analyze, full test

**Verify** (all must pass):
- `dart format lib test integration_test test_driver` then
  `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` → exit 0
- `flutter analyze` → `No issues found!`
- `flutter test` → all pass, including the new test.

## Test plan

- New file: `test/statistics_summary_test.dart`, cases as in Step 3.
- Pattern: `test/dashboard_summary_test.dart` (helper constructors, fixed `now`,
  hand-computed expectations).
- Verification: `flutter test` → all pass.

## Done criteria

ALL must hold:

- [ ] `flutter analyze` → `No issues found!`
- [ ] `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` exits 0
- [ ] `flutter test` exits 0; `test/statistics_summary_test.dart` exists and passes
- [ ] `grep -n "_Stats\b" lib/ui/statistics_screen.dart` returns no matches
- [ ] `lib/domain/statistics_summary.dart` exposes public `StatisticsSummary`
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- The `_Stats.from` body differs from the "Current state" excerpt (drift).
- A test encoding current behaviour fails — report the case; do not change the
  formula or the test to force a pass.
- The extraction requires touching a card-rendering method beyond renaming the
  type — it should not.

## Maintenance notes

- `StatisticsSummary` becomes the spec for the stats numbers; if a formula
  changes, update the test in the same commit.
- Plan 007 will consolidate the weekly-budget formula that this class shares
  with `computeWeeklyBudget`; after 006 lands, that shared logic lives in
  `StatisticsSummary` and is the natural thing to factor out.
- Reviewer: diff the moved code against the deleted code to confirm zero
  arithmetic change.
