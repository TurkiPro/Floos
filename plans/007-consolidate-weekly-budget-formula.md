# Plan 007: Consolidate the duplicated weekly-budget formula

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 8edb242..HEAD -- lib/services/alerts_coordinator.dart lib/domain/statistics_summary.dart`
> Note: `lib/domain/statistics_summary.dart` is created by **plan 006**, which
> must be DONE first. If it doesn't exist, STOP — this plan depends on it.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/006-extract-test-statistics.md (must be DONE)
- **Category**: tech-debt
- **Planned at**: commit `8edb242`, 2026-07-15

## Why this matters

The recommended-weekly-spend formula — `essential/weeks + luxury/weeks * 0.85`
over a rolling 12-week (84-day) window — is coded **twice, independently**:
once in `computeWeeklyBudget` (which drives the salary-day notification and the
app-icon badge) and once in the statistics summary (which drives the on-screen
budget card). The comment in `computeWeeklyBudget` even says "the same formula
the statistics screen shows." Two copies of one money formula means a change to
one silently disagrees with the other — the badge could say one number while the
stats card says another. This plan makes them one function so they can't drift.

## Current state

**Copy 1** — `lib/services/alerts_coordinator.dart`, inside
`computeWeeklyBudget` (lines ~94–100):

```dart
final windowDays =
    earliest == null ? 1 : today.difference(earliest).inDays + 1;
final weeks = (windowDays / 7).clamp(1.0, 12.0);
final recommended = essentialWindow / weeks + (luxuryWindow / weeks) * 0.85;
```

with `windowStart = today.subtract(const Duration(days: 84))` and the loop that
accumulates `essentialWindow` / `luxuryWindow` (expenses in the window, split by
`CategoryKind.luxury`).

**Copy 2** — `lib/domain/statistics_summary.dart` (created by plan 006), inside
`StatisticsSummary.from`:

```dart
final windowDays = earliestInWindow == null
    ? 1
    : today.difference(earliestInWindow).inDays + 1;
final weeks = (windowDays / 7).clamp(1.0, 12.0);
final essentialWeekly = essentialWindow / weeks;
final luxuryWeekly = luxuryWindow / weeks;
// ...
recommendedWeekly: essentialWeekly + luxuryWeekly * 0.85,
```

Both use the same `84`-day window and the same `0.85` discretionary factor.

**Convention**: pure, testable domain logic lives in `lib/domain/` (see
`recurrence_math.dart`, `savings_math.dart`, `dashboard_summary.dart`). Tests
live beside their subject in `test/` and follow `test/savings_math_test.dart`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Install | `flutter pub get` | exit 0 |
| Codegen | `dart run build_runner build --delete-conflicting-outputs` | exit 0 |
| Format check | `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` | exit 0 |
| Analyze | `flutter analyze` | `No issues found!` |
| Targeted tests | `flutter test test/weekly_budget_test.dart test/statistics_summary_test.dart test/spending_window_test.dart` | all pass |
| Full suite | `flutter test` | all pass |

## Scope

**In scope**:
- `lib/domain/spending_window.dart` (create — the shared window/formula)
- `lib/services/alerts_coordinator.dart` (modify — use the shared function)
- `lib/domain/statistics_summary.dart` (modify — use the shared function)
- `test/spending_window_test.dart` (create)
- `plans/README.md` (status update)

**Out of scope** (do NOT touch):
- The `spentThisWeek` calculation in `computeWeeklyBudget` — that's a
  *this-week* figure, separate from the *recommended* window formula. Leave it.
- The many other fields `StatisticsSummary.from` computes — only the
  `recommendedWeekly` / `currentWeeklyPace` window aggregation is shared.
- Any change to the numeric result. This is a pure refactor; the values must be
  identical before and after (the existing `test/weekly_budget_test.dart` and
  `test/statistics_summary_test.dart` are the guard — they must still pass
  unchanged).

## Git workflow

- Branch: `advisor/007-consolidate-weekly-budget-formula`
- Commit style matches `git log` (imperative subject).
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Create the shared window function

Create `lib/domain/spending_window.dart` with a pure function that both callers
can use. It takes the already-classified window totals and the window bounds and
returns the derived weekly numbers. Suggested shape:

```dart
/// The rolling spending window both the weekly-budget alert and the statistics
/// screen derive their "recommended weekly spend" from: a 12-week (84-day)
/// look-back, recommending all essentials plus 85% of the discretionary
/// average. Kept in one place so the badge/notification and the on-screen card
/// can never disagree.
const spendingWindowDays = 84;
const discretionaryFactor = 0.85;

