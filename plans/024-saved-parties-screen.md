# Plan 024: A screen to view, fix and forget saved parties

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> **No schema change.** `PartyRules` (plan 021) already holds everything.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: — (021/022 are DONE)
- **Category**: feature (batch 5)
- **Planned at**: commit `f54f113`, 2026-11-05

## Why this matters

The import learns rules — "RED BOX → مطاعم", "**7772 → ادخار: السيارة",
"إضافة اموال → تجاهل" — but the only place a rule is visible is inside the
review screen, on a row that happens to match it. A wrong rule learned once is
silently re-applied on every future import, and there is no way to see it, fix
it, or remove it. `PartyRuleDao` already has `watchAll` and `deleteById`; only
the screen and an update method are missing.

## Design

### DAO — `PartyRuleDao.updateRule` (in `lib/data/database.dart`)

```dart
Future<void> updateRule(int id, {
  required String? displayName,
  required PartyDisposition disposition,
  int? categoryId,
  int? goalId,
});
```

- Enforce **the same invariants `remember` asserts** (category set iff
  expense/income, goal set iff savings, neither for ignore). Factor the check
  into one private function both methods call — two copies of an invariant is
  how they drift.
- **Set `createdByBatchId` to null.** A rule the user curated by hand must
  survive undoing the import that first taught it. Without this, "undo last
  import" would delete a rule the user had just fixed on this screen (the
  CASCADE in plan 021 was designed for *unreviewed* rules).
- An empty or whitespace `displayName` is stored as null.

### Screen — `lib/ui/party_rules_screen.dart` (new)

- Reached from the import screen (`import_screen.dart`) — the import is
  Settings-only, so this lives with it: a tile «الجهات المحفوظة (N)» under the
  past-imports list.
- One row per rule: title = `displayName ?? rawParty`; subtitle = `rawParty`
  when a display name exists; a trailing chip for the disposition and, for
  expense/income/savings, the category or goal name.
- A search field at the top once there are more than ~10 rules (plain
  substring on displayName/rawParty is enough here).
- Tap → edit sheet: display name, disposition (segmented), category picker
  filtered to the matching `TxnType`, or goal picker. Footer text:
  «التعديل يُطبَّق على الاستيرادات القادمة فقط، ولا يغيّر العمليات المسجّلة سابقًا.»
  — editing a rule never rewrites past transactions, and the user must know.
- Delete from the sheet, with a confirmation naming the party.
- Empty state: «لم تُحفظ أي جهة بعد. تُحفظ الجهات عند الاستيراد.»

## Steps

1. Extract the invariant check; add `updateRule`. Tests in
   `test/party_rules_test.dart`: each invariant rejects a bad combination;
   `updateRule` clears `createdByBatchId`; undoing the original batch after an
   edit leaves the rule in place (this is the important one — write it first
   and see it fail).
2. Build the screen and sheet; widget test: open, edit a rule's disposition from
   expense to ignore, see the chip change; delete a rule.
3. Wire the tile into the import screen.

## Verification

```
flutter analyze
flutter test test/party_rules_test.dart test/party_rules_screen_test.dart
flutter test
```

## STOP conditions

- The edit sheet would need to rewrite existing transactions to stay
  consistent → STOP. It must not; rules are forward-only.
