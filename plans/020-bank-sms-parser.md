# Plan 020: Parse batches of bank SMS into draft transactions (pure domain)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> **This plan adds NO UI and touches NO schema.** It creates one pure domain
> module and its tests. Plans 021 (party rules) and 022 (import UI) build on
> it. If you find yourself editing anything under `lib/ui/` or `lib/data/`,
> STOP.
>
> **Drift check (run first)**:
> `git diff --stat ba8d695..HEAD -- lib/domain/parse_amount.dart`
> If it changed, re-read it before Step 1 (this plan reuses its digit
> normalization).

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (additive; nothing imports it until 022)
- **Depends on**: none
- **Category**: feature (batch 4 — maintainer-requested, not from the audit)
- **Planned at**: commit `ba8d695`, 2026-09-21

## Why this matters

Adding transactions one at a time means bouncing between Messages and Floos to
copy an amount and cross-check a date. The maintainer's stated pain is the
cross-checking, not the typing. If a pasted blob of bank SMS yields amount +
date + merchant already filled in, the cross-check disappears and the only
remaining work is categorization (which 021 largely automates).

Of the three approaches considered, pasting text is the only one compatible
with the app's promises: reading SMS directly is impossible on iOS and a Play
policy fight on Android, and OCR of screenshots needs an Arabic model that ML
Kit does not ship — plus the usual ML Kit setup downloads models at runtime,
which would be the app's first network call. **Parsing pasted text needs no
permission, no native code, and no network**, and lands as a pure function in
`lib/domain/` exactly like `recurrence_math` and `parse_amount`.

### The two findings that shape the design

Both came out of running a prototype against 13 real messages from the
maintainer's own bank:

1. **Not every message is spending.** `إضافة اموال` (a wallet/card top-up) and
   `حوالة صادرة` (an outgoing transfer) are the user's own money moving, not
   expenses. In the 13-message sample, real spending was **560.43 SAR** but
   importing every row as an expense gives **1,295.43 SAR** — a 131%
   inflation. Worse, the top-up is *double counting*: money loaded onto a card
   is spent later and reported again by its own message. **Classification is
   the primary job of this module; extraction is the easy part.**

2. **The balance line is a trap.** Messages carry `الرصيد 7,930` next to an
   amount of `70.00`, and `بطاقة 1672*` / `حساب *1000` contain 4-digit
   numbers. A "find the first number" parser files a 7,930 SAR expense. The
   amount must be taken only from lines that are not known metadata lines.

### Two bugs the prototype hit — do not re-introduce them

Arabic keyword matching is where this module will break. Both of these were
real:

- `في` ("in", the timestamp marker) is a **prefix of** `فيزا` ("Visa", which
  carries the amount). A bare `^في` in the metadata skip-list swallowed the
  amount line of every Visa message.
- `ال?بطاقة` reads as "alef, optional lam, بطاقة" — it never matches a bare
  `بطاقة`. This one produced **no error at all**, just a silently empty card
  field on 11 of 13 rows.

Hence the `_arBoundary` lookahead in Step 1 and the group in `(?:ال)?بطاقة`.
The silent-failure mode is why the fixture corpus in Step 2 is the real
deliverable of this plan.

## Current state

- `lib/domain/parse_amount.dart` already normalizes Arabic-Indic and Persian
  digits and the Arabic separators (`normalizeAmountInput`). Reuse it for the
  extracted numeric substring — bank SMS can arrive with Arabic-Indic digits.
- No import/paste/clipboard code exists anywhere (`grep -rn "Clipboard" lib/`
  → no matches).
- Domain convention: plain top-level functions + small value classes, a doc
  comment explaining *intent*, and a dedicated `test/<name>_test.dart`.
  Closest exemplars: `lib/domain/savings_math.dart`,
  `lib/domain/parse_amount.dart`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Deps | `flutter pub get` | exit 0 |
