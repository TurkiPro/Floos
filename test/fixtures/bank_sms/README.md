# Bank SMS fixtures

Real bank notification messages, pasted verbatim. These drive
`test/bank_sms_test.dart`, and they are the point of that test — the parser is
easy to change and very hard to change *safely*, because Arabic keyword
matching fails silently.

Two bugs from the first prototype, both found only by running against real
messages:

- `في` ("in") is a prefix of `فيزا` ("Visa"). A bare `^في` in the metadata
  skip-list ate the amount line of every Visa message.
- `ال?بطاقة` reads as "alef, optional lam, بطاقة" and never matches a bare
  `بطاقة`. That one raised **no error at all** — it just left the card field
  empty on 11 of 13 rows.

## The rule

**When a new message layout shows up, add it here first, then change the
parser to satisfy it.** Never the other way round.

Add it as the next `sample_NN.txt` and extend `bank_sms_test.dart` with its
expected fields. Keep the message exactly as received — including trailing
spaces, missing spaces after Arabic keywords, and whatever ordering the sender
used. Those quirks are the test.

Do not edit an existing fixture to make a change pass. If a new format
genuinely conflicts with an old one, that is a real ambiguity in the bank's
templates and needs a decision, not a quiet edit.

## What each file covers

| File | Messages | What it pins down |
|------|----------|-------------------|
| `sample_01.txt` | 8 | mada debit + two credit cards. Currency before *and* after the amount; date before *and* after the time; two-digit year-first dates; `من` vs `لدى`; the `SA /` country prefix; names truncated with `*`; and balance lines sitting next to amounts. |
| `sample_02.txt` | 5 | A second sender. Full `YYYY-MM-DD` dates with no `في` marker; no space after Arabic keywords (`لدىAPPLE`, `رصيد0.40`, `فيزا34.99`); the `المبلغ:` amount marker; and the two non-expense kinds — `إضافة اموال` (top-up) and `حوالة صادرة` (transfer). |

## The assertion that matters most

Across both files: expenses total **560.43 SAR**, every row totals
**1,295.43 SAR**. The gap is two card top-ups and one transfer, which are the
user's own money moving. Booking them as spending inflates the period by 131%
and double counts, because money loaded onto a card is spent later and reported
again by its own message.

If a change makes that assertion fail, the classification broke — not the
arithmetic.
