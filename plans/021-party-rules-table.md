# Plan 021: Remember what each party means, and make an import undoable (schema v13)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> **This plan adds NO UI.** It is schema + DAOs + backup coverage + tests. The
> import screen that uses it is plan 022. If you find yourself editing anything
> under `lib/ui/`, STOP.
>
> **Drift check (run first)**:
> `git diff --stat ba8d695..HEAD -- lib/data/database.dart lib/data/tables.dart lib/data/backup.dart`
> If `schemaVersion` is no longer 12, this plan's migration number is stale —
> renumber to the next free version and report that you did.

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: MED-HIGH (schema migration on a live financial database, plus a
  cascading delete path)
- **Depends on**: 020 (uses its party normalization; no code dependency, but
  the key format must match)
- **Category**: feature (batch 4)
- **Planned at**: commit `ba8d695`, 2026-09-21

## Why this matters

This plan carries two things the import needs, both of which are schema.

### 1. Remembering what a party means

Parsing gets you amount + date + merchant. What is left is the only real work:
deciding what each row *means*. Doing that from scratch on every import would
make batch entry barely faster than one-at-a-time.

The 13-message sample shows why a plain merchant→category map is not enough:

- `KR-133` and `**7772` are a POS terminal code and an account number. They are
  permanently unreadable unless the user can **name** them once.
- `إلى : **7772` is an outgoing transfer. Whether that is an expense, a savings
  contribution, or money between the user's own accounts is something only the
  user knows — and the answer is the same every time.
- `إضافة اموال` (top-ups) must be **ignored entirely**, or the same riyals get
  counted twice: once when loaded onto the card and again when spent. In the
  sample that is 635 SAR of phantom spending on its own.

So the stored decision is not a category, it is a **disposition**: what to do
with money involving this party. Answer once, and every future import of that
party is pre-resolved — which is what turns this feature from "faster typing"
into "confirm a list".

The app already has the right destinations for each disposition:
`Transactions` (expense/income) and the `SavingsContributions` ledger.

### 2. Making an import undoable

A batch import writes many rows at once from text the app parsed heuristically.
The user must be able to take that back in one action — otherwise a bad paste
means deleting rows one at a time through swipe-to-delete, which is exactly the
tedium this feature exists to remove.

Undo needs the rows to remember which import produced them, so it is a schema
change, not a UI trick: an `ImportBatches` table plus a nullable batch pointer
on both ledgers. Undo then deletes the batch row and lets the database cascade.

Undo also removes the party rules **that batch first created** (not ones it
merely re-used), so "undo, fix, re-import" actually works as a correction path.
Otherwise a miscategorized merchant would be re-applied on the re-import from
the rule the bad import had just taught it.

## Current state

- `schemaVersion` is **12** (`lib/data/database.dart:730`). Migrations are a
  chain of `if (from < N)` blocks in `onUpgrade`; v10/v11 are the model for
  adding a new table, v7/v8/v12 for adding a column.
- `PRAGMA foreign_keys = ON` is set in `beforeOpen`, so FK actions are real
  (plan 003). Choose delete semantics deliberately.
- `Transactions.recurrenceId` uses `ON DELETE SET NULL` **on purpose**:
  deleting a recurrence rule keeps its generated rows because that was real
  money. The batch pointer added here is the opposite case and uses CASCADE —
  see Step 2, and do not "fix" one to match the other.
- Backup (`lib/data/backup.dart`) keeps `backupFormatVersion = 1` and reads
  **new sections leniently** — see the `categoryBudgets` comment at
  `backup.dart:211-215`: a pre-v6 file has no such section and must restore as
  "none" rather than fail. Only the original five sections are required
  (`backup.dart:196-205`). Follow that pattern; **do not bump
  `backupFormatVersion`** or every existing backup file stops restoring.
- `restoreBackupJson` wipes tables in FK-safe order (`backup.dart:235-243`)
  then re-inserts. New tables must be added to both halves.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Deps | `flutter pub get` | exit 0 |
| Codegen | `dart run build_runner build --delete-conflicting-outputs` | exit 0 |
| Format | `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` | exit 0 |
| Analyze | `flutter analyze` | exit 0 |
| Focused tests | `flutter test test/party_rules_test.dart test/import_batch_test.dart` | all pass |
| Full tests | `flutter test` | all pass |

## Scope

**In scope**:
- `lib/data/enums.dart` — add `PartyDisposition`
- `lib/data/tables.dart` — add `PartyRules` and `ImportBatches`; add a nullable
  `importBatchId` to `Transactions` and `SavingsContributions`
- `lib/data/database.dart` — register both tables, `schemaVersion` → 13, the
  `from < 13` migration block, `PartyRuleDao`, `ImportBatchDao`
