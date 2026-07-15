# Plan 005: Test the v4→v5 database migration

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 8edb242..HEAD -- lib/data/database.dart lib/data/tables.dart`
> If either changed since this plan was written, re-read the `onUpgrade` block
> in `lib/data/database.dart` before proceeding; on a material mismatch, treat
> it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: LOW (test + dev-dependency only; no production code changes)
- **Depends on**: none
- **Category**: tests
- **Planned at**: commit `8edb242`, 2026-07-15

## Why this matters

The database schema was bumped to v5, adding foreign-key enforcement and an
`ON DELETE SET NULL` on `transactions.recurrenceId`. The `onUpgrade` handler for
`from < 5` runs a raw `UPDATE` (to null orphaned recurrence links) and rebuilds
the `transactions` table via `m.alterTable`. **Every existing test builds a
fresh v5 database**, so this upgrade path has never executed against a v4
database. It will run for the first time on real users' devices, against their
only copy of their financial data — there is no server backup. Migrations are
the highest-risk code in a local-first app. This plan proves the upgrade
preserves data and applies the new delete behaviour, before it ships to anyone.

## Current state

The migration under test (`lib/data/database.dart`):

```dart
// lib/data/database.dart — inside MigrationStrategy.onUpgrade
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

And the per-connection FK pragma:

```dart
// lib/data/database.dart — MigrationStrategy.beforeOpen
beforeOpen: (details) async {
  await customStatement('PRAGMA foreign_keys = ON');
},
```

`schemaVersion` is `5` (`lib/data/database.dart`). Drift decides which migration
to run by comparing SQLite's `user_version` pragma against `schemaVersion`: a
database whose `user_version` is 4 triggers `onUpgrade(m, 4, 5)` on open.

**Why a fresh v5 test can't cover this**: with FK enforcement on, you cannot
even *create* the orphaned-`recurrenceId` state on a v5 database — the insert is
rejected. The orphan only exists in a pre-FK v4 database, so the test must stand
up a real v4 database file and open it through `AppDatabase`.

**Column names**: drift snake-cases Dart field names — `recurrenceId` →
`recurrence_id`, `categoryId` → `category_id`, `startDate` → `start_date`,
`lastMaterialized` → `last_materialized`, `targetAmount` → `target_amount`,
`goalId` → `goal_id`, `sortOrder` → `sort_order`, `iconKey` → `icon_key`,
`colorValue` → `color_value`, `parentId` → `parent_id`, `createdAt` →
`created_at`, `targetDate` → `target_date`.

**Test convention**: model after `test/foreign_keys_test.dart` (in-memory drift
DB, `addTearDown`). But this test needs a *file-backed* DB (so it can be closed
and re-opened) and a way to write raw v4 DDL before drift is involved — use
`package:sqlite3/sqlite3.dart` for the raw setup, then `AppDatabase` (drift) to
trigger the migration.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Install | `flutter pub get` | exit 0 |
| Codegen | `dart run build_runner build --delete-conflicting-outputs` | exit 0 |
| Format check | `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` | exit 0 |
| Analyze | `flutter analyze` | `No issues found!` |
| This test | `flutter test test/migration_v4_to_v5_test.dart` | all pass |
| Full suite | `flutter test` | all pass |

## Scope

**In scope**:
- `pubspec.yaml` (add `sqlite3` to **dev_dependencies** only — it's already a
  transitive dependency of drift, so this just makes it directly importable in a
  test)
- `test/migration_v4_to_v5_test.dart` (create)
- `plans/README.md` (status update)

**Out of scope** (do NOT touch):
- `lib/data/database.dart`, `lib/data/tables.dart` — the migration is the code
  under test; do not modify it. If the test reveals the migration is wrong,
  STOP and report — do not "fix" the migration in this plan.
- Any production code.

## Git workflow

- Branch: `advisor/005-test-v4-v5-migration`
- Commit style matches `git log` (imperative subject).
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Make `sqlite3` directly importable in tests

Add to `pubspec.yaml` under `dev_dependencies` (NOT `dependencies`):

```yaml
  sqlite3: ^2.4.0
```

Then `flutter pub get`. Confirm the resolved version is compatible; if pub
reports a version conflict with drift's constraint, use the version pub
suggests.

**Verify**: `flutter pub get` → exit 0.

### Step 2: Write the migration test

Create `test/migration_v4_to_v5_test.dart`. Structure:

1. Create a temp directory and a file path for the database
   (`Directory.systemTemp.createTempSync`).
