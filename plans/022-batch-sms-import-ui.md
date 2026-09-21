# Plan 022: A bank-message import page in Settings — paste, review, commit, undo

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat ba8d695..HEAD -- lib/ui/settings_screen.dart`
> Re-locate the insertion point by grep if it changed.
>
> **Hard prerequisite**: 020 and 021 must both be DONE and on main. This plan
> writes no parser and no schema; if you need either, you are in the wrong plan.

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: MED-HIGH (this is the first code path other than the recurrence
  engine that writes transactions in bulk)
- **Depends on**: 020 (parser), 021 (party rules + import batches)
- **Category**: feature (batch 4)
- **Planned at**: commit `ba8d695`, 2026-09-21

## Why this matters

020 extracts amount + date + merchant; 021 remembers what each merchant means
and makes a batch undoable. This plan is the part the user actually touches:
open a page, paste, look at a list, confirm — and take the whole thing back if
it went wrong.

Nothing is written to the database until the user confirms, and everything that
is written can be removed in one action afterwards. Neither is a nicety: both
are the safety margin for a parser reading templates the bank can change
without warning.

## Current state

- Settings has a data section with backup / restore / CSV / PDF tiles
  (`settings_screen.dart`) — this is where the import page hangs.
- `refreshAlerts(db, settings)` must be called after any mutation that changes
  spending (plan 015); the add sheet does this at
  `add_transaction_sheet.dart:147`.
- **Salary cycle is the only period unit in this app.** `financial_period.dart`
  defines the window; nothing groups or labels by calendar month. A single
  paste routinely straddles a payday (the 020 fixtures span 16 Aug – 18 Sep).
- Restore already sets the precedent for a destructive action behind an
  explicit confirmation (`README.md`, "Backup & restore stay on-device").
- 021 provides `ImportBatchDao.create/latest/watchRecent/undo/countsFor` and
  `PartyRuleDao.lookup/remember`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Deps | `flutter pub get` | exit 0 |
| Codegen | `dart run build_runner build --delete-conflicting-outputs` | exit 0 |
| Format | `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` | exit 0 |
| Analyze | `flutter analyze` | exit 0 |
| Focused test | `flutter test test/import_review_test.dart` | all pass |
| Full tests | `flutter test` | all pass |
| Run | `flutter run -d windows` | app launches |

## Scope

**In scope**:
- `lib/domain/import_review.dart` (create) — pure duplicate/collision detection
- `test/import_review_test.dart` (create)
- `lib/ui/import_screen.dart` (create) — the Settings-accessible page: paste
  box + past-imports list + undo
- `lib/ui/import_review_screen.dart` (create) — the review list, pushed from
  the page above
- `lib/data/database.dart` — one bulk-commit method; no schema change
- `lib/ui/settings_screen.dart` — one tile in the data section

**Out of scope (do NOT touch)**:
- The parser (020) and the schema (021).
- **A balance-gap / missing-message detector.** Considered and dropped: the
  samples show `رصيد` meaning two different things (an account balance vs. the
  remaining value on a prepaid card), and the Visa messages carry no card
  number to scope it by. It cannot be grounded well enough to be worth a
  warning the user has to judge.
- A second entry point from the add-transaction sheet or the home screen. The
  import is a deliberate, occasional action and lives in Settings only.
- A share-sheet / share-extension entry point. Noted as a follow-up; it needs
  native extension code and `receive_sharing_intent`, and the clipboard path
  must prove itself first.
- Undo for anything but the most recent batch (see Step 6 for why).
- A rule-management screen (follow-up to 021).
- Editing `recurrence_engine.dart` in any way.

## Git workflow

- Branch: `advisor/022-batch-sms-import-ui`
- Commit per step; imperative messages.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Pure review logic

Create `lib/domain/import_review.dart`. No database imports — it takes plain
lists so it can be tested without a device.

```dart
enum DraftStatus {
  fresh,              // not seen before
  duplicateOfLedger,  // fingerprint already exists in the database
  duplicateInPaste,   // the same message appears twice in this paste
  recurrenceCollision // an active recurrence rule already generates this
}

class ReviewedDraft {
  final BankMessage message;
  final DraftStatus status;
  final PartyRule? rule;   // the remembered decision, if any
}