- `lib/data/backup.dart` — write + read the two new sections (leniently) and
  the two new columns
- `lib/domain/party_key.dart` (create) — the pure lookup-key normalization
- `test/party_key_test.dart`, `test/party_rules_test.dart`,
  `test/import_batch_test.dart` (create)
- The existing backup and migration tests (extend)

**Out of scope (do NOT touch)**:
- Anything under `lib/ui/` — including a rule-management screen and the undo
  button itself. Both are 022.
- Applying rules during an import (022).
- Undo for anything other than a whole batch. Individual imported rows are
  deleted the normal way, through existing swipe-to-delete.
- Auto-creating recurrence rules from repeated merchants. Explicitly rejected:
  the recurrence engine is the sole writer of generated transactions, and
  mixing the two writers is the double-count risk 022 must guard against.

## Git workflow

- Branch: `advisor/021-party-rules-and-import-batches`
- Commit per step; imperative messages.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: The disposition enum

In `lib/data/enums.dart`:

```dart
/// What an imported transaction involving a given party means. Stored by
/// index — append new values at the end only.
enum PartyDisposition {
  expense,   // a purchase; [categoryId] says which category
  income,    // money in; [categoryId] says which income category
  savings,   // a deposit into a goal; [goalId] says which
  ignore,    // own money moving (card top-ups, transfers between own
             // accounts). Recording these double-counts the spending that
             // follows, so they are never written to the ledger.
}
```

### Step 2: The tables

In `lib/data/tables.dart`:

```dart
/// One run of the bank-message importer. Exists so a whole batch can be taken
/// back in one action: the rows it wrote point at it with ON DELETE CASCADE,
/// so deleting this row deletes them.
///
/// Note the contrast with [Transactions.recurrenceId], which is deliberately
/// SET NULL — a generated transaction is real money that outlives its rule.
/// An imported batch is the opposite: it is a single user action, and undoing
/// it means the rows were never meant to exist.
@DataClassName('ImportBatch')
class ImportBatches extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get importedAt => dateTime().withDefault(currentDateAndTime)();
  // What was written, so the undo confirmation can state it without a scan.
  IntColumn get rowCount => integer()();
  RealColumn get totalAmount => real()();
  // Rows the user marked "ignore" — parsed, deliberately not written.
  IntColumn get ignoredCount => integer().withDefault(const Constant(0))();
}

/// One remembered decision about a merchant or transfer destination, keyed by
/// the normalized string the bank sends ("RED BOX", "**7772", "KR-133").
///
/// The stored decision is a DISPOSITION, not just a category: a bank message
/// can mean a purchase, income, a savings deposit, or nothing at all (a card
/// top-up is the user's own money moving, and recording it would double-count
/// the purchases that follow). [displayName] exists because the bank's own
/// strings are frequently unreadable — a POS terminal code or an account
/// number — and naming one once should fix it forever.
@DataClassName('PartyRule')
class PartyRules extends Table {
  IntColumn get id => integer().autoIncrement()();
  // Normalized via partyKey(); unique (the DAO upserts on it).
  TextColumn get partyKey => text().withLength(min: 1, max: 120)();
  // What the bank literally sent, kept for display and debugging.
  TextColumn get rawParty => text().withLength(min: 1, max: 120)();
  // The user's readable name for this party, if they gave one.
  TextColumn get displayName => text().nullable()();
  IntColumn get disposition => intEnum<PartyDisposition>()();
  // Set when disposition is expense/income. CASCADE: a rule pointing at a
  // deleted category can never be applied, so it goes with it.
  IntColumn get categoryId => integer()
      .nullable()
      .references(Categories, #id, onDelete: KeyAction.cascade)();
  // Set when disposition is savings.
  IntColumn get goalId => integer()
      .nullable()
      .references(SavingsGoals, #id, onDelete: KeyAction.cascade)();
  // The import that FIRST taught this rule, if any. CASCADE so undoing that
  // import also forgets what it learned — otherwise "undo, fix, re-import"
  // would re-apply the same wrong category from the rule the bad import just
  // created. Rules a batch merely re-used keep their original batch here and
  // are untouched.
  IntColumn get createdByBatchId => integer()
      .nullable()
      .references(ImportBatches, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [{partyKey}];
}
```

And add to **both** `Transactions` and `SavingsContributions`:

```dart
  // Non-null => this row came from a bank-message import. CASCADE: deleting
  // the batch is how "undo this import" is implemented.
  IntColumn get importBatchId => integer()
      .nullable()
      .references(ImportBatches, #id, onDelete: KeyAction.cascade)();
```

### Step 3: The lookup key

Create `lib/domain/party_key.dart`. Pure, no imports beyond dart core.

