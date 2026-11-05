# Plan 029: Debts and IOUs — money lent and borrowed (schema v16)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: confirm plan 027 is DONE (`lib/domain/ledger_balance.dart`
> exists) and read `schemaVersion`. This plan assumes 15 → 16 (028 first); if
> 028 has not landed, use the next free version and say so.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MED-HIGH (a new ledger that moves the balance)
- **Depends on**: 027 (hard)
- **Category**: feature (batch 5)
- **Planned at**: commit `f54f113`, 2026-11-05

## Why this matters

"I lent Fahad 500" and "my brother lent me 2,000" are common and the app has
no honest way to record them. Logged as an expense, a loan to a friend inflates
spending, burns the weekly budget, and the repayment then has to be faked as
income. Logged as nothing, the balance is wrong. Either way the numbers the
maintainer relies on drift.

## Data model — a ledger, like savings

Same philosophy as savings goals: the outstanding amount is **never stored**,
it is summed from movements.

```dart
enum DebtDirection { lent, borrowed } // lent = they owe me

@DataClassName('Debt')
class Debts extends Table {
  id, person (text 1..80), direction (intEnum<DebtDirection>),
  note (nullable), archived (bool, default false), createdAt
}

@DataClassName('DebtMovement')
class DebtMovements extends Table {
  id,
  debtId -> Debts ON DELETE CASCADE,
  // > 0 grows what is owed (the loan itself, or lending more);
  // < 0 is a repayment.
  amount (real), date, note (nullable),
  // Outside the tracked balance — e.g. a loan made before using Floos, or
  // repaid in cash that was never in the account. Same meaning as everywhere.
  external (bool, default false),
}
```

Outstanding = Σ amount. Settled when outstanding ≤ 0.005 (offer to archive).

## How it touches the money (the whole point — get this right)

Balance effect of a non-external movement:
`lent → −amount` (money left me; a repayment, being negative, brings it back),
`borrowed → +amount`.

- Add `debtMovements` + their debts' directions to `LedgerInputs` (plan 027),
  **as a required field**, so every caller is flagged by the compiler.
- **Not spending, not income.** Lending is excluded from spent-this-week,
  category totals, essentials/luxuries, the savings rate, and statistics.
  Borrowing is excluded from income and from `periodIncome` (it must not
  trigger the "salary landed" logic or the savings prompt).
- It does change the balance, and therefore the balance caps (المتبقي's clamp
  in `DashboardSummary`, the weekly headroom in `weeklyBudgetStatus`). That
  follows automatically from going through `ledgerBalance`.

### Borrowed money does not count as yours to spend (decided 2026-11-05)

Borrowed money really is in the account, so it raises the balance. It does
**not** raise المتبقي or the weekly budget's cap — the maintainer chose this.
Introduce `spendableBalance = balance − outstanding borrowed (non-external)`
and use it for those two caps only. The balance card still shows the real
balance; it simply stops telling you a loan is yours to spend. Lent money needs
no such rule (it already left the balance).

Put the subtraction inside `ledger_balance.dart` as a second function
(`spendableBalance`) so it too exists once.

## UI

- Settings list: «الديون والسلف» → `DebtsScreen`: two sections, «لي عند
  الآخرين» (lent) and «عليّ» (borrowed), each person with outstanding amount;
  totals per section; settled ones collapsed.
- Add sheet: person, direction, amount, date, note, «خارج الرصيد» toggle
  (worded per direction, like the savings sheet).
- Debt detail: movements ledger; «تسجيل سداد» (repayment) and «إضافة مبلغ».
  Swipe-to-delete with undo on movements (reuse `swipe_to_delete.dart`).
- Home: no new card. The balance card's existing breakdown, if it lists savings
  and investments, gets a «ديون» line only when any are outstanding.

## Backup, export, reset

- Backup writes both tables; reader is lenient (missing sections → empty).
  `backupFormatVersion` stays 1.
- "Clear all data" clears both tables.
- CSV export: a debts section; amounts pass through the existing formula-
  injection escaping (`_csvField`).

## Steps

1. Schema, enums, migration (+ test from the previous version), DAO
   (`DebtDao`: watchAll with outstanding, add debt with its first movement in
   one transaction, add movement, delete movement, archive, restore for undo).
2. `ledger_balance.dart`: debt effect + `spendableBalance`; tests.
3. Parity: extend `test/weekly_budget_parity_test.dart` with a fixture holding
   a lent and a borrowed debt — home, stats and weekly-performance must agree,
   and lending 500 this week must not count as spent this week.
4. A test that borrowing does not change `periodIncome`,
   `incomeReceivedThisMonth`, or the savings rate.
5. Backup round-trip test; clear-all test.
6. UI + widget test for add → repay → settled.

## Verification

```
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```

## STOP conditions

- Any screen's figure moves when a debt is added and you cannot point to
  `ledgerBalance`/`spendableBalance` as the reason → STOP; something is
  re-deriving the balance on its own.
