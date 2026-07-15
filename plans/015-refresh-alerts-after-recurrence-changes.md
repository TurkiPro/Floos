# Plan 015: Keep alerts and badge honest when the data changes

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat db51b40..HEAD -- lib/ui/add_recurrence_sheet.dart lib/ui/add_income_sheet.dart lib/ui/income_screen.dart lib/ui/recurring_screen.dart lib/ui/settings_screen.dart lib/services/alerts_coordinator.dart`
> If any changed since this plan was written, compare the "Current state"
> excerpts against the live code before proceeding; on a mismatch, STOP.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `db51b40`, 2026-07-15

## Why this matters

The salary-day notification is scheduled as a **one-off** from the soonest
upcoming recurring-income occurrence, re-armed by `refreshAlerts(db, settings)`
— which today runs only on launch, resume, settings toggles, and after adding
a plain transaction. Mutating the **recurrence rules themselves never
re-arms it**. Concretely:

- Create your salary rule → no salary-day notification until the next
  launch/resume happens to occur.
- Delete or pause the salary rule → the already-scheduled "يوم الراتب!"
  notification **still fires** on the old date.
- Edit the rule's date/schedule → the notification fires on the stale date.

The same staleness applies to the weekly-budget alert body and app-icon badge
when a recurring **expense** rule changes. The fix is mechanical: call
`refreshAlerts` after each rule mutation, exactly as
`add_transaction_sheet.dart` already does after inserting a transaction.

Three adjacent honesty bugs in the same subsystem, fixed here too because the
diffs are two lines each:

- **"حذف كل البيانات" leaves the alert schedule and badge armed with the
  deleted data** (`settings_screen.dart:338-348`): after wiping every table,
  no `refreshAlerts` runs — the badge keeps showing a weekly budget derived
  from deleted transactions, and a scheduled salary alert for a deleted rule
  will still fire. The wipe is also four sequential deletes with no
  transaction around them.
- **Opening the app on salary day cancels that day's salary alert**
  (`alerts_coordinator.dart:58`): `_nextSalaryDate` uses
  `afterExclusive: today`, so an occurrence dated *today* is skipped and
  `reschedule()`'s `cancelAll()` erases the already-scheduled alert for this
  evening. The home header solved this exact problem with
  `afterExclusive: today.subtract(const Duration(days: 1))`
  (`home_screen.dart:174` — its comment: "an occurrence dated today still
  counts"); the coordinator predates that fix.
- **The notifications toggle ignores the OS permission result**
  (`settings_screen.dart:146-150`): `requestPermission()`'s return value is
  discarded, so Settings can show alerts "on" while the OS will never show
  one.

## Current state

`refreshAlerts` (in `lib/services/alerts_coordinator.dart:27`) is called from:
`main.dart:27`, `home_screen.dart:52` (resume), `settings_screen.dart` (each
toggle), `add_transaction_sheet.dart:54`. Verify with
`grep -rn "refreshAlerts" lib/` before starting.

The four mutation sites that do NOT call it:

1. `lib/ui/add_recurrence_sheet.dart:97-145` — `_save()` (creates or edits a
   rule, then runs catch-up):

```dart
await RecurrenceEngine(widget.db).catchUp();
if (mounted) Navigator.of(context).pop();
```

2. `lib/ui/add_recurrence_sheet.dart:71-95` — `_delete()`:

```dart
await widget.db.recurrenceDao.deleteById(widget.existingRule!.id);
if (mounted) Navigator.of(context).pop();
```

3. `lib/ui/add_income_sheet.dart:51-68` — `_save()` when `_recurring` is true
   (creates a monthly income rule + catch-up).

4. `lib/ui/income_screen.dart:93-103` and `lib/ui/recurring_screen.dart:111-121`
   — the active/paused `Switch` on each rule card:

```dart
onChanged: (v) async {
  if (v) {
    await db.recurrenceDao.reactivate(r.id);
    await RecurrenceEngine(db).catchUp();
  } else {
    await db.recurrenceDao.pause(r.id);
  }
},
```

Convention to match (`lib/ui/add_transaction_sheet.dart:50-55`): read
`AppSettings` via `context.read<AppSettings>()` after a `mounted` check,
fire-and-forget the refresh (no await needed — it's best-effort):

```dart
if (!mounted) return;
final settings = context.read<AppSettings>();
...
refreshAlerts(widget.db, settings);
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Deps | `flutter pub get` | exit 0 |
| Codegen | `dart run build_runner build --delete-conflicting-outputs` | exit 0 |
| Format | `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` | exit 0 |
| Analyze | `flutter analyze` | exit 0 |
| Tests | `flutter test` | all pass |

