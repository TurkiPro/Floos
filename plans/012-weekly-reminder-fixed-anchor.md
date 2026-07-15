# Plan 012: Anchor the weekly reminder to a fixed weekday

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat db51b40..HEAD -- lib/services/notification_service.dart`
> If the file changed since this plan was written, compare the "Current state"
> excerpt against the live code before proceeding; on a mismatch, STOP.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `db51b40`, 2026-07-15

## Why this matters

A user who sets the "log your spending" reminder to **أسبوعيًا (weekly)** can
receive it almost **daily**. The weekly branch schedules the notification at
"the next instance of the chosen time" — i.e. today or tomorrow — and repeats
it weekly *on whatever weekday that happened to be*. But
`NotificationService.reschedule()` runs on **every app launch and resume**
(`main.dart:27`, `home_screen.dart:52`) and on every settings change, each time
re-anchoring the "weekly" reminder to fire within the next 24 hours. For an
active user the weekly cadence degenerates into a daily nag on a drifting
weekday — precisely what they opted out of by not choosing يوميًا. Compare the
weekly-budget alert in the same file, which correctly anchors to a fixed
Saturday.

## Current state

- `lib/services/notification_service.dart:115-123` — the buggy branch:

```dart
case ReminderCadence.weekly:
  await _scheduleRepeating(
    id: _idReminder,
    title: 'سجّل مصاريف أسبوعك',
    body: 'خصّص دقيقة لتحديث مصاريف هذا الأسبوع.',
    when: _nextInstanceOfTime(time.hour, time.minute),
    match: DateTimeComponents.dayOfWeekAndTime,
  );
  break;
```

- The correct pattern, three lines away (`:139-151`, the weekly-budget alert):

```dart
when:
    _nextInstanceOfWeekday(DateTime.saturday, time.hour, time.minute),
match: DateTimeComponents.dayOfWeekAndTime,
```

- `_nextInstanceOfWeekday` already exists (`:241-248`).
- Weekday choice, decided here so you don't have to: **Sunday**
  (`DateTime.sunday`). Rationale: the app's week starts Saturday (see
  `computeWeeklyBudget`'s week-start math in
  `lib/services/alerts_coordinator.dart:73-75`); Saturday at the reminder time
  is already taken by the weekly-budget alert (`_idWeeklyBudget`) and Friday by
  the stats nudge (`_idStats`). Sunday — the first workday in the app's home
  market — avoids stacking two notifications at the same minute while staying
  at the top of the week.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Deps | `flutter pub get` | exit 0 |
| Codegen | `dart run build_runner build --delete-conflicting-outputs` | exit 0 |
| Format | `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` | exit 0 |
| Analyze | `flutter analyze` | exit 0 |
| Tests | `flutter test` | all pass |

## Scope

**In scope** (the only file you should modify):
- `lib/services/notification_service.dart`

**Out of scope** (do NOT touch):
- The `everyOtherDay` branch — its "schedule one, re-arm on next launch"
  behavior is a documented platform-limitation workaround, not this bug.
- The daily branch, the weekly-budget/stats/salary alerts.
- `lib/app_settings.dart` — a user-facing weekday picker is a possible
  follow-up feature, deliberately not in this fix.

## Git workflow

- Branch: `advisor/012-weekly-reminder-fixed-anchor`
- One commit; imperative message, e.g. "Anchor the weekly reminder to Sunday"
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Fix the weekly branch

Replace the `when:` argument in the `ReminderCadence.weekly` case with the
fixed-weekday helper, and add a one-line comment stating the constraint the
code can't show:

```dart
case ReminderCadence.weekly:
  // Anchored to a fixed weekday: reschedule() runs on every launch/resume,
  // and an anchor of "today-or-tomorrow" + weekly matching would re-arm the
  // reminder to fire within 24h every time — i.e. daily. Sunday avoids
  // stacking on the Saturday budget alert and the Friday stats nudge.
  await _scheduleRepeating(
    id: _idReminder,
    title: 'سجّل مصاريف أسبوعك',
    body: 'خصّص دقيقة لتحديث مصاريف هذا الأسبوع.',
    when: _nextInstanceOfWeekday(DateTime.sunday, time.hour, time.minute),
    match: DateTimeComponents.dayOfWeekAndTime,
  );
  break;
```

**Verify**: `grep -n "DateTime.sunday" lib/services/notification_service.dart`
→ one match inside the weekly case.

### Step 2: Full verification

**Verify**: `dart format --output=none --set-exit-if-changed lib test integration_test test_driver && flutter analyze && flutter test`
→ all exit 0.

## Test plan

`NotificationService` is a thin wrapper over the platform plugin and has no
existing test seam (all members are static, the plugin no-ops off-device);
the suite proves nothing regressed. Adding a scheduling-time abstraction to
make this unit-testable is real work the maintainer hasn't asked for — out of
scope. The grep in Step 1 plus code review is the gate.

## Done criteria

- [ ] The `ReminderCadence.weekly` case calls `_nextInstanceOfWeekday(DateTime.sunday, ...)`
- [ ] `grep -n "_nextInstanceOfTime" lib/services/notification_service.dart`
      shows it used by the daily and everyOtherDay branches and inside
      `_nextInstanceOfWeekday` only — not in the weekly case
- [ ] `flutter analyze` exits 0, `flutter test` all pass
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The weekly case no longer matches the "Current state" excerpt (drift).
- You find a product/design note (commit message, comment, doc) saying the
  drifting anchor was intentional — surface it instead of changing behavior.

## Maintenance notes

- Natural follow-up (not in scope): let the user pick the reminder weekday in
  Settings next to the time picker; store it in `AppSettings` alongside
  `reminderHour`/`reminderMinute` and pass it here.
- Reviewer should sanity-check the other three alert anchors still read:
  budget=Saturday, stats=Friday, salary=one-off date.