| Format | `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` | exit 0 |
| Analyze | `flutter analyze` | exit 0 |
| Focused test | `flutter test test/bank_sms_test.dart` | all pass |
| Full tests | `flutter test` | all pass |

## Scope

**In scope**:
- `lib/domain/bank_sms.dart` (create)
- `test/bank_sms_test.dart` (create)
- `test/fixtures/bank_sms/` (create — the real-message corpus)

**Out of scope (do NOT touch)**:
- Anything under `lib/ui/` or `lib/data/` — no schema, no DAO, no sheet.
- Writing transactions. This module returns drafts and nothing else.
- Merchant→category memory (that is plan 021).
- Deduplication against the database (plan 022 owns the query; this plan
  provides only the pure fingerprint function).

## Git workflow

- Branch: `advisor/020-bank-sms-parser`
- Commit per step; imperative messages.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: The module

Create `lib/domain/bank_sms.dart`.

Public API (keep exactly this shape — 021 and 022 depend on it):

```dart
enum BankTxnKind { expense, topup, transferOut, income, refund, unknown }

class BankMessage {
  final String raw;            // original chunk, shown in the review UI
  final double? amount;
  final String? party;         // merchant (شراء) or destination (حوالة)
  final bool partyTruncated;   // bank cut the name with a trailing '*'
  final DateTime? at;
  final String? card;          // last 4 digits, when the message gives one
  final double? balance;       // running balance, captured so it is provably
                               // NOT read as the amount (see Step 3)
  final BankTxnKind kind;
  final List<String> issues;
  bool get isUsable;           // amount != null && at != null && kind known
}

/// Splits a pasted blob into messages and extracts a draft from each.
/// Never throws: anything unparseable comes back as a BankMessage with
/// [issues] populated and [raw] intact, so the UI can show it for manual
/// entry rather than dropping it silently.
List<BankMessage> parseBankSms(String raw);

/// Stable identity for duplicate detection. Computable from a parsed draft
/// AND from a stored Txn, so 022 can compare the two.
String txnFingerprint({
  required double amount,
  required DateTime date,        // day precision only — times vary by sender
  required String? party,
});
```

Implementation requirements:

- **Chunking**: messages arrive concatenated with no separator. Start a new
  chunk at any line opening with a transaction verb:
  `شراء|حوالة|إيداع|سحب|مرتجع|استرجاع|تحويل|إضافة|راتب`. Blank lines are
  stripped first (a forwarded blob may or may not have them).
- **Arabic keyword boundary**: define
  `const _arBoundary = r'(?![؀-ۿ])'` and append it to every Arabic
  keyword used in an anchored match. See "two bugs" above.
- **Amount**: scan lines in order, skipping metadata lines matching
  `^(البطاقة|بطاقة|حساب|من|لدى|إلى|في|الرصيد|رصيد)` + `_arBoundary`.
  On the first surviving line accept **either** order:
  `SAR\s*([\d,]+(?:\.\d+)?)` or `([\d,]+(?:\.\d+)?)\s*SAR`. Both orders occur
  within the same bank. Run the captured substring through
  `normalizeAmountInput` before `double.parse`.
  Note `المبلغ:` is deliberately NOT in the skip-list — on transfers it *is*
  the amount line.
- **Whitespace**: use `\s*`, never `\s+`, after Arabic keywords. One sender
  omits the space entirely (`لدىAPPLE`, `رصيد0.40`, `فيزا34.99`).
- **Party**: `^(?:من|لدى|إلى)` + `_arBoundary` + `\s*:?\s*(.+)$`. Strip a
  leading `SA\s*/\s*` country prefix; a trailing `*` means the bank truncated
  the name — strip it and set `partyTruncated` (the truncation is stable, so
  the truncated string is still a valid memory key for 021).
