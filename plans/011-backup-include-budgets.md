# Plan 011: Make the backup format cover category budgets

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat db51b40..HEAD -- lib/data/backup.dart test/backup_roundtrip_test.dart plans/004-backup-restore-design.md`
> If any changed since this plan was written, compare the "Current state"
> excerpts against the live code before proceeding; on a mismatch, STOP.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `db51b40`, 2026-07-15

## Why this matters

The backup/restore engine (`lib/data/backup.dart`, the plan-004 spike) was
written against schema v5 and serializes **five** tables. Schema **v6** then
added a sixth — `category_budgets` (the user-set monthly budgets behind
`BudgetsScreen`) — and the backup was never updated. Two concrete failures:

1. A backup file **silently omits every budget** the user set.
2. Restore is worse than omission: it deletes all categories, and
   `CategoryBudgets.categoryId` is declared `ON DELETE CASCADE`
   (`lib/data/tables.dart:70-71`), so **restoring a backup wipes the user's
   existing budgets** and the file has nothing to put back.

No UI invokes restore yet, so no user has been bitten — but plan 016 (the
backup/restore UI) builds directly on this code. This gap must close first,
or the shipped feature will destroy budgets on every restore.

## Current state

- `lib/data/backup.dart:34-39` — `buildBackupJson` reads five tables:

```dart
final categories = await db.select(db.categories).get();
final rules = await db.select(db.recurrenceRules).get();
final txns = await db.select(db.transactions).get();
final goals = await db.select(db.savingsGoals).get();
final contributions = await db.select(db.savingsContributions).get();
```

No `db.categoryBudgets` anywhere in the file
(`grep -n categoryBudgets lib/data/backup.dart` → no matches today).

- `lib/data/backup.dart:142-148` — restore validates exactly five section keys.
- `lib/data/backup.dart:162-167` — restore deletes children-before-parents
  (transactions, contributions, rules, goals, sub-categories, categories);
  budgets are deleted only implicitly via the category CASCADE.
- `lib/data/tables.dart:67-73` — the table being added to the format:

```dart
class CategoryBudgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId =>
      integer().references(Categories, #id, onDelete: KeyAction.cascade)();
  RealColumn get amount => real()(); // monthly limit
}
```

- `const backupFormatVersion = 1;` (`lib/data/backup.dart:28`). **Decision,
  inline so you don't have to make it**: keep version **1**. No producer of
  this format has ever shipped (there is no UI), so there are no v1 files in
  the wild without budgets — except files someone made by hand running the
  POC, which the "tolerate absent section" rule below still restores
  correctly. Do NOT bump to 2.
- Design doc to update: `plans/004-backup-restore-design.md` documents the
  format ("one array per table") and its example JSON.
- Test to extend: `test/backup_roundtrip_test.dart` — seeds all five tables via
  `_seed()` and asserts a roundtrip into a fresh DB.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Deps | `flutter pub get` | exit 0 |
| Codegen | `dart run build_runner build --delete-conflicting-outputs` | exit 0 |
| Format | `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` | exit 0 |
| Analyze | `flutter analyze` | exit 0 |
| Focused tests | `flutter test test/backup_roundtrip_test.dart` | all pass |
| Full tests | `flutter test` | all pass |

## Scope

**In scope** (the only files you should modify):
- `lib/data/backup.dart`
- `test/backup_roundtrip_test.dart`
- `plans/004-backup-restore-design.md` (format section + example only)

**Out of scope** (do NOT touch):
- `lib/data/tables.dart`, `lib/data/database.dart` — no schema change here.
- Any UI — plan 016 owns the UI.
- `lib/data/export.dart` — the CSV export is deliberately lossy; budgets stay
  out of it.

## Git workflow

- Branch: `advisor/011-backup-include-budgets`
- One commit; imperative message, e.g. "Include category budgets in backup format"
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Serialize budgets in buildBackupJson

In `lib/data/backup.dart`, read the sixth table alongside the others and add a
`'categoryBudgets'` array to the map (same style as the existing sections):

```dart
final budgets = await db.select(db.categoryBudgets).get();
...
'categoryBudgets': [
  for (final b in budgets)
    {
      'id': b.id,
      'categoryId': b.categoryId,
      'amount': b.amount,
    },
],
```

**Verify**: `flutter analyze` → exit 0.

### Step 2: Restore budgets (tolerating their absence)

In `restoreBackupJson`:

1. Do **not** add `'categoryBudgets'` to the required-sections loop at
   lines 142–148 — an absent section must restore as "no budgets" so any
   hand-made five-section v1 file still restores. Instead read it leniently:

```dart
final budgetRows = root['categoryBudgets'] is List
    ? (root['categoryBudgets'] as List).cast<Map<String, dynamic>>()
    : const <Map<String, dynamic>>[];