## Scope

**In scope** (the only files you should modify):
- `lib/ui/add_recurrence_sheet.dart`
- `lib/ui/add_income_sheet.dart`
- `lib/ui/income_screen.dart`
- `lib/ui/recurring_screen.dart`
- `lib/ui/settings_screen.dart` (delete-all + notifications toggle only)
- `lib/services/alerts_coordinator.dart` (one line: `_nextSalaryDate`'s
  `afterExclusive`)

**Out of scope** (do NOT touch):
- `lib/services/notification_service.dart` — the scheduling mechanics are
  fine; this plan is about *when* rescheduling runs and *what date* feeds it.
- Transaction deletion staleness — plan 014 owns that.
- Debouncing/coalescing rapid toggles — `reschedule()` is cheap (cancelAll +
  ≤4 zonedSchedule calls) and idempotent.

## Git workflow

- Branch: `advisor/015-refresh-alerts-after-recurrence-changes`
- One commit; imperative message, e.g. "Re-arm alerts after recurrence changes"
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: add_recurrence_sheet.dart — save and delete

In `_save()`, after the `catchUp()` call and before the pop, insert (matching
the sheet's existing `mounted` discipline):

```dart
await RecurrenceEngine(widget.db).catchUp();
if (!mounted) return;
// A rule just changed shape — the salary-day one-off and the weekly-budget
// figures derive from the rules, so re-arm them now rather than at next launch.
refreshAlerts(widget.db, context.read<AppSettings>());
Navigator.of(context).pop();
```

In `_delete()`, same pattern after the `deleteById` and `mounted` check.

Add imports: `package:provider/provider.dart`, `../app_settings.dart`,
`../services/alerts_coordinator.dart`.

**Verify**: `flutter analyze` → exit 0.

### Step 2: add_income_sheet.dart — recurring create

In `_save()`, the `if (!mounted) return;` line already exists after the
writes. After it (in the `_recurring` case only — a one-off income doesn't
change any alert input; but an unconditional call is also acceptable and
simpler — choose unconditional), add:

```dart
refreshAlerts(widget.db, context.read<AppSettings>());
```

(`context.read<AppSettings>()` is already used in this method for the sound —
reuse that `settings` variable if you hoist it.)

Add import: `../services/alerts_coordinator.dart`.

**Verify**: `flutter analyze` → exit 0.

### Step 3: the two rule switches

In `income_screen.dart` and `recurring_screen.dart`, extend the switch
handler:

```dart
onChanged: (v) async {
  if (v) {
    await db.recurrenceDao.reactivate(r.id);
    await RecurrenceEngine(db).catchUp();
  } else {
    await db.recurrenceDao.pause(r.id);
  }
  if (context.mounted) {
    refreshAlerts(db, context.read<AppSettings>());
  }
},
```

Add the needed imports (`../app_settings.dart`,
`../services/alerts_coordinator.dart`; `provider` is already imported in
both files).

**Verify**: `flutter analyze` → exit 0 — pay attention to
`use_build_context_synchronously`: the `context.mounted` guard above is what
keeps it quiet.

### Step 4: Delete-all — atomic wipe + refresh

In `settings_screen.dart` `_confirmClear` (lines ~338-348), wrap the four
clears in a drift transaction and re-arm afterwards:

```dart
if (ok == true) {
  await db.transaction(() async {
    await db.transactionDao.clearAll();
    await db.savingsDao.clearAll();
    await db.recurrenceDao.clearAll();
    await db.budgetDao.clearAll();
  });
  if (!context.mounted) return;
  // The schedule/badge derived from the deleted data must not survive it.
  await refreshAlerts(db, context.read<AppSettings>());
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('تم حذف كل البيانات')),
  );
}
```

**Verify**: `flutter analyze` → exit 0.

### Step 5: Salary alert survives being opened on salary day

In `lib/services/alerts_coordinator.dart` `_nextSalaryDate`, change

```dart
afterExclusive: today,
```

to

```dart
// Exclusive of yesterday => an occurrence dated today still counts, so
// opening the app on salary morning doesn't cancel tonight's alert.
// (Same fix as _salaryHint in home_screen.dart.)
afterExclusive: today.subtract(const Duration(days: 1)),
```

Note the downstream guard already handles the edge this creates:
`notification_service.dart:174` skips scheduling when the computed time is
already in the past (`if (when.isAfter(tz.TZDateTime.now(tz.local)))`).

**Verify**: `flutter test test/weekly_budget_test.dart` → passes (the
coordinator file's other function is under test there);
`flutter analyze` → exit 0.

### Step 6: Honor the permission result in the notifications toggle

In `settings_screen.dart` (lines ~146-150), the toggle's `onChanged`:

```dart
onChanged: (v) async {
  if (v) {
    final granted = await NotificationService.requestPermission();
    if (!granted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('التنبيهات مرفوضة من النظام — فعّلها من إعدادات الجهاز.')));
      }
      return; // leave the setting off; the OS will never deliver anyway
    }
  }
  settings.setNotificationsEnabled(v);
  await refreshAlerts(db, settings);
},
```

(Platform note, so you don't "fix" it away: on desktop/web
`requestPermission()` returns false because the plugin is unsupported —
that's correct behavior here too, since no notification would ever fire
there either.)

**Verify**: `flutter analyze` → exit 0.

### Step 7: Full suite

**Verify**: `dart format --output=none --set-exit-if-changed lib test integration_test test_driver && flutter analyze && flutter test`
→ all exit 0, and `grep -rn "refreshAlerts" lib/ui/` now lists
add_transaction_sheet, add_recurrence_sheet (×2), add_income_sheet,
income_screen, recurring_screen, home_screen, settings_screen (toggle sites
+ delete-all).

## Test plan

`refreshAlerts` bottoms out in platform plugins that no-op off-device, so its
*effects* aren't unit-testable in this repo's harness; the existing suite
proves no regression. The grep in Step 4 is the completeness check. (If the
maintainer later wants this testable, the seam is injecting a scheduler
interface into `NotificationService` — deliberately out of scope.)

## Done criteria

- [ ] All four rule-mutation sites call `refreshAlerts` after their writes
- [ ] Delete-all wipes inside one `db.transaction` and re-arms alerts after
- [ ] `_nextSalaryDate` uses `afterExclusive: today.subtract(1 day)`
- [ ] The notifications toggle leaves the setting off when permission is denied
- [ ] `flutter analyze` exits 0 (no async-context lints), `flutter test` passes
- [ ] Grep in Step 7 shows the expected call-site list
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- Any of the four sites no longer matches its excerpt (drift).
- `flutter analyze` flags `use_build_context_synchronously` after you applied
  the guards as written — report the exact diagnostic rather than sprinkling
  `ignore:` comments.

## Maintenance notes

- Any future write-path that changes recurrence rules, transactions, or
  notification-relevant settings should end with `refreshAlerts` — reviewers
  should treat a rule mutation without it as a smell (this is now the
  established convention at seven call sites).
- If the number of call sites keeps growing, the cleaner shape is a single
  DAO-level hook or a drift table listener — deliberately not done now
  (7 explicit call sites are still legible; a listener hides the trigger).