- **Date**: match on **any** line, not just one prefixed with `في` — one
  sender emits a bare `2026-08-16 02:29`. Try `(\d{4})-(\d{2})-(\d{2})` first,
  then `(\d{2})-(\d{2})-(\d{2})` (year-first, `26-` → 2026). Read the time
  independently via `(\d{1,2}):(\d{2})`: **do not read positionally**, because
  senders emit both `في 18:57 26-09-12` and `في 26-09-14 19:14`.
  Sanity-check the result: a date in the future or more than ~400 days old
  means a misread — keep it but add an issue so the UI can flag it.
- **Card**: `(?:ال)?بطاقة[^\d]*(\d{4})`. Some messages name only `فيزا` with
  no digits; `card` is legitimately null there.
- **Balance**: `^(?:الرصيد|رصيد)` + `_arBoundary` + `\s*:?\s*(...)`. Captured
  onto its own field, never as the amount — Step 3 asserts both, which is what
  makes "the parser didn't grab the balance" a test rather than a hope. Note
  the corpus uses `رصيد` for two different things (an account balance on 4629,
  the remaining value on a prepaid Visa), so nothing downstream should reason
  across messages with it.
- **Classification** from the opening line:
  `إضافة اموال`/`إضافة أموال` → `topup`; `حوالة`/`تحويل` → `transferOut`;
  `مرتجع`/`استرجاع` → `refund`; `راتب`/`إيداع` → `income`; `شراء` →
  `expense`; otherwise `unknown` + an issue.
- **`txnFingerprint`** must use day precision (not the timestamp) and a
  case-folded, whitespace-collapsed party, so the same purchase re-pasted from
  a differently-formatted sender still collides.

### Step 2: The fixture corpus — the real deliverable

Create `test/fixtures/bank_sms/sample_01.txt` with these 8 real messages
(mada debit + two credit cards, four distinct layouts):

```
شراء عبر نقاط بيع SAR 30
بطاقة 1672* مدى- ApplePay
من RED BOX
في 18:57 26-09-12
شراء عبر نقاط بيع SAR 60.50
بطاقة 1672* مدى- ApplePay
من SALAT ASIA*
في 19:04 26-09-12
شراء عبر نقاط بيع SAR 55
بطاقة 1672* مدى- ApplePay
من Ali bin Ab*
في 19:11 26-09-12
شراء إنترنت 36.05 SAR
بطاقة 1672* مدى
حساب *1000
من Keeta
في 22:27 26-09-13
شراء إنترنت 119.90 SAR
بطاقة 1672* مدى
حساب *1000
من AMAZON SA
في 00:33 26-09-13
شراء POS-ApplePay
بـ SAR 70.00
بطاقة ائتمانية *4629
لدى SA /KR-133
في 26-09-14 19:14
الرصيد 7,930
شراء إنترنت ApplePay
بـ 23 SAR
بطاقة ائتمانية *4838
لدى SA/STC
في 14:50 26-09-15
رصيد 19,919.35
شراء POS-ApplePay
بـ SAR 41.00
بطاقة ائتمانية *4629
لدى SA /eski kebap*
في 26-09-15 18:05
الرصيد 7,889
```

And `test/fixtures/bank_sms/sample_02.txt` with these 5 (a different sender —
full-year dates, no `في`, missing spaces, and the two non-expense kinds):

```
إضافة اموال 
 35.0 SAR
البطاقة: **1672 , ابل باي 
2026-08-16 02:29
شراء إنترنت
فيزا34.99 SAR
رصيد0.40
لدىAPPLE
2026-08-23 19:13
شراء إنترنت
فيزا89.99 SAR
رصيد0.21
لدىAPPLE
2026-09-12 18:26
إضافة اموال 
 600.0 SAR
البطاقة: **4629 , ابل باي 
2026-09-18 14:21
حوالة صادرة داخلية
المبلغ: 100.00 SAR
إلى : **7772
2026-09-18 14:33
```

Preserve the trailing/leading spaces exactly — they are part of what the
parser must tolerate. Add a `test/fixtures/bank_sms/README.md` stating that
every new SMS layout the maintainer encounters gets appended here as a new
`sample_NN.txt` **before** the parser is changed to handle it.