```dart
/// Normalizes a bank-supplied merchant/destination string into a stable
/// lookup key: case-folded, whitespace-collapsed, trimmed.
///
/// Plan 020's parser has already stripped the "SA /" country prefix and the
/// trailing '*' the bank uses to mark a truncated name.
String partyKey(String raw);

/// True when [a] and [b] are the same party despite the bank truncating one
/// of them. The bank truncates at a fixed width, so the shorter key being a
/// prefix of the longer is a reliable signal — but only once it is long
/// enough to be distinctive.
bool partyMatches(String a, String b, {int minPrefix = 6});
```

`partyMatches` is exact-match OR one is a prefix of the other AND the shorter
is at least `minPrefix` characters. This is a heuristic; it is here so
`Ali bin Ab` (truncated) resolves to a rule saved as `Ali bin Abi Taleb`.

### Step 4: Register, migrate, DAOs

In `lib/data/database.dart`:

- Add `PartyRules` and `ImportBatches` to the `@DriftDatabase(tables: [...])`
  list and both DAOs to `daos:`.
- `schemaVersion` → **13**.
- Append to `onUpgrade`, after the `from < 12` block:

```dart
// v13 adds the bank-message importer's storage: what each merchant or
// transfer destination means (so a batch arrives pre-categorized), and a
// batch record both ledgers point at so a whole import can be undone in one
// action. No back-fill — existing rows have a null batch and are not part of
// any import.
if (from < 13) {
  await m.createTable(importBatches);
  await m.createTable(partyRules);
  await m.addColumn(transactions, transactions.importBatchId);
  await m.addColumn(savingsContributions, savingsContributions.importBatchId);
}
```

> **SQLite caveat — verify, do not assume.** `ALTER TABLE ADD COLUMN` with a
> `REFERENCES` clause is only legal while foreign keys are enabled if the
> column's default is NULL. Both columns here are nullable with no default, so
> this is fine — but Step 7 must prove that the cascade actually fires on a
> **migrated** database, not only on a freshly created one. A fresh install and
> an upgraded install can differ here, and this is a delete path on financial
> rows.

- `PartyRuleDao`:
  - `Future<PartyRule?> lookup(String rawParty)` — normalize with `partyKey`,
    try an exact match first, then scan for a `partyMatches` hit. **Exact wins
    over prefix**, always.
  - `Future<void> remember({required String rawParty, required PartyDisposition disposition, String? displayName, int? categoryId, int? goalId, int? createdByBatchId})`
    — upsert on `partyKey`. On update, leave `createdByBatchId` as it was: only
    the batch that first created a rule owns it.
  - `Stream<List<PartyRule>> watchAll()`, `Future<void> deleteById(int id)`.
  - Assert the invariant: `expense`/`income` require a `categoryId`, `savings`
    requires a `goalId`, `ignore` requires neither.
- `ImportBatchDao`:
  - `Future<int> create({required int rowCount, required double totalAmount, required int ignoredCount})`
  - `Future<ImportBatch?> latest()` — most recent by `importedAt`, then `id`.
  - `Stream<List<ImportBatch>> watchRecent({int limit = 20})`
  - `Future<void> undo(int batchId)` — delete the batch row inside a
    transaction and let CASCADE remove its transactions, contributions and
    first-created rules. **Do not hand-delete the child rows**; the whole point
    of the FK action is that undo cannot half-apply.
  - `Future<({int txns, int contributions})> countsFor(int batchId)` — for the
    confirmation dialog.

**Verify**: `dart run build_runner build --delete-conflicting-outputs` →
exit 0; `flutter analyze` → exit 0.

### Step 5: Backup coverage

In `lib/data/backup.dart`:

- **Write**: add `'importBatches'` and `'partyRules'` sections next to
  `'investments'`. Add `importBatchId` to the emitted transaction and
  savings-contribution rows.
- **Read**: leniently, exactly like `categoryBudgets` at `backup.dart:211-215`
  — a pre-v13 backup has neither section and restores as "none". Read
  `importBatchId` as nullable and absent-tolerant. Do **not** add either to the
  required-keys list at `backup.dart:196-205`, and do **not** change
  `backupFormatVersion`.
- **Wipe order**: delete `partyRules` first, then `importBatches`, both
  **before** transactions/contributions/categories/goals.
- **Insert order**: `importBatches` before transactions and contributions (they
  reference it); `partyRules` after categories, savingsGoals **and**
  importBatches (it references all three).

**Verify**: `flutter analyze` → exit 0.

### Step 6: Tests

`test/party_key_test.dart`:
- `partyKey('  RED   BOX ')` == `partyKey('red box')`
- `partyMatches('ali bin ab', 'ali bin abi taleb')` → true
- `partyMatches('stc', 'stc pay')` → false (shorter than `minPrefix`)
- `partyMatches('amazon sa', 'apple')` → false

