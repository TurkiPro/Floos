# Plan 014: Give swipe-to-delete an Undo (and keep the badge honest)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat db51b40..HEAD -- lib/ui/widgets/transaction_row.dart lib/data/database.dart`
> If either changed since this plan was written, compare the "Current state"
> excerpts against the live code before proceeding; on a mismatch, STOP.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `db51b40`, 2026-07-15

## Why this matters

A transaction — a real financial record in an app with **no backup feature
yet** — is deleted by a single swipe with no confirmation, no undo, and no
feedback beyond the row vanishing. An accidental swipe in a scrolling list
silently and permanently destroys data. Every serious list UI (Gmail, iOS
Mail, Material guidelines for `Dismissible`) pairs destructive swipes with an
undo affordance. Additionally, deleting an expense changes the weekly-budget
numbers, but the app-icon badge and scheduled alert texts are only recomputed
on launch/resume/add — a delete leaves them stale.

## Current state

- `lib/ui/widgets/transaction_row.dart:25-38` — the swipe:

```dart
return Dismissible(
  key: ValueKey(row.txn.id),
  direction: DismissDirection.endToStart,
  background: Container(...),
  onDismissed: (_) => db.transactionDao.deleteById(row.txn.id),
  child: ...
```

`TransactionRow` is shared by the home day-list, the income screen and
month-detail browsing (all wrap it in day cards via `DayGroupCard`).

- `lib/data/database.dart:120-134` — `TransactionDao.add(...)` inserts via
  `TransactionsCompanion.insert(...)` but does **not** accept an `id` or
  `recurrenceId`, so it cannot resurrect a deleted row faithfully; a new
  DAO method is needed for undo.
- The add-transaction sheet already shows the convention for refreshing OS
  surfaces after a write — `lib/ui/add_transaction_sheet.dart:51-54`:

```dart
final settings = context.read<AppSettings>();
SoundService.playSaved(enabled: settings.soundEnabled);
// Keeps the weekly-budget badge in step with the new spending.
refreshAlerts(widget.db, settings);
```

- Snackbar convention: `ScaffoldMessenger.of(context).showSnackBar(SnackBar(...))`
  with Arabic copy (see `settings_screen.dart:92-95`).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Deps | `flutter pub get` | exit 0 |
| Codegen | `dart run build_runner build --delete-conflicting-outputs` | exit 0 |
| Format | `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` | exit 0 |
| Analyze | `flutter analyze` | exit 0 |
| Focused test | `flutter test test/transaction_undo_test.dart` | all pass |
| Full tests | `flutter test` | all pass |

## Scope

**In scope** (the only files you should modify/create):
- `lib/ui/widgets/transaction_row.dart`
- `lib/data/database.dart` (one new DAO method on `TransactionDao`)
- `test/transaction_undo_test.dart` (create)

**Out of scope** (do NOT touch):
- Savings contributions / goals deletion — they have no delete UI at all;
  that's a separate feature decision (see plans/README "direction" notes).
- Confirmation dialogs — undo-after-the-fact is the chosen UX, not
  confirm-before (a dialog on every swipe would punish the common case).
- The recurrence engine: an undone generated transaction keeps its original
  `recurrenceId`; the rule's `lastMaterialized` marker never moved, so
  catch-up cannot double-create. Do not touch marker logic.

## Git workflow

- Branch: `advisor/014-undo-swipe-delete`
- Commit per step; imperative messages.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add a faithful re-insert to TransactionDao

In `lib/data/database.dart`, next to `deleteById` (line ~147), add:

```dart
/// Re-inserts a just-deleted transaction with its original id and links —
/// the undo path for swipe-to-delete. Safe because the id was freed by the
/// delete moments earlier; keeping it preserves the recurrenceId link and
/// list position.
Future<void> restore(Txn txn) {
  return into(transactions).insert(TransactionsCompanion.insert(
    id: Value(txn.id),
    amount: txn.amount,
    categoryId: txn.categoryId,
    type: txn.type,
    date: txn.date,
    note: Value(txn.note),
    recurrenceId: Value(txn.recurrenceId),
    createdAt: Value(txn.createdAt),
  ));
}
```

