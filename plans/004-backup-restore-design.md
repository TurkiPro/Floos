# Backup & Restore — design (spike output)

Companion to plan `004-backup-restore-spike.md`. Records the decisions the POC
(`lib/data/backup.dart`, `test/backup_roundtrip_test.dart`) implements, and the
questions a full build must still answer.

## Problem

Floos is offline-first with no cloud backup by deliberate choice (running a
server would make the project the custodian of everyone's financial data). But
`lib/data/export.dart` only exports CSV *out*, and it's lossy (no goals, no
recurrence rules, no category tree). There is no way to get data *back in*. A
user who changes phones or reinstalls loses everything. A **local file** backup
+ restore closes that gap without touching the no-cloud stance — the file stays
in the user's custody.

## 1. Format

**JSON**, not CSV — CSV can't represent the five-table relational shape (the
self-referential category tree, the FK links) without inventing a bespoke
encoding. One object with a `version`, an `exportedAt` timestamp, and one array
per table containing every column of every row.

- **Dates** are stored as `millisecondsSinceEpoch` (int) for a lossless,
  timezone-free round-trip.
- **Enums** (`type`, `frequency`, `kind`) are stored as their `.index` int,
  matching how drift persists them (`intEnum`).
- Nullable columns serialize as JSON `null`.

Example (trimmed to one row per table):

```json
{
  "version": 1,
  "exportedAt": 1767225600000,
  "categories": [
    {"id": 1, "name": "طعام", "iconKey": "food", "colorValue": 4293934665,
     "type": 0, "parentId": null, "kind": 0, "archived": false, "sortOrder": 0}
  ],
  "recurrenceRules": [
    {"id": 1, "title": "راتب", "amount": 17000.0, "categoryId": 9, "type": 1,
     "frequency": 2, "interval": 1, "startDate": 1767225600000,
     "endDate": null, "lastMaterialized": 1767225600000, "active": true, "note": "راتب"}
  ],
  "transactions": [
    {"id": 1, "amount": 40.0, "categoryId": 1, "type": 0, "date": 1769904000000,
     "note": null, "recurrenceId": null, "createdAt": 1769904000000}
  ],
  "savingsGoals": [
    {"id": 1, "name": "سيارة", "targetAmount": 50000.0,
     "targetDate": 1798761600000, "archived": false, "createdAt": 1767225600000}
  ],
  "savingsContributions": [
    {"id": 1, "goalId": 1, "amount": 2000.0, "date": 1770076800000, "note": "إيداع", "external": false}
  ],
  "categoryBudgets": [
    {"id": 1, "categoryId": 1, "amount": 2500.0}
  ]
}
```

**Schema drift since the spike:** the format now also carries
`categoryBudgets` (schema v6) and the `external` flag on contributions (v7).
Both are read leniently on restore — a pre-v6 file with no `categoryBudgets`
section restores with zero budgets, and a pre-v7 contribution without
`external` defaults to `false` — so older spike files still restore. Standing
rule: every schema migration that adds a table or column must update
`lib/data/backup.dart` and `test/backup_roundtrip_test.dart` in the same change.

## 2. Restore semantics — **Replace** (chosen)

Options weighed:

- **Replace** (chosen): wipe all tables, import the file wholesale. Simplest,
  deterministic, and it's what "restore a backup" means — "make this device look
  like the backup". Cost: it destroys whatever is currently on the device, so
  the UI (out of scope for the spike) **must** put it behind an explicit,
  clearly-worded confirmation.
- **Merge**: insert alongside existing rows. Avoids data loss but produces
  duplicate categories/goals and primary-key collisions, needing identity/dedup
  rules the app has no basis for. Rejected — it's not what restore means, and the
  complexity isn't worth it for v1.

## 3. ID strategy — preserve primary keys

Under Replace, primary keys are inserted explicitly (drift allows an explicit
value for an autoincrement column). This keeps every foreign key valid with zero
remapping: `categories.parentId`, `recurrenceRules.categoryId`,
`transactions.categoryId` / `recurrenceId`, `savingsContributions.goalId` all
still resolve to the same rows.

## 4. FK-safe order

With FK enforcement ON (plan 003), insert/delete order matters.

- **Wipe** (children before parents): `transactions` → `savingsContributions` →
  `recurrenceRules` → `savingsGoals` → sub-categories (`parentId IS NOT NULL`) →
  remaining categories. Sub-categories are deleted before top-level to satisfy
  the self-reference.
- **Insert** (parents before children): categories top-level first then
  sub-categories → `recurrenceRules` → `savingsGoals` → `transactions` →
  `savingsContributions`.

The whole restore runs inside `db.transaction(...)`. (Note: SQLite's
`PRAGMA foreign_keys` is a no-op inside a transaction, so enforcement can't be
toggled mid-restore — ordering is the mechanism, not toggling.)

## 5. Validation & failure handling

- Reject: non-JSON, non-object root, a `version` other than the supported one,
  or any missing/!-list table section — via `BackupFormatException`.
- A dangling FK in the file (a transaction pointing at an absent category)
  surfaces as an insert failure inside the transaction.
- **Guarantee**: any failure rolls the whole transaction back, so a bad file
  leaves the existing database exactly as it was. Covered by the
  "malformed JSON leaves the database untouched" test.

## 6. Open questions for the full build

- **Encryption**: the file is plaintext financial data. Encrypt at rest (a
  passphrase-derived key), or rely on the user storing it somewhere private?
  Deliberately unimplemented in the spike.
- **Archived rows**: the backup includes archived categories/goals (they carry
  history). Confirm that's desired.
- **Cross-schema-version compatibility**: today `version` gates on an exact
  match. A shipped app needs a forward path — a v1 file imported into a later
  schema. Decide whether the importer migrates old files or refuses them with a
  clear message.
- **Delivery / dependencies**: ANSWERED (plan 016). Shipped with `share_plus`
  (hand the file to the OS share sheet) and `file_selector` (pick a file to
  restore), plus two Settings tiles and the Replace confirmation dialog.
- **Very large databases**: the current implementation holds the whole DB in
  memory as JSON. Fine for personal-finance volumes; revisit only if that
  assumption breaks.

## What the spike delivered

- `lib/data/backup.dart` — `buildBackupJson` / `restoreBackupJson`
  (Replace, transaction-wrapped, no UI, no deps beyond `dart:convert` + drift).
- `test/backup_roundtrip_test.dart` — export → restore into a fresh DB preserves
  all five tables and their FK links; restore replaces existing data;
  malformed input and wrong version roll back / are rejected.
