# Plan 001: Cover the user-facing money math with tests

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat b756b1a..HEAD -- lib/ui/home_screen.dart lib/domain/period_summary.dart lib/services/alerts_coordinator.dart`
> If any of those files changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: tests
- **Planned at**: commit `b756b1a`, 2026-07-15

## Why this matters

The three calculations that produce the money the user actually looks at have
zero test coverage: the home-screen running balance and monthly split, the
monthly/yearly behaviour summaries, and the weekly-budget formula that drives
both a notification and the app-icon badge. Their pure-logic siblings
(`recurrence_math`, `savings_math`, `date_grouping`) are all well tested; these
are not. One of the three (`_Dashboard.from`) is also a private method inside a
UI file, so it cannot be tested without first extracting it to a pure function.
After this plan, every money figure shown on screen is verified by a test, and
a future refactor that breaks the balance math fails CI instead of shipping.

## Current state

Three units, none tested:

- `lib/ui/home_screen.dart` — `_Dashboard.from` (lines 407–449) computes the
  balance, this-month remaining/spent/saved, the month's expense list, and the
  "income received this month" flag. It is a `private` static method, so it is
  untestable from a test file as it stands. Excerpt:

  ```dart
  // lib/ui/home_screen.dart:407
  static _Dashboard from(
    List<TxnRow> rows,
    List<SavingsContribution> contributions,
  ) {
    final now = DateTime.now();
    bool inMonth(DateTime d) => d.year == now.year && d.month == now.month;

    double allIncome = 0, allExpense = 0, monthIncome = 0, monthSpent = 0;
    var incomeThisMonth = false;
    final monthExpenses = <TxnRow>[];
    for (final r in rows) {
      final amount = r.txn.amount;
      if (r.txn.type == TxnType.income) {
        allIncome += amount;
        if (inMonth(r.txn.date)) {
          monthIncome += amount;
          incomeThisMonth = true;
        }
      } else {
        allExpense += amount;
        if (inMonth(r.txn.date)) {
          monthSpent += amount;
          monthExpenses.add(r);
        }
      }
    }

    double allSaved = 0, monthSaved = 0;
    for (final c in contributions) {
      allSaved += c.amount;
      if (inMonth(c.date)) monthSaved += c.amount;
    }

    return _Dashboard(
      balance: allIncome - allExpense - allSaved,
      savingsTotal: allSaved,
      monthRemaining: monthIncome - monthSpent - monthSaved,
      monthSpent: monthSpent,
      monthSaved: monthSaved,
      monthExpenses: monthExpenses,
      incomeReceivedThisMonth: incomeThisMonth,
    );
  }
  ```

  The class `_Dashboard` (fields + const constructor) is declared at lines
  387–405 directly above it.

- `lib/domain/period_summary.dart` — `monthlySummaries` and `yearlySummaries`
  (already public, pure, take `List<TxnRow>` + `List<SavingsContribution>`).
  These back the behaviour pages and the stats CSV. No test file exists.

- `lib/services/alerts_coordinator.dart:68` — `computeWeeklyBudget(AppDatabase db, DateTime now)`.
  It reads from the DB, so it needs a seeded in-memory DB to test. Its formula:
  a 12-week (84-day) lookback, weeks starting **Saturday**, recommended =
  `essentialWindow / weeks + (luxuryWindow / weeks) * 0.85`, and `spentThisWeek`
  = expenses since the most recent Saturday. `WeeklyBudget.remaining` clamps at 0.

**Repo test conventions** — model new pure-logic tests after
`test/savings_math_test.dart` (nested `group()` / `test()`, `expect(actual, expected)`,
fixed `DateTime` literals, no mocks). Example:

```dart
// test/savings_math_test.dart:24
group('suggestedMonthlyDeposit', () {
  test('spreads the remaining amount over the months left', () {
    final d = suggestedMonthlyDeposit(
      target: 6000, saved: 1000,
      deadline: DateTime(2026, 6, 1), now: DateTime(2026, 1, 1),
    );
    expect(d, 1000); // 5000 remaining / 5 months
  });
});
```

For a test that needs a database, model after `test/widget_test.dart`, which
builds an in-memory drift DB and tears it down:

```dart
// test/widget_test.dart:20
final db = AppDatabase.forTesting(NativeDatabase.memory());
addTearDown(db.close);
```

`AppDatabase.forTesting` is defined at `lib/data/database.dart:421`. Insert rows
with the DAO methods: `db.transactionDao.add(amount:, categoryId:, type:, date:, note:)`
and `db.savingsDao.addContribution(goalId:, amount:, date:, note:)`. A fresh
`AppDatabase` auto-seeds default categories (see `onCreate` at
`lib/data/database.dart:428`), so category ids 1..11 exist; category id 1 is an
expense category (`طعام`, essential) and id 3 is `تسوق` (expense, luxury). Confirm
ids by reading `_defaultCategories` at `lib/data/database.dart:514` — the list
order is the id order (1-based).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Install | `flutter pub get` | exit 0 |
| Codegen | `dart run build_runner build --delete-conflicting-outputs` | exit 0; regenerates `lib/data/database.g.dart` |
| Format check | `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` | exit 0 (CI enforces this) |
| Analyze | `flutter analyze` | `No issues found!` |
| Tests | `flutter test` | all pass |
| Single test file | `flutter test test/dashboard_summary_test.dart` | all pass |

> The `.g.dart` files are gitignored. Run codegen once after `pub get` before
> `analyze`/`test`, or nothing compiles.

## Scope

**In scope**:
- `lib/domain/dashboard_summary.dart` (create — the extracted pure function)
- `lib/ui/home_screen.dart` (modify — use the extracted type; delete the old
  private class)
- `test/dashboard_summary_test.dart` (create)
- `test/period_summary_test.dart` (create)
- `test/weekly_budget_test.dart` (create)
- `plans/README.md` (status update)

**Out of scope** (do NOT touch):
- Any behaviour change to the math. This plan extracts and tests the existing
  logic verbatim; it must not "fix" or alter any formula, even one that looks
  off. If a test reveals a genuine bug, record it in the STOP report — do not
  change the formula here.
- `_DashboardBody` — this is a **different** widget class in the same file
  (lines 459+). It stays. Only the `_Dashboard` data class moves.
- `lib/services/alerts_coordinator.dart` — tested but not modified.
- `lib/domain/period_summary.dart` — tested but not modified.

## Git workflow

- Branch: `advisor/001-test-money-math`
- Commit style matches `git log` (imperative subject, sentence body). Example
  from history: `Ship iPhone-only, and allow re-releasing a version without a new tag`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Extract `_Dashboard` to a pure, public domain type

Create `lib/domain/dashboard_summary.dart`. Move the `_Dashboard` class and its
`from` factory there **verbatim**, with three changes only:

1. Rename the type `_Dashboard` → `DashboardSummary` (public).
2. Make `from` take `now` as a parameter instead of calling `DateTime.now()`
   internally — this is what makes it testable:
   `factory DashboardSummary.from(List<TxnRow> rows, List<SavingsContribution> contributions, DateTime now)`.
   Delete the `final now = DateTime.now();` line inside the body.
3. Add the imports the moved code needs:
   ```dart
   import '../data/database.dart'; // TxnRow, SavingsContribution
   import '../data/enums.dart';    // TxnType
   ```

Keep every field, the const constructor, and the doc comment. Do not change any
arithmetic.

**Verify**: `flutter analyze lib/domain/dashboard_summary.dart` → `No issues found!`

### Step 2: Point `home_screen.dart` at the extracted type

In `lib/ui/home_screen.dart`:

1. Add `import '../domain/dashboard_summary.dart';` with the other `../domain/`
   imports (near line 8).
2. Delete the now-moved `_Dashboard` class and its `from` factory (lines
   387–450 in the "Planned at" revision).
3. Replace the remaining `_Dashboard` references with `DashboardSummary`. There
   are exactly these sites (word `_Dashboard`, NOT `_DashboardBody`):
   - line 139: `final data = _Dashboard.from(rows, contributions);`
     → `final data = DashboardSummary.from(rows, contributions, DateTime.now());`
   - line 460: `final _Dashboard data;` → `final DashboardSummary data;`
   - line 682: `final _Dashboard data;` → `final DashboardSummary data;`

**Verify**:
- `grep -n "_Dashboard\b" lib/ui/home_screen.dart` → **no matches** (only
  `_DashboardBody` may remain, which the `\b` boundary excludes).
- `flutter analyze` → `No issues found!`
- `flutter test test/widget_test.dart` → passes (proves the home screen still
  builds and shows its empty state).

### Step 3: Test `DashboardSummary.from`

Create `test/dashboard_summary_test.dart` following the `savings_math_test.dart`
pattern. Build `TxnRow`s directly (no DB needed — construct `Txn` and `Category`
data classes, or seed an in-memory DB and read them back; prefer whichever
compiles cleanly — `TxnRow({required Txn txn, required Category category})` is at
`lib/data/database.dart:16`). Cover:

- Balance = all income − all expense − all savings across multiple months.
- This-month remaining/spent/saved isolates the current month (pass a fixed
  `now`; include rows in other months that must be excluded from the month
  figures but included in the all-time balance).
- `incomeReceivedThisMonth` is false with no income this month, true with income
  this month.
- `monthExpenses` contains only this month's expenses, and excludes income.
- Empty input → all zeros, `incomeReceivedThisMonth` false, empty `monthExpenses`.

**Verify**: `flutter test test/dashboard_summary_test.dart` → all pass.

### Step 4: Test `period_summary.dart`

Create `test/period_summary_test.dart`. Cover `monthlySummaries` and
`yearlySummaries`:

- Income/spent/saved aggregate correctly per month and per year.
- `remaining = income - spent - saved` and `savingsRate = saved / income`.
- `savingsRate` is null when income is 0 (see `PeriodSummary.savingsRate` at
  `lib/domain/period_summary.dart:28`).
- Ordering is newest-first (assert the first element's year/month).
- A month/year with only contributions (no transactions) still appears.

**Verify**: `flutter test test/period_summary_test.dart` → all pass.

### Step 5: Test `computeWeeklyBudget`

Create `test/weekly_budget_test.dart`. This one needs a DB — use
`AppDatabase.forTesting(NativeDatabase.memory())` with `addTearDown(db.close)`
(pattern from `widget_test.dart`). Seed expenses via `db.transactionDao.add`
using an essential category id and a luxury category id (confirm the ids from
`_defaultCategories`). Pass a fixed `now` so the Saturday-week and 84-day window
are deterministic. Cover:

- `spentThisWeek` counts only expenses on/after the most recent Saturday and
  on/before `now`; picks a `now` mid-week and asserts an earlier-in-week expense
  is included and a last-week expense is excluded.
- `recommended` follows `essential/weeks + (luxury/weeks) * 0.85` for a known
  set of rows.
- Income rows are ignored (add an income row; assert it changes nothing).
- `WeeklyBudget.remaining` clamps to 0 when `spentThisWeek > recommended`.

**Verify**: `flutter test test/weekly_budget_test.dart` → all pass.

### Step 6: Format, analyze, full test

**Verify** (all must pass):
- `dart format lib test integration_test test_driver` (this rewrites files to
  the canonical format; CI runs it with `--set-exit-if-changed`)
- `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` → exit 0
- `flutter analyze` → `No issues found!`
- `flutter test` → all pass, including the 3 new test files.

## Test plan

- New files: `test/dashboard_summary_test.dart`, `test/period_summary_test.dart`,
  `test/weekly_budget_test.dart`.
- Structural pattern: `test/savings_math_test.dart` (pure) and
  `test/widget_test.dart` (in-memory DB for the weekly-budget test).
- Verification: `flutter test` → all pass; the three new files contribute new
  passing tests.

## Done criteria

ALL must hold:

- [ ] `dart run build_runner build --delete-conflicting-outputs` exits 0
- [ ] `flutter analyze` → `No issues found!`
- [ ] `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` exits 0
- [ ] `flutter test` exits 0; the three new test files exist and pass
- [ ] `grep -n "_Dashboard\b" lib/ui/home_screen.dart` returns no matches
- [ ] `lib/domain/dashboard_summary.dart` exists and exposes public `DashboardSummary`
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- The `_Dashboard.from` body in the live code differs from the "Current state"
  excerpt (drift — the math may have changed and your tests would encode the
  wrong expectation).
- A test you write to encode the *existing* behaviour fails — that means the
  current code has a real bug. Report it with the failing case; do NOT change
  the formula to make the test pass, and do NOT change the test to match a
  result you believe is wrong. This plan's job is to pin down current behaviour.
- `flutter analyze` reports errors you can't resolve without touching an
  out-of-scope file.
- The default category ids you rely on in Step 5 don't match `_defaultCategories`.

## Maintenance notes

- `DashboardSummary.from` now takes `now` explicitly; the single production
  caller passes `DateTime.now()`. Keep it that way — an injected clock is what
  makes it testable.
- If the balance definition ever changes (e.g. savings contributions stop
  reducing the running balance), update `test/dashboard_summary_test.dart` in
  the same change — it is now the spec for that formula.
- Reviewer should confirm no arithmetic changed in the extraction (diff the
  moved method against the deleted one line-for-line) and that `_DashboardBody`
  was untouched.
