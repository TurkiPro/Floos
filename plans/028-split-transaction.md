# Plan 028: Split one transaction across categories (schema v15)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `grep -n "schemaVersion" lib/data/database.dart`.
> If it is no longer 14, another schema plan landed first — renumber this
> migration to the next free version and say so in your report.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED (schema change; interacts with import de-duplication)
- **Depends on**: —
- **Category**: feature (batch 5)
- **Planned at**: commit `f54f113`, 2026-11-05

## Why this matters

One Panda receipt of 420 SAR is often 300 groceries + 120 household. Today it
can only be filed under one category, so either category budgets or the
essentials/luxuries split come out wrong.

## Design decision: split rows, not a child table

A split becomes **several ordinary `Transactions` rows** sharing a
`splitGroupId`. Every existing sum, budget, weekly figure and stat keeps
working with zero changes, because each part *is* a normal transaction. A
child "splits" table would instead require every query in the app to learn
about it.

```dart
// tables.dart, Transactions
// Non-null => this row is one part of a split purchase. All parts share the
// value, which is the id of the part that was the original row. No FK: the
// group is a label, and deleting one part must not take the others with it.
IntColumn get splitGroupId => integer().nullable()();
```

Migration v15: `m.addColumn(transactions, transactions.splitGroupId)`.
Backup: write it; read it leniently (`t['splitGroupId'] as int?`). Restore keeps
row ids (`backup.dart` inserts with `id: Value(t['id'])`), so group ids stay
valid — verify that in the round-trip test.

## Rules

- **Expense only, manual or imported only.** Do not allow splitting a row with
  a `recurrenceId` in this plan: the engine and the import's recurrence-collision
  check key on `(rule, date)` and `(amount, date)`, and a split generated row
  would make both lie. Hide the action for those rows.
- Parts keep the original's `date`, `note`, `importBatchId`; each has its own
  `amount` and `categoryId`. Parts must sum to the original to the halala
  (validate `|sum − original| < 0.005`); the last part's field offers
  "the rest" automatically.
- Undo of an import still works unchanged: every part carries the batch id, so
  CASCADE removes them all.

## The import de-duplication trap (important)

`import_review_screen.dart` builds ledger fingerprints from each
`(amount, date, note)`. After a 420 → 300 + 120 split, re-pasting the same bank
message would find neither 300 nor 120 matching 420 and **import it again as a
fresh row**. Fix: when building fingerprints, group rows by `splitGroupId` and
fingerprint the group as `(sum of parts, date, note of the original part)`, in
addition to the per-row fingerprints. Write the failing test first.

## UI

- `DayGroupCard` / `transaction_row.dart`: a split part shows a small split
  icon; tapping any part opens the split editor for the whole group.
- Edit sheet for a non-generated expense: action «تقسيم على أكثر من فئة».
- Split editor: the original total at the top (read-only), a list of
  (amount, category) rows, "+ جزء", a live "remaining" line, Save disabled until
  it reaches 0. «إلغاء التقسيم» merges back into one row with the first part's
  category.
- DAO: `TransactionDao.split(int id, List<({double amount, int categoryId})>)`
  and `unsplit(int groupId)`, each in one `transaction(() async {...})` so a
  half-written split cannot exist.

## Steps

1. Schema + migration + backup + migration test (extend
   `test/migration_upgrade_test.dart` with a v14 → v15 path; existing rows get
   null).
2. DAO `split`/`unsplit` + tests: sum mismatch rejected; generated row
   rejected; parts inherit date/note/batch; unsplit restores one row; undoing
   the import removes all parts.
3. De-dup fix + test: split an imported row, re-review the same message, it is
   flagged `duplicateOfLedger`.
4. UI + widget test.

## Verification

```
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```

## STOP conditions

- A screen shows a split purchase as N separate purchases in a way that changes
  a *count* the user sees (e.g. "transactions this week: 3") → report it; decide
  with the maintainer whether counts should be per-group.