### Step 3: Tests

Create `test/bank_sms_test.dart` (style: `test/parse_amount_test.dart`).

Required assertions — these encode the findings, so do not weaken them:

- `sample_01.txt` yields 8 messages; `sample_02.txt` yields 5.
- Every message in both fixtures has a non-null `amount`, `at` and `kind`, and
  no `NO AMOUNT` / `NO DATE` / `UNCLASSIFIED` issue.
- Exact amounts, in chronological order after sorting by `at`:
  `35.00, 34.99, 89.99, 30.00, 60.50, 55.00, 119.90, 36.05, 70.00, 23.00,
  41.00, 600.00, 100.00`.
- **Kinds**: the two `إضافة اموال` rows are `topup`, the `حوالة` row is
  `transferOut`, the other ten are `expense`.
- **The money assertion**: sum of `expense` rows across both fixtures is
  `560.43`; sum of all rows is `1295.43`. A regression that reclassifies a
  top-up as an expense fails here loudly.
- **Balance is never the amount**: the `الرصيد 7,930` message parses as
  `70.00` with `balance == 7930.0`; likewise `41.00` / `7889.0` and
  `23.00` / `19919.35`.
- **The فيزا regression**: `فيزا34.99 SAR` parses as `34.99`, not null.
- **The بطاقة regression**: `بطاقة 1672* مدى- ApplePay` yields
  `card == '1672'` (a bare `بطاقة`, no `ال` prefix).
- **Both date/time orders**: `في 18:57 26-09-12` and `في 26-09-14 19:14` both
  yield the right day, and `2026-08-16 02:29` parses with no `في` present.
- **Year-first**: `26-09-12` and `2026-09-12` resolve to the same date
  (both appear in the corpus for 12 Sep 2026).
- **Truncation**: `SALAT ASIA*` → party `SALAT ASIA`, `partyTruncated == true`.
- **Country prefix**: `لدى SA /KR-133` → party `KR-133`.
- **Robustness**: `parseBankSms('')` → empty list; a blob of unrelated Arabic
  prose returns messages with issues rather than throwing; an OTP-style
  message classifies as `unknown` (add one to a `sample_03.txt` if the
  maintainer supplies one — otherwise assert on a hand-written line).
- **Fingerprint**: two drafts differing only in time-of-day collide; differing
  in amount or day do not.

**Verify**: `flutter test test/bank_sms_test.dart` → all pass.

### Step 4: Full suite

**Verify**:
`dart format --output=none --set-exit-if-changed lib test integration_test test_driver && flutter analyze && flutter test`
→ all exit 0.

## Test plan

Entirely covered by Step 3 — this module is pure and needs no device. The
fixtures ARE the test plan; every future bank-format change adds a fixture
first, then the code to satisfy it.

## Done criteria

- [ ] `lib/domain/bank_sms.dart` exists with exactly the API in Step 1
- [ ] Both fixture files exist with the messages verbatim, plus the fixtures
      README
- [ ] `test/bank_sms_test.dart` covers every bullet in Step 3
- [ ] The 560.43 / 1295.43 assertions are present and passing
- [ ] `flutter test` green
- [ ] `git status` shows no files outside the in-scope list
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- Any fixture message cannot be parsed cleanly and the fix would require
  guessing at the bank's intent — report the message instead.
- You are tempted to add a network call, an OCR dependency, or a platform
  channel. None are in scope and all break the app's privacy promise.
- Handling a new format would break an existing fixture assertion. That is a
  genuine ambiguity in the bank's templates; report both cases.

## Maintenance notes

- **Never add a bank format without adding its fixture first.** The `بطاقة`
  bug produced no error — only the corpus catches that class of failure.
- Arabic keywords in anchored regexes always need `_arBoundary`. `في` ⊂ `فيزا`
  is not the only such pair.
- This module deliberately knows nothing about categories, goals or the
  database. Keep it that way; disposition is 021's job.
