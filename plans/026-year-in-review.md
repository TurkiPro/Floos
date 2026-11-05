# Plan 026: A year in review, by salary cycle

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.

## Status

- **Priority**: P3
- **Effort**: M
- **Risk**: LOW (read-only), but it is one more surface that states income /
  spent / saved — see "the consistency rule" below
- **Depends on**: —
- **Category**: feature (batch 5)
- **Planned at**: commit `f54f113`, 2026-11-05

## Why this matters

`MonthsScreen` lets you open one cycle at a time. Nothing lets you see the
cycles *next to each other* — which one was the expensive one, whether saving
is trending up, where the year's money went.

## The consistency rule (read first)

This screen restates numbers that already appear elsewhere (each cycle's
income/spent/saved is on `MonthDetailScreen`; the current cycle's is on home).
The maintainer has had to report three separate cases of the same figure
disagreeing between screens. So:

- Per-cycle totals come from the **existing** `cycleSummaries` in
  `lib/domain/period_summary.dart`. Do not re-sum transactions.
- If a figure this screen needs is not in `CycleSummary`, add it **there** and
  make every existing caller benefit, rather than computing it locally.
- Add a parity test: for every cycle shown, the screen's income/spent figures
  equal what `MonthDetailScreen` would show for that cycle (it sums
  `watchForRange(cycle.start, cycle.end)`).

## Design

- "A year" = **the last 12 salary cycles**, including the current one (marked
  in progress). Never a calendar year. Label each cycle with the existing
  `cycleLabelFor` (month name when it lines up, a date range when it straddles).
- Sections:
  1. Totals across the 12 cycles: income, spent, saved, savings rate.
  2. A bar per cycle (spent, with saved stacked), the current cycle visibly
     partial. Use plain `CustomPaint`/`Container` bars like the existing
     statistics screen — no chart dependency.
  3. Best and worst cycle by savings rate (completed cycles only — a cycle in
     progress is not "the best" just because the salary landed yesterday).
  4. Top 5 top-level categories over the 12 cycles, with share of spending.
  5. Committed vs discretionary split over the 12 cycles, reusing whatever
     `StatisticsSummary` uses to classify (recurrence-generated = committed).
- Fewer than 12 cycles of data → show what exists, say how many.
- Entry: a tile at the top of `MonthsScreen` «ملخص آخر ١٢ دورة».

## Side finding (do not fix in this plan — report it)

The statistics CSV was moved to salary cycles on 2026-11-05 (`statsCsvFor` in
`export.dart`; `monthlySummaries` was deleted). `behavior_screen.dart` still
uses `yearlySummaries` (calendar years), against the salary-cycle rule. This
screen's 12-cycle grouping is the natural replacement — note it in the README
row so the maintainer can decide.

## Steps

1. Extend `CycleSummary` only if needed; tests in
   `test/period_summary_test.dart`.
2. Pure `yearReview(cycles, rows, categoriesById)` in
   `lib/domain/year_review.dart` returning the five sections; tests: best/worst
   ignores the current cycle; top categories roll subcategories into parents;
   fewer than 12 cycles.
3. Parity test against `MonthDetailScreen`'s sum (see above).
4. The screen.

## Verification

```
flutter analyze
flutter test test/year_review_test.dart test/period_summary_test.dart
flutter test
```

## STOP conditions

- `cycleSummaries` and `MonthDetailScreen` already disagree on some fixture →
  STOP and report that first; it is a bug, and this screen would inherit it.