2. **Build a v4 database with raw SQL** using `package:sqlite3/sqlite3.dart`:
   open the file, create all five tables with their v4 column shapes (names as
   listed in "Current state"), then `PRAGMA user_version = 4`. The v4
   `transactions` table has the same columns as today but no FK action matters
   (FK was off at v4). Dates can be stored as arbitrary integers — the migration
   never reads them, so the test asserts on structure/survival, not date values.
   Insert:
   - one category (`id = 1`),
   - one recurrence rule (`id = 1`, `category_id = 1`),
   - one transaction (`id = 1`, `category_id = 1`, `recurrence_id = 1`) — the
     valid link,
   - one transaction (`id = 2`, `category_id = 1`, `recurrence_id = 999`) — an
     **orphan** pointing at a non-existent rule.

   Close the raw sqlite3 database.
3. **Open the same file through drift** to trigger the migration:
   `AppDatabase(NativeDatabase(File(path)))`. (Import `dart:io`,
   `package:drift/native.dart`.) Drift sees `user_version = 4` and runs
   `onUpgrade(_, 4, 5)`, then `beforeOpen`.
4. Force the open by issuing a query (drift opens lazily), e.g.
   `final txns = await db.transactionDao.watchRecent().first;`.
5. Assert the migration outcomes:
   - Both transactions still exist (data preserved through the table rebuild).
   - Transaction 1 keeps `recurrenceId == 1`.
   - Transaction 2's `recurrenceId` is now `null` (orphan nulled by the UPDATE).
   - `PRAGMA foreign_keys` returns 1 (enforcement is on):
     `(await db.customSelect('PRAGMA foreign_keys').getSingle()).data.values.first == 1`.
6. Assert the new delete behaviour works post-migration: delete rule 1 via
   `db.recurrenceDao.deleteById(1)`, then re-read transaction 1 and assert its
   `recurrenceId` is now `null` (the `ON DELETE SET NULL` from the rebuilt
   table).
7. `addTearDown` to close the drift DB and delete the temp directory.

**Verify**: `flutter test test/migration_v4_to_v5_test.dart` → all pass.

### Step 3: Format, analyze, full test

**Verify** (all must pass):
- `dart format lib test integration_test test_driver` then
  `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` → exit 0
- `flutter analyze` → `No issues found!`
- `flutter test` → all pass, including the new migration test.

## Test plan

- New file: `test/migration_v4_to_v5_test.dart` — one test that stands up a v4
  DB, opens it through drift, and asserts data preservation + orphan-nulling +
  FK-on + post-migration SET NULL.
- Pattern: `test/foreign_keys_test.dart` for the drift/assertion style;
  `package:sqlite3/sqlite3.dart` for the raw v4 setup.
- Verification: `flutter test` → all pass.

## Done criteria

ALL must hold:

- [ ] `flutter analyze` → `No issues found!`
- [ ] `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` exits 0
- [ ] `flutter test` exits 0; `test/migration_v4_to_v5_test.dart` exists and passes
- [ ] The test opens a **v4** database (user_version = 4) through `AppDatabase`
      and asserts: both rows survive, the orphan link is nulled, FK is on, and
      post-migration rule-delete nulls the link
- [ ] `sqlite3` is added under `dev_dependencies` only (not `dependencies`)
- [ ] No production code (`lib/`) is modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- Opening the hand-built v4 database runs `onCreate` instead of `onUpgrade`
  (i.e. drift didn't see `user_version = 4`) — the raw setup's `PRAGMA
  user_version` didn't stick, or the tables weren't recognised. Report the
  observed `from`/`to` values.
- The migration **throws** on the v4 database (e.g. `m.alterTable`/
  `TableMigration` fails) — that is a real migration bug that would hit users on
  upgrade. Report the exact error; do NOT modify the migration to make the test
  pass.
- An assertion about data preservation fails (a row vanished, an amount
  changed) — again a real migration defect, report it.
- `sqlite3` can't be added without a version conflict that pub can't resolve —
  report it; a fallback is to build the v4 DB through a bare
  `NativeDatabase.memory()` executor with `customStatement` DDL, but only if the
  file-based sqlite3 route is truly blocked.

## Maintenance notes

- The gold-standard alternative is drift's schema-verification tooling
  (`drift_dev schema dump` + `SchemaVerifier`), which auto-generates historical
  schema snapshots. It isn't used here because the repo has no v4 snapshot (it
  wasn't dumped before v5 landed). If the team adopts that tooling, dump a
  snapshot at **every** future schema version so migrations get verified
  automatically — and this hand-rolled test can be retired.
- Any future `schemaVersion` bump must add a sibling test for the new
  `from < N` branch. Migrations are the one place a bug is unrecoverable for the
  user.
- Reviewer: confirm the test actually opens a v4 DB (not a fresh v5 one) — the
  whole value is in exercising the real upgrade path.
