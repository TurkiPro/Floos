# Plan 027: Compute the balance in exactly one place

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> **Pure refactor. No number on any screen may change.** If any existing test
> needs its expected value edited, STOP.

## Status

- **Priority**: P1 (prerequisite for 029 debts)
- **Effort**: M
- **Risk**: MED (touches the two most important figures in the app)
- **Depends on**: —
- **Category**: refactor (batch 5)
- **Planned at**: commit `f54f113`, 2026-11-05

## Why this matters

The balance formula — all income − all expense − internal savings − internal
investments — is written out twice:

- `lib/domain/dashboard_summary.dart:83`
  `balance = allIncome - allExpense - internalSaved - internalInvested;`
- `lib/domain/weekly_budget_status.dart:151-168`, which re-sums the same
  ledgers (plus an "as of week start" variant) for the weekly cap.

Plan 029 adds a ledger that moves the balance without being spending
(lending and borrowing money). Added to two copies, that is
two chances to forget one — exactly how investments once reached the home card
but not the statistics screen (fixed in v1.3.0, see
`test/weekly_budget_parity_test.dart`). Doing this refactor first means each
new ledger is added in one function and every screen gets it.

## Design

`lib/domain/ledger_balance.dart` (new, pure):

```dart
class LedgerInputs {
  final List<TxnRow> rows;
  final List<SavingsContribution> contributions;
  final List<Investment> investments;
  const LedgerInputs({required this.rows, required this.contributions,
      required this.investments});
}

/// Money neither spent nor set aside, counting only entries dated strictly
/// before [asOfExclusive] (null = everything).
double ledgerBalance(LedgerInputs l, {DateTime? asOfExclusive});
```

- **All fields are `required`, no defaults.** The investments bug happened
  because `investments` defaulted to `const []` and a caller silently omitted
  it. When 029 adds a field here, the compiler must flag every call site.
- `DashboardSummary.from` and `weeklyBudgetStatus` both call it — the latter
  twice (now, and `asOfExclusive: weekStart` for `balanceAtWeekStart`).
- Change `weeklyBudgetStatus`'s `investments` parameter from defaulted to
  `required` at the same time, and fix the call sites the compiler reports
  (`alerts_coordinator.dart`, `home_screen.dart`, `statistics_summary.dart`,
  tests).
- `StatisticsSummary` keeps getting the balance via `DashboardSummary`, as now.

## Steps

1. Write `test/ledger_balance_test.dart`: the formula on a fixture with
   income, expense, internal + external savings, a planned withdrawal, internal
   + external investments; and the `asOfExclusive` boundary (an entry *on*
   weekStart is excluded from the before-week figure — same rule as today).
2. Implement `ledgerBalance`. Replace both inline computations.
3. Make `investments` required on `weeklyBudgetStatus`; fix call sites.
4. Add one more parity test to `test/weekly_budget_parity_test.dart`:
   `DashboardSummary.balance == ledgerBalance(...)` on the parity fixtures.

## Verification

```
flutter analyze
flutter test
```
Full suite green **with no expected value changed in any pre-existing test**.
Run `git diff --stat test/` and confirm only new tests/fixtures appear plus
call-site updates for the now-required parameter.

## STOP conditions

- Any pre-existing test's expected number has to change → STOP. That means the
  two copies were *not* equivalent; report the case instead of picking one.
