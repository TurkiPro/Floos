# Plan 004: Design local backup & restore (spike)

> **Executor instructions**: This is a **design/spike plan**, not a
> build-everything plan. Your deliverable is a written design document plus a
> narrow, reversible proof-of-concept — not a shipped feature. Do not build the
> full UI or migration surface. Follow the steps, produce the artifacts, and
> STOP for maintainer review at the marked point. When done, update the status
> row in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat b756b1a..HEAD -- lib/data/export.dart lib/data/database.dart`
> If either changed materially, re-read them before designing.

## Status

- **Priority**: P3
- **Effort**: L (design + POC; full build is a separate, later plan)
- **Risk**: LOW (spike is additive and gated; no changes to existing flows)
- **Depends on**: none (but 003's FK work informs the restore-ordering design)
- **Category**: direction
- **Planned at**: commit `b756b1a`, 2026-07-15

## Why this matters

Floos is offline-first with no cloud backup by deliberate choice (the README
lists cloud backup as intentionally out of scope — running a server would make
the project the custodian of everyone's financial data). But that leaves a real
gap for the exact users the app is built for: there is **no way to get data
back in**. `lib/data/export.dart` exports CSV *out*; nothing imports. So a user
who buys a new phone, or reinstalls, loses everything. A **local file** backup +
restore (export a full snapshot to a file the user controls, import it on another
device) closes that gap without touching the no-cloud stance — the file never
leaves the user's custody. This spike defines the format and the safest restore
semantics before anyone writes the feature.

## Current state

- `lib/data/export.dart` already produces CSVs: `buildTransactionsCsv` (one row
  per transaction, ISO dates, numeric amounts, UTF-8 BOM) and `buildStatsCsv`.
  These are analysis exports — **lossy** (no goals, no recurrence rules, no
  category metadata beyond id+name), so they are not a backup format. Reuse
  their conventions (BOM, numeric cells) but not their scope.
- The database has five tables (`lib/data/tables.dart`): `Categories` (with
  self-referential `parentId`), `RecurrenceRules`, `Transactions` (FK to both
  categories and rules via `recurrenceId`), `SavingsGoals`,
  `SavingsContributions`. A faithful backup must capture all five and restore
  them in FK-safe order.
- `AppDatabase` seeds default categories on first run (`onCreate`,
  `lib/data/database.dart:428`). Restore has to reconcile with rows that already
  exist (the defaults) — this is the core design question, not an afterthought.
- The README's "Not in v1" section explicitly defers **cloud** backup; a local
  file backup is *not* what it rejected. Confirm this framing holds before
  building (STOP condition if the README now rejects local backup too).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Install | `flutter pub get` | exit 0 |
| Codegen | `dart run build_runner build --delete-conflicting-outputs` | exit 0 |
| Format check | `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` | exit 0 |
| Analyze | `flutter analyze` | `No issues found!` |
| Tests | `flutter test` | all pass |

## Scope

**In scope**:
- `plans/004-backup-restore-design.md` (create — the design document; this is
  the primary deliverable)
- `lib/data/backup.dart` (create — a POC of `buildBackupJson` /
  `restoreBackupJson` covering the round-trip, pure data-layer, no UI)
- `test/backup_roundtrip_test.dart` (create — proves export→wipe→import restores
  identical data)
- `plans/README.md` (status update)

**Out of scope** (do NOT build in this spike):
- Any UI (no settings entry, no file picker, no share sheet). The POC is
  exercised only by tests.
- Any new dependency (`share_plus`, `file_picker`) — the design doc names them
  as future needs; the POC round-trips in-memory / to a temp path only.
- Encryption of the backup file — note it in the design's open questions; do not
  implement.
- Changing `export.dart` or any existing flow.

## Git workflow

- Branch: `advisor/004-backup-restore-spike`
- Commit style matches `git log` (imperative subject).
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Write the design document

Create `plans/004-backup-restore-design.md`. It must decide and justify:

1. **Format**: JSON (recommended — captures all five tables with types and
   nulls faithfully; CSV can't represent the relational shape). Define the
   top-level shape: a version field, an export timestamp, and one array per
   table with every column. Include a concrete example with 1–2 rows per table.
2. **Restore semantics** — the central decision. Present the options and pick
   one with reasoning:
   - **Replace** (wipe all tables, import the file wholesale): simplest,
     deterministic, matches "move to a new phone". Risk: destroys current data —
     must be behind an explicit, clearly-worded confirmation.
   - **Merge** (insert alongside existing): avoids data loss but creates
     duplicate categories/goals and id collisions; needs identity rules. More
     complex; usually not what a "restore" means.
   - Recommendation to argue for: **Replace**, because "restore a backup" means
     "make this device look like the backup", and merge's duplicate/identity
     problems aren't worth it for v1.
3. **ID strategy**: whether to preserve primary keys (needed so
   `Transactions.categoryId`, `parentId`, `recurrenceId`, `goalId` stay valid)
   or remap. Preserving keys under Replace is simplest; state it.
4. **FK-safe restore order**: categories (parents before children — sort by
   `parentId` null-first), then recurrence rules and goals, then transactions
   and contributions. Note the interaction with plan 003 (FK enforcement): once
   FKs are ON, insert order matters and a bad backup file must fail loudly.
5. **Validation & failure handling**: what makes a file invalid (wrong version,
   missing table, dangling FK), and the guarantee that a failed import leaves
   the existing DB untouched (import inside a single transaction that rolls back
   on any error).
6. **Open questions** for the maintainer: encryption? include archived rows?
   forward/backward compatibility across schema versions? file location and the
   `share_plus`/`file_picker` deps a real UI would need.

**Verify**: the file exists and covers all six points above.

### Step 2: Prototype the round-trip in the data layer

Create `lib/data/backup.dart` with two pure-ish functions:

- `Future<String> buildBackupJson(AppDatabase db)` — read all five tables, emit
  the JSON defined in Step 1.
- `Future<void> restoreBackupJson(AppDatabase db, String json)` — parse,
  validate, and under the **Replace** semantics wipe and re-insert, all inside
  `db.transaction(() async { ... })` so a failure rolls back.

Keep it minimal and dependency-free (use `dart:convert`). No UI, no file I/O
beyond what a test needs (a test can pass the JSON string directly).

**Verify**: `flutter analyze` → `No issues found!`.

### Step 3: Prove the round-trip with a test

Create `test/backup_roundtrip_test.dart` (in-memory DB pattern from
`test/widget_test.dart`). The test:

1. Seeds a known set across all five tables (a sub-category under a parent, a
   recurrence rule, a transaction generated from it, a goal, a contribution).
2. Captures `buildBackupJson`.
3. Wipes the DB (the `clearAll` DAO methods, or a fresh in-memory DB).
4. Runs `restoreBackupJson`.
5. Asserts every table's rows match what was seeded — including that
   `Transactions.recurrenceId` still points at the right rule and a
   sub-category's `parentId` still points at the right parent.
6. A negative case: malformed JSON leaves the DB unchanged (import rolls back).

**Verify**: `flutter test test/backup_roundtrip_test.dart` → all pass.

### Step 4: STOP for maintainer review

Do **not** build the UI, add dependencies, or wire a settings entry. Report:
the design doc, the POC, the passing round-trip test, and the open questions
from Step 1. The maintainer decides whether to green-light a follow-up
build plan.

**Verify**: `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` → exit 0; `flutter analyze` → `No issues found!`; `flutter test` → all pass.

## Test plan

- New file: `test/backup_roundtrip_test.dart`, cases in Step 3.
- Pattern: `test/widget_test.dart` (in-memory DB, `addTearDown`).
- Verification: `flutter test` → all pass.

## Done criteria

ALL must hold:

- [ ] `plans/004-backup-restore-design.md` exists and covers format, restore
      semantics (with a chosen recommendation), id strategy, restore order,
      validation/rollback, and open questions
- [ ] `lib/data/backup.dart` round-trips all five tables, restore wrapped in a
      transaction
- [ ] `flutter analyze` → `No issues found!`
- [ ] `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` exits 0
- [ ] `flutter test` exits 0; `test/backup_roundtrip_test.dart` passes, including
      the malformed-input rollback case
- [ ] No UI, no new dependency, `export.dart` untouched (`git status` shows only
      in-scope files)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- The README no longer frames only *cloud* backup as out of scope (i.e. it now
  rejects local backup too) — the product direction changed; confirm before
  building.
- Faithful restore appears to require preserving auto-increment primary keys in
  a way drift resists — document the constraint in the design doc and STOP
  rather than forcing it.
- The round-trip can't reproduce `recurrenceId`/`parentId` links — that's a
  format design flaw; fix the format in the doc, don't paper over it in the test.

## Maintenance notes

- This is a spike; the real feature (UI, file picker/share, encryption decision,
  cross-schema-version compatibility) is a separate plan gated on maintainer
  sign-off.
- The backup format is a long-lived contract: once users have backup files, the
  restore path must read old versions forever. The `version` field in Step 1 is
  what makes that possible — the design doc should say how a future importer
  handles an older version.
- If plan 003 (FK enforcement) lands first, restore must insert in FK-safe order
  and a dangling reference in a backup file must fail the import loudly rather
  than silently — fold that into the design.
