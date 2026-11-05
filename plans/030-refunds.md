# Plan 030: Refunds as their own thing, linked to the purchase (schema: next free)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: read `schemaVersion`. Expected order is 028 (v15)
> → 029 (v16) → this (v17). Use the next free version and say which.

## Status

- **Priority**: P1 (fixes a live import bug as well as adding the feature)
- **Effort**: M–L
- **Risk**: MED-HIGH (introduces negative expense amounts; every place that
  reads `txn.amount` must be checked)
- **Depends on**: — (independent of 027/029; land after 028 if both are in
  flight, since both touch the import's fingerprints)
- **Category**: feature + bug fix (batch 5)
- **Planned at**: commit `f54f113`, 2026-11-05

## Why this matters

A refund today has no right answer:

- Logged as **income**, it inflates income and the savings rate, and the
  category it came back to still shows the full purchase.
- Logged as a reduced/edited purchase, the history lies about what happened
  and when the money moved.
- Not logged, the balance is wrong.

**And the import gets it actively wrong (live bug).** The parser already
classifies `مرتجع`/`استرجاع` messages as `BankTxnKind.refund`
(`lib/domain/bank_sms.dart:303`), but nothing downstream reads `kind` —
`import_review.dart` and `import_review_screen.dart` decide only from the
party's saved rule. So a refund from a merchant the user has a rule for
("RED BOX → مطاعم") is imported as **a second purchase**: the money that came
back is counted as spent twice over. Without a rule, the user can only pick
expense or income, and both are wrong.

## Design decision: a refund is a negative expense

A refund is stored as an **expense row with a negative amount**, in the same
category as the purchase, dated the day the money came back:

```dart
// tables.dart, Transactions
// Non-null => this row is a refund of that purchase. Refund rows are expense
// rows with a NEGATIVE amount, so every existing sum (category totals, weekly
// spend, budgets, balance) nets them out with no special case. SET NULL: if
// the purchase is deleted, the refund is still real money that came back.
IntColumn get refundOf => integer()
    .nullable()
    .references(Transactions, #id, onDelete: KeyAction.setNull)();
```

Why negative rows rather than a new `TxnType.refund` or an `isRefund` flag
with a positive amount: the app has dozens of `if (type == income) … else …`
sums. A new type would silently fall into the `else` and be counted as
spending; a flag would need every sum to learn a sign rule. A negative expense
is already correct in every sum — the risk moves to the few places that assume
an expense is positive, which the audit below finds.

**Which cycle it reduces — the refund's own date.** The money came back today,
so today's cycle and this week get the headroom back. Reaching back into the
purchase's cycle would rewrite finished cycles and the frozen weekly budget.

Invariant (checked in the DAO): `amount < 0` ⇔ `type == expense` and it is a
refund (linked or standalone). Income is never negative. A refund linked to a
purchase cannot exceed what is still unrefunded on it.

## The audit (the real work — do it before writing UI)

Grep every read of `.amount` on a `Txn` in `lib/domain/` and `lib/ui/`, and
classify each in a table in your report: **sum** (fine as is), **count**,
**max/min/median**, **display**, **validation**. Known places to decide:

- **Counts** — `category_breakdown.dart:17` (`count => transactions.length`):
  a refund is not a purchase; exclude refund rows from counts.
- **Medians / "typical"** — `budget_advisor.dart`, `category_insights.dart`:
  these run on per-cycle *sums*, so a refund correctly lowers that cycle;
  confirm no per-transaction median exists.
- **`<= 0` guards** — `budget_risk.dart:64` (`if (spent <= 0) continue`): a
  category whose refunds exceed its purchases this cycle has negative spend.
  Clamp displayed spend at 0 per category, but never clamp the balance.
- **Committed vs discretionary** — a refund has no `recurrenceId`; if it
  refunds a recurrence-generated row (`refundOf` → row with `recurrenceId`),
  classify it as committed so it nets against the same bucket.
- **Display** — `transaction_row.dart`: a refund shows as «استرداد» with a
  return icon and `+amount` in the income colour, never as `-(-50)`.
- **Validation** — amount inputs stay positive; the sheet negates on save.
- CSV export: write type `refund` (not `expense`) and a `refund_of` column.

## Manual entry

- On an expense's edit sheet: «تسجيل استرداد». Amount defaults to what is still
  unrefunded (full or partial allowed), date defaults to today; category and
  note are inherited and locked.
- In the add-expense sheet: a toggle «استرداد» for a refund whose purchase
  predates the app or was never logged (standalone, `refundOf` null).
- The purchase row shows a chip: «مسترد بالكامل» or «مسترد جزئيًا 50».

## Import

- `kind == refund` never takes the party rule's disposition as-is:
  - rule says expense (or no rule): a refund in the rule's category, or ask for
    a category;
  - rule says ignore: ignore;
  - rule says income/savings: ask (show the row as needing a decision).
- Auto-link: the most recent purchase from the same party (`partyMatches`)
  within 90 days with enough unrefunded amount → `refundOf`. Show the match on
  the row so the user can unlink it.
- **Fingerprints include the sign.** A purchase and its same-day refund for the
  same amount and party must not flag each other as `duplicateInPaste` /
  `duplicateOfLedger` — which they would today.
- The recurrence-collision check applies to purchases only.

## Backup

Write `refundOf`; read it leniently. Restore keeps row ids (backup.dart inserts
with `id: Value(...)`), so links stay valid; insert purchases before refunds or
defer FK checks during restore, whichever the existing restore already does
for `recurrenceId`.

## Steps

1. The audit table (report it before continuing).
2. Schema + migration (+ test) + backup round-trip.
3. DAO: `addRefund(purchaseId, amount, date)`, `addStandaloneRefund(...)`;
   invariant tests (over-refund rejected, positive refund rejected, income
   refund rejected); deleting the purchase leaves the refund with
   `refundOf == null`.
4. Domain fixes from the audit, each with a test: category count excludes
   refunds; a refund this week lowers spent-this-week and raises remaining;
   a refund of a generated row is committed; per-category display clamps at 0
   but the balance does not.
5. Parity: extend `test/weekly_budget_parity_test.dart` with a refund in the
   fixture — home, stats and weekly-performance agree.
6. Import: the live bug first — a test where a party has an expense rule and a
   refund message for it imports as a refund (negative), not a purchase; then
   auto-link and the sign-aware fingerprint tests.
7. UI + widget tests.

## Verification

```
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```

## STOP conditions

- Any screen shows a negative *spent* figure to the user → STOP and decide the
  clamp with the maintainer; do not hide it by changing the stored amount.
- A sum somewhere treats `type == expense` rows as positive by taking `abs()` →
  STOP and report; it would turn every refund into spending.
