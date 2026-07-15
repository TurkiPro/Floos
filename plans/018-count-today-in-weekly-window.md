# Plan 018: Count today's transactions in the weekly budget and spending window

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat db51b40..HEAD -- lib/services/alerts_coordinator.dart lib/domain/statistics_summary.dart lib/domain/date_grouping.dart lib/domain/calendar_format.dart`
> If any changed since this plan was written, compare the "Current state"
> excerpts against the live code before proceeding; on a mismatch, STOP.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW (pure boundary-condition fixes with unit tests)
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `db51b40`, 2026-07-15

## Why this matters

Every transaction added through the add sheet defaults to
`DateTime.now()` **with its time of day** (`add_transaction_sheet.dart:25`),
and is stored that way. But the weekly-budget and 84-day-window math uses
`!date.isAfter(today)` where `today` is **midnight**. A transaction stamped
today at 14:30 *is after* today-at-midnight, so it is silently excluded from:

- `spentThisWeek` — the number behind the app-icon badge and the
  weekly-budget alert. Spend 500 ر.س today and the badge still says you have
  it left. **The most-live number in the app is wrong all day, every day,**
  self-correcting only at midnight.
- the 84-day window that derives the recommended weekly budget and the
  statistics screen's "current pace" / top-weekday figures.

(Recurrence-generated rows and date-picker-chosen dates land at midnight and
are unaffected — which is why tests, which use midnight dates, never caught
this.) The same files also do calendar math with `Duration` arithmetic
(`subtract(const Duration(days: 84))`, `add(const Duration(days: 1))`),
which drifts by an hour across DST transitions — harmless in KSA but wrong
for users in DST countries (e.g. Egypt observes DST): day labels can call
yesterday "اليوم" and window boundaries shift. The repo's own convention
(`recurrence_math.dart:29`: "Uses DateTime constructor arithmetic throughout
so it is DST-safe") says how to do it; these sites predate the convention.

## Current state

- `lib/ui/add_transaction_sheet.dart:25` — `DateTime _date = DateTime.now();`
  (kept as-is; the fix is at the comparison boundaries so existing stored
  rows with times are also handled).
- `lib/services/alerts_coordinator.dart:71-88` (`computeWeeklyBudget`):

```dart
final today = DateTime(now.year, now.month, now.day);
final windowStart = today.subtract(const Duration(days: spendingWindowDays));
// Weeks here start on Saturday.
final daysSinceSaturday = (today.weekday + 1) % 7;
final weekStart = today.subtract(Duration(days: daysSinceSaturday));
...
if (!date.isBefore(weekStart) && !date.isAfter(today)) {
  spentThisWeek += amount;
}
if (!date.isBefore(windowStart) && !date.isAfter(today)) {
```

- `lib/domain/statistics_summary.dart:71-75` and `:127`:

```dart
final today = DateTime(now.year, now.month, now.day);
...
final windowStart =
    today.subtract(const Duration(days: spendingWindowDays));
...
if (!date.isBefore(windowStart) && !date.isAfter(today)) {
```

- `lib/domain/statistics_summary.dart:235-244` — `_countWeekday` steps with
  `d = d.add(const Duration(days: 1));`.
- `lib/domain/date_grouping.dart:11-18` (`dayLabel`) and `:107-115`
  (`dayFullLabel`), plus `lib/domain/calendar_format.dart:39-47`
  (`dayFullLabelFor`) — all compute
  `final diff = t.difference(d).inDays;` between two local midnights; across
  a DST change a "day" is 23h/25h and `inDays` truncates, mislabeling
  اليوم/أمس.
- Tests that pin current behavior: `test/weekly_budget_test.dart` (all dates
  midnight), `test/statistics_summary_test.dart`, `test/date_grouping_test.dart`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Deps | `flutter pub get` | exit 0 |
| Codegen | `dart run build_runner build --delete-conflicting-outputs` | exit 0 |
| Format | `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` | exit 0 |
| Analyze | `flutter analyze` | exit 0 |
| Focused tests | `flutter test test/weekly_budget_test.dart test/statistics_summary_test.dart test/date_grouping_test.dart` | all pass |
| Full tests | `flutter test` | all pass |

## Scope

**In scope**:
- `lib/services/alerts_coordinator.dart`
- `lib/domain/statistics_summary.dart`
- `lib/domain/date_grouping.dart`
- `lib/domain/calendar_format.dart`
- `test/weekly_budget_test.dart`, `test/statistics_summary_test.dart`,
  `test/date_grouping_test.dart` (add cases)

**Out of scope (do NOT touch)**:
- `lib/domain/recurrence_math.dart` — already DST-safe by construction.
- Normalizing `_date` to midnight in the add sheets — tempting, but it would
  not fix the rows already stored with times; the boundary fix handles both.
  (If the maintainer later wants midnight-normalized storage too, that's a
  separate cosmetic decision.)
- `lib/domain/dashboard_summary.dart`, `period_summary.dart`,
  `budget_progress.dart` — they compare year/month fields, not instants;
  they are already correct.

## Git workflow

- Branch: `advisor/018-count-today-in-weekly-window`
- Commit per step; imperative messages.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Inclusive-today boundaries via an exclusive `tomorrow`

In `computeWeeklyBudget` (`alerts_coordinator.dart`) and
`StatisticsSummary.from` (`statistics_summary.dart`), introduce next to
`today`:

```dart
// Exclusive upper bound: includes rows stamped today with a time-of-day
// (manual adds default to DateTime.now(), not midnight).
final tomorrow = DateTime(now.year, now.month, now.day + 1);
```

and replace every `!date.isAfter(today)` in those two functions with
`date.isBefore(tomorrow)`. (Three sites: weekly spend, window split in the
coordinator; window split in the summary.)

**Verify**: `grep -n "isAfter(today)" lib/services/alerts_coordinator.dart lib/domain/statistics_summary.dart`
→ no matches.

### Step 2: DST-safe calendar steps

Replace `Duration`-based day arithmetic with constructor arithmetic
(the `recurrence_math.dart` convention):

- `alerts_coordinator.dart`:
  `today.subtract(const Duration(days: spendingWindowDays))` →
  `DateTime(today.year, today.month, today.day - spendingWindowDays)`;
  `today.subtract(Duration(days: daysSinceSaturday))` →
  `DateTime(today.year, today.month, today.day - daysSinceSaturday)`.
- `statistics_summary.dart`: same replacement for `windowStart`; in
  `_countWeekday`, `d = d.add(const Duration(days: 1));` →
  `d = DateTime(d.year, d.month, d.day + 1);`.
- `date_grouping.dart` (`dayLabel`, `dayFullLabel`) and
  `calendar_format.dart` (`dayFullLabelFor`): compute the day difference in
  UTC so a 23/25-hour local day can't truncate:

```dart
final dd = DateTime.utc(day.year, day.month, day.day);
final tt = DateTime.utc(today.year, today.month, today.day);
final diff = tt.difference(dd).inDays;
```

**Verify**: `grep -n "Duration(days" lib/services/alerts_coordinator.dart lib/domain/statistics_summary.dart lib/domain/date_grouping.dart lib/domain/calendar_format.dart`
→ no matches.

### Step 3: Regression tests

- `test/weekly_budget_test.dart`: add "a transaction stamped today with a
  time of day counts toward this week and the window" — insert
  `date: DateTime(2026, 7, 15, 14, 30)` (the file's fixed `now` is
  2026-07-15) and assert `spentThisWeek` includes it and `recommended`
  reflects it. This test FAILS before Step 1 and passes after.
- `test/statistics_summary_test.dart`: same-shaped case asserting
  `currentWeeklyPace`/window totals include a timed today-transaction.
- `test/date_grouping_test.dart`: `dayLabel`/`dayFullLabel` with `day` and
  `today` built from plain `DateTime(y,m,d)` still return اليوم/أمس exactly
  as before (guards the UTC rewrite). Note honestly in the test file that a
  true DST scenario can't be simulated in-process (the Dart VM's local zone
  is fixed); the UTC construction is correct by construction.

**Verify**: `flutter test test/weekly_budget_test.dart test/statistics_summary_test.dart test/date_grouping_test.dart`
→ all pass, including the new cases.

### Step 4: Full suite

**Verify**: `dart format --output=none --set-exit-if-changed lib test integration_test test_driver && flutter analyze && flutter test`
→ all exit 0.

## Test plan

Covered in Step 3 — the timed-today cases are the regression tests for the
actual bug; the existing midnight-based tests guard against off-by-one at the
new `tomorrow` boundary (a midnight-today row must still count exactly once).

## Done criteria

- [ ] No `isAfter(today)` remains in the two computation files (grep, Step 1)
- [ ] No `Duration(days` remains in the four in-scope lib files (grep, Step 2)
- [ ] New timed-today tests exist and pass; full `flutter test` green
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- Any existing test fails after Step 1 — that would mean somewhere *depends*
  on excluding today's timed rows; report which test.
- The excerpts don't match the live code (drift).

## Maintenance notes

- Any new window/period math should use `DateTime(y, m, d ± n)` constructor
  arithmetic and half-open ranges (`>= start && < endExclusive`) — this is
  now the convention in all four files, matching `recurrence_math.dart`.
- The notification scheduler (`notification_service.dart`) has its own
  `TZDateTime.add(Duration)` steps with the same DST-drift shape — left
  out of scope here because it schedules wall-clock reminders (an hour's
  drift once a year, self-correcting on next reschedule). Recorded in
  `plans/README.md` as a known nit.
