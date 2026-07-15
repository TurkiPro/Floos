# Plan 003: Enforce foreign keys with deliberate delete semantics

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat b756b1a..HEAD -- lib/data/database.dart lib/data/tables.dart`
> If either file changed since this plan was written, compare the "Current
> state" excerpts against the live code before proceeding; on a mismatch, treat
> it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: none (but land after 001 so the test suite is richer)
- **Category**: tech-debt
- **Planned at**: commit `b756b1a`, 2026-07-15

## Why this matters

Every table declares `.references(...)` foreign keys, but SQLite ignores foreign
keys unless `PRAGMA foreign_keys = ON` is set per connection — and this app never
sets it (confirmed: no `beforeOpen`/`PRAGMA` anywhere in `lib/`). So the
constraints are decorative. The concrete consequence today: deleting a
recurrence rule via `RecurrenceDao.deleteById` leaves the transactions it
generated pointing at a rule id that no longer exists (`recurrenceId` dangles).
It's low-impact right now (that column is provenance only, and the data is
single-user), but it's a latent trap: the day someone turns FK enforcement on
without thinking through delete behaviour, rule deletion will start throwing.
This plan turns enforcement on **and** defines the delete behaviour that makes
it safe, so referential integrity is real instead of aspirational.

## Current state

Foreign keys are declared but never enforced.

Tables and their references (`lib/data/tables.dart`):

```dart
// lib/data/tables.dart:16  (Categories)
IntColumn get parentId => integer().nullable().references(Categories, #id)();
// lib/data/tables.dart:32  (RecurrenceRules)
IntColumn get categoryId => integer().references(Categories, #id)();
// lib/data/tables.dart:50  (Transactions)
IntColumn get categoryId => integer().references(Categories, #id)();
// lib/data/tables.dart:55  (Transactions)
IntColumn get recurrenceId => integer().nullable().references(RecurrenceRules, #id)();
// lib/data/tables.dart:76  (SavingsContributions)
IntColumn get goalId => integer().references(SavingsGoals, #id)();
```

The database class has a `MigrationStrategy` with `onCreate` and `onUpgrade` but
**no `beforeOpen`**:

```dart
// lib/data/database.dart:427
MigrationStrategy get migration => MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
        await _seedDefaultCategories();
        await _seedDefaultSubcategories();
      },
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          await m.addColumn(categories, categories.parentId);
          await m.addColumn(categories, categories.kind);
        }
        if (from < 4) {
          await _seedDefaultSubcategories();
        }
      },
    );
```

The only hard-delete of a parent row that has children is
`RecurrenceDao.deleteById` (`lib/data/database.dart:331`) — deleting a rule that
has generated transactions. (Categories and goals are archived, not deleted; see
`CategoryDao.archive` at `lib/data/database.dart:76` and `SavingsDao` which has
no per-goal delete. `clearAll` methods delete children-before-parents already.)

**Decision to encode**: when a recurrence rule is deleted, its generated
transactions should be **kept** (they represent real money that changed hands)
but their `recurrenceId` should become NULL (the rule is gone). That is
`ON DELETE SET NULL` on `Transactions.recurrenceId`. All other references should
be `ON DELETE RESTRICT` (the default) — you must not be able to delete a category
or goal out from under rows that point at it; those are archived, never deleted,
so RESTRICT never fires in normal use but guards against a future bug.

Drift expresses this in the column definition, e.g.:
`integer().nullable().references(RecurrenceRules, #id, onDelete: KeyAction.setNull)()`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Install | `flutter pub get` | exit 0 |
| Codegen | `dart run build_runner build --delete-conflicting-outputs` | exit 0; regenerates `lib/data/database.g.dart` |
| Format check | `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` | exit 0 |
| Analyze | `flutter analyze` | `No issues found!` |
| Tests | `flutter test` | all pass |
| Single test | `flutter test test/foreign_keys_test.dart` | all pass |

> Changing `tables.dart` requires re-running codegen before analyze/test.

## Scope

**In scope**:
- `lib/data/tables.dart` (add `onDelete: KeyAction.setNull` to
  `Transactions.recurrenceId` only)
- `lib/data/database.dart` (add `beforeOpen` enabling the pragma; bump
  `schemaVersion`; add an `onUpgrade` branch that runs the FK-integrity
  migration for existing installs)
- `test/foreign_keys_test.dart` (create)
- `plans/README.md` (status update)

**Out of scope** (do NOT touch):
- Any other column's reference semantics — leave them at the default (RESTRICT).
- The DAO method bodies — no query changes are needed; enabling the pragma and
  the `setNull` action does the work.
- `_seedDefaultCategories` / `_seedDefaultSubcategories`.

## Git workflow

- Branch: `advisor/003-enforce-foreign-keys`
- Commit style matches `git log` (imperative subject, sentence body).
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Enable enforcement per connection

In `lib/data/database.dart`, add a `beforeOpen` to the `MigrationStrategy`:

```dart
beforeOpen: (details) async {
  await customStatement('PRAGMA foreign_keys = ON');
},
```

`customStatement` is available on the database accessor (drift). This makes SQLite
enforce FKs for **every** connection, including the in-memory test DB.

**Verify**: `dart run build_runner build --delete-conflicting-outputs` → exit 0,
then `flutter analyze` → `No issues found!`.

### Step 2: Set the delete action on `recurrenceId`

In `lib/data/tables.dart`, change line 55 to:

```dart
IntColumn get recurrenceId =>
    integer().nullable().references(RecurrenceRules, #id, onDelete: KeyAction.setNull)();
```

Leave every other `.references(...)` unchanged.

**Verify**: `dart run build_runner build --delete-conflicting-outputs` → exit 0.

### Step 3: Bump the schema version and migrate existing installs

Existing users' databases were created without this FK action baked into the
`Transactions` table. On SQLite, the delete action is part of the table
definition, so existing installs need their `Transactions` table rebuilt for the
`SET NULL` behaviour to apply. Do this in `onUpgrade`.

1. Change `schemaVersion` from `4` to `5` (`lib/data/database.dart:424`).
2. Add to `onUpgrade`:

```dart
if (from < 5) {
  // Rebuild Transactions so recurrenceId gains ON DELETE SET NULL, and
  // proactively null out any recurrenceId that already points at a
  // deleted rule (FK enforcement would otherwise reject the rebuild).
  await customStatement(
    'UPDATE transactions SET recurrence_id = NULL '
    'WHERE recurrence_id IS NOT NULL '
    'AND recurrence_id NOT IN (SELECT id FROM recurrence_rules)',
  );
  await m.alterTable(TableMigration(transactions));
}
```

`m.alterTable(TableMigration(...))` is drift's helper for recreating a table
from its current Dart definition, preserving data. Confirm the exact API against
the installed drift version (2.16) — if `TableMigration`'s constructor differs,
read drift's migration docs rather than guessing (STOP condition).

> The column name in SQL is `recurrence_id` (drift snake-cases `recurrenceId`).
> Confirm by inspecting the generated `lib/data/database.g.dart` after codegen if
> unsure.

**Verify**: `dart run build_runner build --delete-conflicting-outputs` → exit 0,
`flutter analyze` → `No issues found!`.

### Step 4: Test the enforced behaviour

Create `test/foreign_keys_test.dart` (in-memory DB pattern from
`test/widget_test.dart`). Cover:

- **`setNull` on rule delete**: add a recurrence rule, generate/add a
  transaction with that `recurrenceId`, delete the rule via
  `db.recurrenceDao.deleteById(id)`, then read the transaction back and assert
  it still exists and its `recurrenceId` is now null.
- **RESTRICT protects categories**: attempt to delete a category row that a
  transaction references (via a raw `db.customStatement('DELETE FROM categories WHERE id = ?', ...)`
  or the lowest-level delete available) and assert it throws. If there is no
  code path that deletes a category, assert the pragma is on instead:
  `final r = await db.customSelect('PRAGMA foreign_keys').getSingle();` and
  assert the value is 1. Prefer whichever is straightforward; the pragma check
  is the reliable one.
- **Pragma is on for a fresh DB**: `PRAGMA foreign_keys` returns 1.

**Verify**: `flutter test test/foreign_keys_test.dart` → all pass.

### Step 5: Format, analyze, full test

**Verify** (all must pass):
- `dart format lib test integration_test test_driver` then
  `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` → exit 0
- `flutter analyze` → `No issues found!`
- `flutter test` → all pass, including the new file, and the existing
  `widget_test.dart` (which exercises a fresh DB with the new `beforeOpen`).

## Test plan

- New file: `test/foreign_keys_test.dart`, cases as listed in Step 4.
- Pattern: `test/widget_test.dart` (in-memory DB, `addTearDown(db.close)`).
- Verification: `flutter test` → all pass.

## Done criteria

ALL must hold:

- [ ] `dart run build_runner build --delete-conflicting-outputs` exits 0
- [ ] `flutter analyze` → `No issues found!`
- [ ] `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` exits 0
- [ ] `flutter test` exits 0; `test/foreign_keys_test.dart` exists and passes
- [ ] `schemaVersion` is 5 and an `if (from < 5)` migration branch exists
- [ ] `grep -n "foreign_keys" lib/data/database.dart` shows the pragma is set
- [ ] Deleting a rule nulls its transactions' `recurrenceId` (proven by test)
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- The `MigrationStrategy` or `tables.dart` in the live code differs from the
  "Current state" excerpts (drift — the schema may have moved past v4).
- `schemaVersion` is already greater than 4 — someone added a migration since
  this plan was written; reconcile the version numbers before proceeding.
- The `TableMigration` / `alterTable` API in drift 2.16 differs from Step 3 —
  read drift's official migration guide and report the correct call rather than
  guessing (a wrong migration corrupts real user data on upgrade).
- Enabling the pragma makes an existing test fail because it relied on a
  now-illegal cross-reference — that's a latent data-integrity bug; report it.

## Maintenance notes

- Migrations are the single most dangerous change in this app: they run against
  real user databases on upgrade, and there is no server backup. The reviewer
  must scrutinise the `if (from < 5)` branch specifically, and ideally test the
  upgrade path (open a v4 DB, upgrade to v5, confirm data survives) — drift
  supports schema-version migration tests; consider adding one as follow-up.
- If a per-category or per-goal hard delete is ever added, revisit its
  `onDelete` action deliberately (archived-not-deleted is why RESTRICT is safe
  today).
- The `alterTable`/table-rebuild in Step 3 is only needed because SQLite bakes
  the FK action into the table definition. New installs get it via `onCreate`
  automatically; the migration is purely for existing users.