```

2. In the wipe block, delete budgets explicitly **first** (before categories),
   with a comment noting the CASCADE would otherwise do it implicitly — the
   explicit delete keeps the wipe order self-documenting:

```dart
await db.delete(db.categoryBudgets).go();
```

3. After the categories are inserted (budgets reference them), insert the
   budget rows preserving ids:

```dart
for (final b in budgetRows) {
  await db.into(db.categoryBudgets).insert(CategoryBudgetsCompanion.insert(
        id: Value(b['id'] as int),
        categoryId: b['categoryId'] as int,
        amount: b['amount'] as double,
      ));
}
```

**Verify**: `flutter analyze` → exit 0.

### Step 3: Extend the roundtrip test

In `test/backup_roundtrip_test.dart`:

1. In `_seed()`, set a budget: `await db.budgetDao.setBudget(1, 2500);`
2. In the roundtrip test, assert it comes back:

```dart
final budgets = await target.budgetDao.getAll();
expect(budgets.single.categoryId, 1);
expect(budgets.single.amount, 2500);
```

3. Add a new test — the regression this plan exists for — "restore does not
   destroy budgets it can't represent... and a budget-less v1 file restores
   with zero budgets": build a JSON string with the five original sections
   only (you can `jsonDecode` a real backup, remove the `categoryBudgets`
   key, re-encode), restore it into a DB that has a budget set, and assert
   `getAll()` is empty afterwards (replace semantics) **without** throwing.
4. Add: restore into a target that already has a budget → after restore the
   target's budgets equal exactly the backup's budgets (proves the explicit
   wipe).
5. Add a corrupt-row rollback test (a gap the audit flagged separately: the
   existing failure tests never reach the DB-write phase): take a valid
   backup JSON, corrupt one transaction row's type (e.g. set `"amount"` to a
   string), restore it into a DB that has known data, assert it throws
   (any `Exception` — the POC surfaces raw cast errors, which is accepted
   behavior recorded in `plans/README.md`) and that the pre-existing data is
   fully intact afterwards (the mid-transaction rollback guarantee).

Model the test structure on the existing tests in the same file.

**Verify**: `flutter test test/backup_roundtrip_test.dart` → all pass
(existing 4 + new assertions/tests).

### Step 4: Update the design doc

In `plans/004-backup-restore-design.md`, format section: add
`categoryBudgets` to the table list and to the example JSON (one row:
`{"id": 1, "categoryId": 1, "amount": 2500.0}`), and note the lenient-absence
rule: "a file without a `categoryBudgets` section restores with zero budgets
(pre-v6 spike files)."

**Verify**: `grep -n categoryBudgets plans/004-backup-restore-design.md` → ≥2 matches.

### Step 5: Full suite

**Verify**: `dart format --output=none --set-exit-if-changed lib test integration_test test_driver && flutter analyze && flutter test`
→ all exit 0.

## Test plan

Covered in Step 3: roundtrip includes budgets; absent-section leniency; the
wipe-then-restore replacement of pre-existing budgets. Pattern:
`test/backup_roundtrip_test.dart` (existing tests in the same file).

## Done criteria

- [ ] `grep -c categoryBudgets lib/data/backup.dart` ≥ 3 (build, wipe, insert)
- [ ] `flutter test test/backup_roundtrip_test.dart` → all pass, including the
      new budget assertions and the absent-section test
- [ ] `flutter test` exits 0
- [ ] Design doc mentions `categoryBudgets`
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- `lib/data/backup.dart` already mentions `categoryBudgets` (drift — someone
  fixed it).
- The schema has moved past v6 (check `schemaVersion` in
  `lib/data/database.dart`) and yet more tables are missing from the backup —
  report the full gap instead of patching only budgets.
- Any existing backup test fails before you change anything.

## Maintenance notes

- **Standing rule this plan establishes**: every future schema migration that
  adds a table or column must touch `lib/data/backup.dart` and
  `test/backup_roundtrip_test.dart` in the same change. A reviewer of any
  future "schema vN" PR should ask "does the backup know?".
- Plan 016 (backup/restore UI) depends on this landing first.
