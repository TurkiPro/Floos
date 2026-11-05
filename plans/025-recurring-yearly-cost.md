# Plan 025: Show what recurring expenses cost over a year

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> **No schema change, no new date math.**

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: —
- **Category**: feature (batch 5)
- **Planned at**: commit `f54f113`, 2026-11-05

## Why this matters

Recurring charges are invisible in aggregate. 39 SAR a month for a
subscription looks like nothing; 468 SAR a year is a decision. The obligations
screen (`recurring_screen.dart`, «الالتزامات الشهرية») lists each rule's amount
and frequency but never adds them up.

## Design

### Domain — `lib/domain/recurring_cost.dart` (new, pure)

```dart
/// What [rule] will actually charge between [from] (inclusive) and
/// [from] + 12 months (exclusive).
double costNext12Months(RecurrenceRule rule, DateTime from);

/// Sum over active expense rules.
double totalNext12Months(List<RecurrenceRule> rules, DateTime from);
```

- **Count real occurrences** with the existing `occurrencesBetween` in
  `lib/domain/recurrence_math.dart` — not `amount × 12`. That is what makes an
  end date, an interval of 2, a yearly charge due in 3 months, or a rule
  starting next month all come out right, and it reuses the engine's own
  month-end clamping (a charge on the 31st). Writing a second
  "frequency → multiplier" table would be a second source of truth and would be
  wrong for every rule with an end date.
- Only `type == expense && active`. A paused rule costs nothing.
- Honour a pending `nextOverrideDate` the same way `upcomingCommitments` does
  (it replaces the next scheduled occurrence, it does not add one).

### UI — `recurring_screen.dart`

- A summary card at the top: «خلال ١٢ شهرًا القادمة: X ر.س» and, beneath it,
  «≈ Y لكل دورة» where Y = X / 12. Say "per cycle", not "per month" — the salary
  cycle is the app's only period unit.
- Each rule row gets a trailing secondary line with its own 12-month cost.
- A sort toggle in the app bar: by next date (current) / by yearly cost.

## Steps

1. Tests first (`test/recurring_cost_test.dart`): monthly → 12×; every-2-months
   → 6×; weekly → 52 or 53 depending on `from` (assert against
   `occurrencesBetween`, not a constant); yearly due in 3 months → 1×; end date
   in 5 months → 5×; paused → 0; income rule → excluded; override date moves
   the next charge but does not add one.
2. Implement; build the card and sort.

## Verification

```
flutter analyze
flutter test test/recurring_cost_test.dart
flutter test
```

## STOP conditions

- `occurrencesBetween` does not handle overrides and adding it would change
  engine behaviour → STOP; handle the override in `recurring_cost.dart` only.