class WeeklySpend {
  final double recommended;
  final double pace; // total average, no discretionary discount
  const WeeklySpend({required this.recommended, required this.pace});
}

WeeklySpend weeklySpend({
  required double essentialWindow,
  required double luxuryWindow,
  required DateTime? earliestInWindow,
  required DateTime today,
}) {
  final windowDays = earliestInWindow == null
      ? 1
      : today.difference(earliestInWindow).inDays + 1;
  final weeks = (windowDays / 7).clamp(1.0, 12.0);
  return WeeklySpend(
    recommended: essentialWindow / weeks + (luxuryWindow / weeks) * discretionaryFactor,
    pace: (essentialWindow + luxuryWindow) / weeks,
  );
}
```

**Verify**: `flutter analyze lib/domain/spending_window.dart` → `No issues found!`

### Step 2: Use it in `computeWeeklyBudget`

In `lib/services/alerts_coordinator.dart`:
- Replace the literal `const Duration(days: 84)` for `windowStart` with
  `Duration(days: spendingWindowDays)`.
- Replace the `windowDays`/`weeks`/`recommended` block with a call to
  `weeklySpend(...)`, using its `.recommended`. Import
  `../domain/spending_window.dart`.

Leave the accumulation loop and `spentThisWeek` untouched.

**Verify**: `flutter test test/weekly_budget_test.dart` → all pass **unchanged**
(same numbers as before the refactor).

### Step 3: Use it in `StatisticsSummary.from`

In `lib/domain/statistics_summary.dart`:
- Replace the literal `84` in `windowStart` with `spendingWindowDays`.
- Replace the `windowDays`/`weeks`/`essentialWeekly`/`luxuryWeekly` computation
  and the `recommendedWeekly` / `currentWeeklyPace` assignments with a
  `weeklySpend(...)` call, using `.recommended` and `.pace`. Import
  `spending_window.dart`.

**Verify**: `flutter test test/statistics_summary_test.dart` → all pass
**unchanged**.

### Step 4: Test the shared function directly

Create `test/spending_window_test.dart` (pattern: `test/savings_math_test.dart`).
Cover:
- `recommended = essential/weeks + luxury/weeks*0.85` for a known input
  (reuse the hand-computed case from `test/weekly_budget_test.dart` — e.g.
  earliest 14 days ago → weeks 2, essential 300, luxury 400 → recommended 320).
- `weeks` clamps to 1 for a <7-day window and to 12 for a >84-day window.
- `earliestInWindow == null` → `weeks == 1` (no divide-by-zero).
- `pace` ignores the 0.85 discount.

**Verify**: `flutter test test/spending_window_test.dart` → all pass.

### Step 5: Format, analyze, full test

**Verify** (all must pass):
- `dart format lib test integration_test test_driver` then
  `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` → exit 0
- `flutter analyze` → `No issues found!`
- `flutter test` → all pass. The pre-existing `weekly_budget_test.dart` and
  `statistics_summary_test.dart` must pass **without edits** — that's the proof
  the refactor changed no numbers.

## Test plan

- New file: `test/spending_window_test.dart`.
- The regression guard is that `weekly_budget_test.dart` and
  `statistics_summary_test.dart` keep passing unmodified.
- Verification: `flutter test` → all pass.

## Done criteria

ALL must hold:

- [ ] `flutter analyze` → `No issues found!`
- [ ] `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` exits 0
- [ ] `flutter test` exits 0; `test/spending_window_test.dart` passes; the two
      pre-existing budget/stats tests pass **unmodified**
- [ ] `grep -n "0.85" lib/services/alerts_coordinator.dart lib/ui/statistics_screen.dart` → no matches (the literal now lives only in `spending_window.dart`)
- [ ] `grep -rn "days: 84" lib/` → no matches (replaced by `spendingWindowDays`)
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- Plan 006 is not DONE (`lib/domain/statistics_summary.dart` doesn't exist) —
  this plan depends on it.
- After the refactor, `weekly_budget_test.dart` or `statistics_summary_test.dart`
  fails — the two copies were NOT actually identical (e.g. a subtle difference
  in window bounds), which is itself a latent bug. Report the divergence rather
  than forcing either test to pass.
- The two copies turn out to classify the window differently (e.g. one includes
  today, the other doesn't) — surface it; don't silently pick one.

## Maintenance notes

- After this lands there is exactly one place the 12-week / 85% policy lives.
  Any future tuning (a different discount, a different window) changes one file
  and both surfaces move together.
- Reviewer: confirm the numbers didn't move by checking the two pre-existing
  tests were not edited.