**Verify**: `dart run build_runner build --delete-conflicting-outputs && flutter analyze` → exit 0.

### Step 2: Wire undo + alert refresh into the swipe

In `lib/ui/widgets/transaction_row.dart`, replace the `onDismissed` handler:

```dart
onDismissed: (_) {
  final settings = context.read<AppSettings>();
  final messenger = ScaffoldMessenger.of(context);
  final deleted = row.txn;
  db.transactionDao.deleteById(deleted.id).then((_) {
    // The badge/alert texts derive from spending; keep them in step with
    // the deletion, same as add_transaction_sheet does on insert.
    refreshAlerts(db, settings);
  });
  messenger.showSnackBar(SnackBar(
    content: const Text('تم حذف الحركة'),
    action: SnackBarAction(
      label: 'تراجع',
      onPressed: () {
        db.transactionDao.restore(deleted).then((_) {
          refreshAlerts(db, settings);
        });
      },
    ),
  ));
},
```

Add the two imports (`../../app_settings.dart` is NOT needed —
`context.read<AppSettings>()` needs `provider`, already imported; add
`../../services/alerts_coordinator.dart`). Capture `settings` and `messenger`
**before** any await/async gap (as shown) — the row unmounts on dismissal, so
`context` must not be touched inside the callbacks.

**Verify**: `flutter analyze` → exit 0 (in particular no
`use_build_context_synchronously` warning).

### Step 3: Test the restore path

Create `test/transaction_undo_test.dart` (model after
`test/foreign_keys_test.dart` — in-memory DB, seeded category id 1):

1. `restore resurrects a deleted transaction byte-for-byte`: add a transaction
   (with a note), read it back as `Txn`, `deleteById`, assert list empty,
   `restore(txn)`, assert the row is back with the **same id, amount, date,
   note, createdAt**.
2. `restore preserves the recurrence link`: create a rule (see
   `foreign_keys_test.dart:22-32` for the pattern), `insertGenerated`, read the
   row, delete it, restore it, assert `recurrenceId` still points at the rule.
3. `catch-up does not duplicate a restored occurrence`: after test 2, run
   `RecurrenceEngine(db).catchUp()` and assert the transaction count is
   unchanged (the marker never moved back).

**Verify**: `flutter test test/transaction_undo_test.dart` → 3 tests pass.

### Step 4: Full suite

**Verify**: `dart format --output=none --set-exit-if-changed lib test integration_test test_driver && flutter analyze && flutter test`
→ all exit 0.

## Test plan

Covered in Step 3. No widget test for the SnackBar: the harness's
`widget_test.dart` covers the shared tree, and SnackBar-action plumbing is
framework behavior; the data-integrity of undo is what needs the net.

## Done criteria

- [ ] `TransactionDao.restore` exists and is covered by 3 passing tests
- [ ] `transaction_row.dart` shows a SnackBar with a تراجع action on dismiss
- [ ] `refreshAlerts` is called after both delete and undo
- [ ] `flutter analyze` exits 0, `flutter test` all pass
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- `onDismissed` no longer matches the excerpt (drift).
- Restoring with an explicit id throws a constraint error in the tests —
  that would mean id reuse is unsafe in this drift/sqlite setup, and the undo
  design needs to switch to "insert without id" + accept a changed id, which
  is a semantics decision for the maintainer.

## Maintenance notes

- If a "recycle bin"/soft-delete ever lands, this SnackBar-undo becomes its
  thin front-end; the `restore` DAO method is reusable as-is.
- Reviewer: check the SnackBar isn't shown twice when several rows are swiped
  quickly (each swipe replaces the previous snackbar — default
  ScaffoldMessenger behavior — losing the older undo; acceptable, but worth a
  conscious nod).