/// Classifies each parsed draft against what the app already knows.
/// Sorted by [BankMessage.at] — paste order is NOT chronological.
List<ReviewedDraft> reviewDrafts({
  required List<BankMessage> drafts,
  required Set<String> ledgerFingerprints,
  required List<RecurrenceCandidate> activeRules,
  required PartyRule? Function(String party) lookupRule,
});
```

Notes for the implementer:

- `duplicateOfLedger` uses `txnFingerprint` from 020 on both sides — day
  precision, normalized party.
- **`recurrenceCollision` is the important one.** `README.md` states the
  recurrence engine is the sole writer of generated transactions. This import
  becomes a second writer, so a subscription that has a rule AND arrives as an
  SMS would be booked twice. Flag a draft when an active rule has the same
  amount and its occurrence falls within ±3 days of the draft's date.
- Everything except `fresh` defaults to **unchecked** in the UI.

### Step 2: Tests for Step 1

Create `test/import_review_test.dart`, driven off the 020 fixtures:

- All 13 fixture drafts against an empty ledger → all `fresh`.
- Re-running with the first paste's fingerprints in `ledgerFingerprints` → the
  8 sample_01 rows come back `duplicateOfLedger`. **This is the
  overlapping-paste case and it will happen every time the maintainer imports.**
- The same message twice in one blob → the second is `duplicateInPaste`.
- An active rule for 89.99 dated 2026-09-12 makes the APPLE draft
  `recurrenceCollision`; the same rule at 2026-08-01 does not.
- A remembered rule is attached to its draft; an unknown party gets
  `rule == null`.
- Output is sorted by `at`, **not** input order (assert using the fixture pair,
  where 22:27 precedes 00:33 in the file but not in time).

**Verify**: `flutter test test/import_review_test.dart` → all pass.

### Step 3: The bulk commit

Add one method that writes a confirmed batch **inside a single transaction**,
so a failure part-way leaves the ledger untouched:

```dart
Future<int> commitImport(List<ResolvedDraft> rows);   // returns the batch id
```

Where each `ResolvedDraft` carries the draft plus the user's resolution:
disposition, category or goal, and optional display name.

Order inside the transaction:

1. `ImportBatchDao.create(...)` first — it is the FK target for everything else.
2. Route each row by disposition (from 021):
   - `expense` / `income` → `transactions`, tagged with the batch id, with the
     display name (or the bank's party string) as the **note**, so the row is
     recognisable in history the way a rule-generated row carries its rule
     title.
   - `savings` → a `SavingsContributions` row against the chosen goal, tagged
     with the batch id.
   - `ignore` → **write nothing.** This is what keeps card top-ups from
     double-counting the purchases that follow. Count them into the batch's
     `ignoredCount` so the history row can say what was skipped.
3. `remember(...)` each resolved party, passing `createdByBatchId` only when
   the rule did not already exist.

**`recurrenceId` stays null** on every imported row. These are not
rule-generated, and claiming otherwise would let a catch-up interact with them.

After the transaction commits, call `refreshAlerts(db, settings)` once (not per
row) — plan 015's rule.

### Step 4: The import page (Settings destination)

Create `lib/ui/import_screen.dart`, Arabic-first and RTL like the rest of the
app. This is the page the Settings tile opens, and it has two parts.

**Top — paste:**

- A multiline `TextField` plus a "لصق من الحافظة" button
  (`Clipboard.getData(Clipboard.kTextPlain)`). No permission, no plugin.
- Live count as they type/paste: "N عملية" from `parseBankSms`.
- Empty state explains where the text comes from. On iOS, Messages
  multi-select offers **Forward**, not Copy — the working path is select →
  Forward → select-all in the compose box → copy. Say so plainly; it is not
  obvious.
- A "متابعة" button → pushes the review screen (Step 5).

**Bottom — past imports:**

- `ImportBatchDao.watchRecent()` in a list: date, row count, total, and the
  ignored count when non-zero.
- Covered by Step 6.

### Step 5: The review screen

Create `lib/ui/import_review_screen.dart`: a list of `ReviewedDraft`s with a
per-row checkbox.

Each row shows: amount, date, the party's **display name if a rule exists**
(otherwise the raw party), and its resolution as a tappable chip.

- Rows with a rule are pre-resolved and checked. **This is the payoff** — after
  a few imports most rows arrive done.
- Rows without a rule need one tap: a sheet offering the four dispositions,
  reusing `CategoryPicker` for expense/income and a goal picker for savings,
  plus an optional "اسم مختصر" field (so `KR-133` and `**7772` become readable
  once, forever).
- `duplicateOfLedger` / `duplicateInPaste` / `recurrenceCollision` rows render
  dimmed, unchecked, with a one-line reason. **Never drop them silently** — a
  silent drop is the one failure mode that would make the maintainer distrust
  the feature.
- Drafts with parse issues render with their `raw` text visible and manual
  amount/date fields.
- **Group by salary cycle**, using `financial_period.dart` — never by calendar
  month. Label a group that straddles a payday as a range. A single paste
  routinely spans two cycles.
- A pinned footer shows the count and **total of checked rows only**, then
  "حفظ N عملية". On save: `commitImport`, pop back to the import page, and show
  a confirmation naming the batch.

### Step 6: Undo the last import

In the "past imports" list on `import_screen.dart`:

- **Only the most recent batch gets a "تراجع" action.** Older batches are
  shown read-only. This is deliberate: imported rows can be edited or deleted
  afterwards through the normal UI, so undoing an older batch would remove rows
  the user may have since changed, while the newest batch is almost always
  still exactly as it was written. Do not add undo to older rows without
  raising it first.
- Tapping it opens an explicit confirmation dialog (the pattern restore
  already uses) stating, from `ImportBatchDao.countsFor`:
  - how many transactions and contributions will be deleted, and their total;
  - that party rules **first learned by that import** will be forgotten, so the
    next import will ask about those merchants again.
- On confirm: `ImportBatchDao.undo(batchId)`, then `refreshAlerts` once. The
  batch disappears from the list.
- Undo is a single batch-row delete relying on the CASCADE from 021. **Do not
  hand-delete the child rows here** — if you find yourself writing per-table
  deletes in the UI layer, the schema is wrong and you should STOP.

### Step 7: The Settings tile

In `settings_screen.dart`, add one tile to the data section (beside
backup/export), labelled "استيراد من رسائل البنك", pushing `ImportScreen`.
This is the only entry point.

**Verify**: `flutter run -d windows`, paste both fixture blobs, confirm the
counts, totals and groupings match the 020 fixture expectations (560.43 SAR of
expenses; the top-ups and the transfer NOT counted as spending).

### Step 8: Full suite

**Verify**:
`dart format --output=none --set-exit-if-changed lib test integration_test test_driver && flutter analyze && flutter test`
→ all exit 0.

## Test plan

- Steps 1–2 cover the logic without a device.
- 021's `import_batch_test.dart` covers undo at the data layer.
- Manual on-device pass (the parts a unit test cannot reach):
  1. Settings → import page → paste sample_01 → 8 rows, all fresh, total 435.45.
  2. Save all → history shows 8 rows with readable notes; the import page lists
     one batch.
  3. **Paste sample_01 again → all 8 come back dimmed as duplicates and the
     checked total is 0.** The single most important manual check.
  4. Paste sample_02 → the two `إضافة اموال` rows and the `حوالة` row are
     *not* expenses; resolve `**7772` as savings and confirm the deposit lands
     in the savings ledger, not in spending.
  5. Resolve `KR-133` with a display name; re-import and confirm the name and
     category are pre-filled.
  6. **Undo the latest batch** → its rows disappear from history, the balance
     and weekly badge return to their pre-import values, and the older batch is
     untouched.
  7. Re-import the undone batch → the merchants it had first taught ask again;
     merchants taught by the older batch do not.
  8. Confirm the weekly badge / alerts update once after a commit and once
     after an undo.

## Done criteria

- [ ] `lib/domain/import_review.dart` is pure and fully tested
- [ ] Nothing writes to the database before the user confirms
- [ ] `commitImport` runs in one transaction; `ignore` rows write nothing but
      are counted
- [ ] Imported rows carry `importBatchId` and have `recurrenceId == null`
- [ ] Duplicates and recurrence collisions are shown-but-unchecked, never dropped
- [ ] Review groups by salary cycle, sorts by parsed timestamp
- [ ] Undo is offered for the latest batch only, behind an explicit
      confirmation that states the counts and the forgotten-rules consequence
- [ ] Undo is one batch-row delete via CASCADE; no per-table deletes in the UI
- [ ] `refreshAlerts` called once per commit and once per undo
- [ ] Settings tile is the only entry point
- [ ] No balance-gap detector anywhere in the diff
- [ ] Manual test plan steps 1–8 pass on a real device
- [ ] `flutter test` green
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- A design change would require writing rows before confirmation.
- The recurrence-collision check cannot be implemented from the data available
  — report rather than shipping without it; double-booked subscriptions are
  silent and compounding.
- Undo needs per-table deletes in the UI layer. That means 021's cascade is not
  working and the fix belongs there, not here.
- You find yourself modifying `recurrence_engine.dart`. Out of scope.
- Re-pasting the same blob produces any checked row.

## Maintenance notes

- **Two writers now touch the ledger.** The recurrence engine and this import.
  The collision check in Step 1 is the only thing keeping them from
  double-booking; any change to either side needs a test covering the overlap.
- `ignore` rows existing-but-unwritten is the design, not an oversight. Card
  top-ups and own-account transfers must never reach a spending total.
- Undo is latest-batch-only by choice, not by limitation. If older-batch undo
  is ever wanted, first decide what should happen to imported rows the user has
  since edited.
- Follow-ups, in rough order of value: a rule-management screen (021), an iOS
  share-sheet target so Forward → Floos skips the clipboard, and appending each
  newly-encountered bank format to the 020 fixture corpus.
