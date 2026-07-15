# Plan 008: Compute savings totals in one pass, not one query per goal

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 8edb242..HEAD -- lib/ui/savings_screen.dart`
> If it changed since this plan was written, compare the "Current state"
> excerpt against the live code before proceeding; on a mismatch, treat it as a
> STOP condition.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: perf
- **Planned at**: commit `8edb242`, 2026-07-15

## Why this matters

The savings screen already subscribes to `watchAllContributions()` — every
contribution across every goal — to render the ledger. But each goal card *also*
opens its own `StreamBuilder<double>(watchTotal(goal.id))`, i.e. a separate
`SELECT SUM(...)` query and stream subscription per goal, recomputing totals the
outer stream already has the data for. It's a per-list-row query fan-out. Impact
is small (nobody has dozens of savings goals), which is why this is P3 — but the
fix is small too, removes N redundant subscriptions, and makes the screen derive
every number from a single stream (matching how the home dashboard and
statistics screens already work).

## Current state

`lib/ui/savings_screen.dart`. The outer build already has all contributions in
scope:

```dart
// lib/ui/savings_screen.dart:55
return StreamBuilder<List<SavingsContribution>>(
  stream: db.savingsDao.watchAllContributions(),
  builder: (context, contribSnapshot) {
    final contributions =
        contribSnapshot.data ?? const <SavingsContribution>[];
    // ...
    for (final g in goals)
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: _GoalCard(db: db, goal: g),   // <-- each opens its own SUM stream
      ),
```

`_GoalCard` then opens a second, redundant stream per goal:

```dart
// lib/ui/savings_screen.dart:182
return StreamBuilder<double>(
  // The only source for a goal's balance -- always SUM(contributions),
  // never a stored field.
  stream: db.savingsDao.watchTotal(goal.id),
  builder: (context, snapshot) {
    final total = snapshot.data ?? 0.0;
    // ... renders the card using `total` ...
```

`_GoalCard` uses `total` for: the progress `ratio`, the "الحالي X ر.س" line, and
`_monthlyLabel(goal, total, money)`.

The invariant this must preserve: **a goal's balance is always the sum of its
contributions, never a stored field** (the comment at line 183 and the app's
core design). Summing in Dart from `watchAllContributions()` keeps that
invariant — it's the same sum, computed from the same ledger, just once.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Install | `flutter pub get` | exit 0 |
| Codegen | `dart run build_runner build --delete-conflicting-outputs` | exit 0 |
| Format check | `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` | exit 0 |
| Analyze | `flutter analyze` | `No issues found!` |
| Full suite | `flutter test` | all pass |

## Scope

**In scope**:
- `lib/ui/savings_screen.dart` (modify)
- `plans/README.md` (status update)

**Out of scope** (do NOT touch):
- `lib/data/database.dart` — `SavingsDao.watchTotal` stays (it's still used by
  `goal_detail_screen.dart`; do not delete it).
- The ledger/day-card rendering below the goal cards — unchanged.
- `_monthlyLabel` behaviour — it still takes a `total`; only its source changes.

## Git workflow

- Branch: `advisor/008-savings-total-single-pass`
- Commit style matches `git log` (imperative subject).
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Build a per-goal total map once, in the outer builder

In the `watchAllContributions` builder (around line 57), after `contributions`
is available, fold it into a `Map<int, double>` of goalId → sum:

```dart
final totalByGoal = <int, double>{};
for (final c in contributions) {
  totalByGoal[c.goalId] = (totalByGoal[c.goalId] ?? 0) + c.amount;
}
```

### Step 2: Pass each goal's total into `_GoalCard`

Change `_GoalCard` to take a `required double total` instead of computing it,
and drop its `db` field if `db` is no longer used inside it (check: the card's
"add deposit" button uses `db` for the bottom sheet — if so, keep `db`). Update
the call site:

```dart
child: _GoalCard(db: db, goal: g, total: totalByGoal[g.id] ?? 0),
```

### Step 3: Remove the per-goal `StreamBuilder<double>`

In `_GoalCard.build`, delete the `StreamBuilder<double>(stream: db.savingsDao.watchTotal(goal.id), ...)`
wrapper and use the injected `total` directly for `ratio`, the "الحالي" line,
and `_monthlyLabel(goal, total, money)`. The card body is otherwise unchanged.

**Verify**:
- `grep -n "watchTotal" lib/ui/savings_screen.dart` → **no matches** (the screen
  no longer opens per-goal SUM streams; `watchTotal` remains defined in the DAO
  and used by `goal_detail_screen.dart`).
- `flutter analyze` → `No issues found!`.

### Step 4: Format, analyze, full test

**Verify** (all must pass):
- `dart format lib test integration_test test_driver` then
  `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` → exit 0
- `flutter analyze` → `No issues found!`
- `flutter test` → all pass (no test targets this screen directly; the guard is
  that analysis and the existing suite stay green).

## Test plan

- No new automated test — this is a rendering refactor with no pure-logic
  surface to unit-test (the sum is a trivial fold). The existing suite must stay
  green.
- Manual smoke (optional, note in the PR): run the app with a couple of goals
  and several contributions; confirm each goal card shows the same "الحالي"
  total and progress bar as before, and updates live when a deposit is added.

## Done criteria

ALL must hold:

- [ ] `flutter analyze` → `No issues found!`
- [ ] `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` exits 0
- [ ] `flutter test` exits 0
- [ ] `grep -n "watchTotal" lib/ui/savings_screen.dart` → no matches
- [ ] `SavingsDao.watchTotal` still exists in `lib/data/database.dart` and is
      still used by `lib/ui/goal_detail_screen.dart`
- [ ] Each goal card derives its total from the single `watchAllContributions`
      stream
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- Removing `db` from `_GoalCard` breaks the "add deposit" button (it needs `db`
  for the bottom sheet) — keep `db`, only remove the total stream.
- `watchTotal` turns out to be used elsewhere you'd break by any change — it
  shouldn't be (this plan doesn't touch the DAO), but confirm before finishing.

## Maintenance notes

- The balance-is-always-SUM(contributions) invariant is preserved — the sum just
  moves from SQL to a one-line Dart fold over the stream the screen already
  reads. Don't reintroduce a stored balance field.
- If a future change adds many goals (unlikely for personal finance), this is
  already O(contributions) in one pass rather than O(goals) subscriptions.
- Reviewer: confirm `watchTotal` is retained for `goal_detail_screen.dart`.