`test/party_rules_test.dart` (use `AppDatabase.forTesting` with an in-memory
executor; follow `test/migration_v4_to_v6_test.dart` for the setup style):
- `remember` then `lookup` round-trips each of the four dispositions.
- `remember` twice on the same party updates rather than duplicating
  (assert exactly one row) and does **not** overwrite `createdByBatchId`.
- `lookup('Ali bin Ab')` finds a rule stored as `Ali bin Abi Taleb`.
- An exact match is preferred over a prefix match when both exist.
- Deleting a category cascades away an `expense` rule pointing at it; deleting
  a goal cascades away a `savings` rule.
- `remember` rejects the invalid combinations from Step 4.

`test/import_batch_test.dart`:
- `undo` deletes exactly the transactions and contributions carrying that
  `importBatchId`, and **nothing else** — assert that a hand-added transaction
  on the same day with the same amount survives.
- `undo` deletes rules the batch created and **keeps** rules it re-used
  (create a rule under batch 1, re-use it in batch 2, undo batch 2, assert the
  rule is still there).
- Rows imported by an *older* batch are untouched when the latest is undone.
- `countsFor` matches what `undo` actually removes.

Backup test (extend the existing round-trip test):
- A database with batches, rules and tagged rows round-trips intact, and the
  restored rows still cascade on undo.
- **A backup JSON with neither new section restores successfully** — the
  regression guard for old backup files.

**Verify**: `flutter test test/party_key_test.dart test/party_rules_test.dart test/import_batch_test.dart`
→ all pass.

### Step 7: Migration test

Extend the migration test (or add a sibling) to drive **v12 → v13** against a
real database file: build a v12-schema DB with categories, transactions and
contributions, upgrade, then assert:

1. `import_batches` and `party_rules` exist and are empty.
2. Pre-existing transactions and contributions are unchanged, with a null
   `import_batch_id`.
3. **The cascade fires on the migrated database**: insert a batch, tag a new
   transaction and a new contribution with it, delete the batch, and assert
   both rows are gone. This is the check the SQLite caveat in Step 4 calls for
   — do not skip it because the fresh-install test already passed.

**Verify**: `flutter test` → all pass.

### Step 8: Full suite

**Verify**:
`dart format --output=none --set-exit-if-changed lib test integration_test test_driver && flutter analyze && flutter test`
→ all exit 0.

## Test plan

Covered by Steps 6 and 7. The three assertions that matter most:

1. **A pre-v13 backup file still restores.** Getting this wrong silently
   breaks every backup the maintainer already has.
2. **v12 → v13 leaves existing data untouched**, and the cascade works on the
   migrated schema. This is a live database with real financial history and a
   new delete path running through it.
3. **Undo removes only what its batch wrote.** A cascade that reaches one row
   too far deletes real money.

## Done criteria

- [ ] `schemaVersion == 13`; the `from < 13` block creates two tables and adds
      two nullable columns
- [ ] `PartyRules`, `ImportBatches` registered; both DAOs present
- [ ] `undo` is implemented as a single batch-row delete relying on CASCADE,
      inside a transaction
- [ ] `lib/domain/party_key.dart` is pure and tested
- [ ] Backup writes and leniently reads both sections and the new columns;
      `backupFormatVersion` is still `1`
- [ ] Old-backup-restores-fine test present and passing
- [ ] v12→v13 migration test present, **including the migrated-cascade check**
- [ ] `flutter test` green
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- `schemaVersion` is not 12 when you start (someone else migrated first).
- The migrated-database cascade check in Step 7 fails. Do **not** work around
  it by hand-deleting child rows — report it, because it means the fresh and
  upgraded schemas disagree and that affects more than this feature.
- Any existing backup or migration test fails after Step 5.
- You conclude `backupFormatVersion` needs bumping. It does not — the lenient
  read exists for exactly this case; report instead of bumping.

## Maintenance notes

- `PartyDisposition` is stored by index. **Append only.**
- `ignore` is the disposition that protects the ledger from double counting.
  If a future change makes ignored rows visible somewhere, make sure they stay
  out of every spending total.
- **Two different FK philosophies now live in `Transactions`.** `recurrenceId`
  is SET NULL (generated rows are real money and outlive their rule);
  `importBatchId` is CASCADE (an import is one user action and undo means it
  never happened). Neither is a mistake; do not unify them.
- Undoing a batch forgets the party rules that batch first taught. That is
  deliberate, so "undo, fix, re-import" corrects a miscategorization instead of
  repeating it.
- A rule-management screen (view / rename / re-assign / delete saved parties)
  is the natural follow-up once 022 lands and the table has real content.
