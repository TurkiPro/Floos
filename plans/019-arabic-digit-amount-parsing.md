# Plan 019: Accept Arabic-Indic digits everywhere an amount is typed

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat db51b40..HEAD -- lib/ui/add_transaction_sheet.dart lib/ui/add_income_sheet.dart lib/ui/add_contribution_sheet.dart lib/ui/add_goal_sheet.dart lib/ui/add_recurrence_sheet.dart lib/ui/home_screen.dart lib/ui/budgets_screen.dart`
> If any changed since this plan was written, re-locate the parse sites by
> grepping `tryParse` before proceeding; if a site disappeared, STOP.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `db51b40`, 2026-07-15

## Why this matters

Floos is an Arabic-first app (`locale: Locale('ar')`, RTL everywhere), yet
every amount field parses input with
`double.tryParse(text.replaceAll(',', '.'))`. `double.tryParse` only
understands Western digits — a user whose keyboard emits Eastern
Arabic-Indic digits (٠١٢٣٤٥٦٧٨٩ — the default digit shape on many Arabic
keyboard layouts and common in pasted text), the Arabic decimal separator
(٫), or Arabic thousands separator (٬) gets `null`, and the sheet shows the
generic "أدخل مبلغًا صحيحًا" error for input that is, to the user, a perfectly
valid number written in their own script. The same eight-line parse snippet
is copy-pasted across seven call sites — this plan replaces them with one
tested helper that normalizes Arabic-Indic (and Persian-variant) digits and
separators first.

## Current state

The seven parse sites (all the same pattern; grep
`grep -rn "tryParse" lib/` to confirm the set):

- `lib/ui/add_transaction_sheet.dart:36` — `double.tryParse(_amountCtrl.text.replaceAll(',', '.'))`
- `lib/ui/add_income_sheet.dart:44` — same
- `lib/ui/add_contribution_sheet.dart:44` — same
- `lib/ui/add_goal_sheet.dart:29` — same
- `lib/ui/add_recurrence_sheet.dart:98` — same, plus `:99`
  `int.tryParse(_intervalCtrl.text)` for the interval
- `lib/ui/home_screen.dart:720` — same (custom deposit dialog)
- `lib/ui/budgets_screen.dart:109` — same (budget dialog)

Repo conventions: pure logic lives in `lib/domain/` with a dedicated test
file (see `lib/domain/savings_math.dart` + `test/savings_math_test.dart` for
the smallest exemplar of the style — doc comment explaining intent, plain
top-level functions).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Deps | `flutter pub get` | exit 0 |
| Codegen | `dart run build_runner build --delete-conflicting-outputs` | exit 0 |
| Format | `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` | exit 0 |
| Analyze | `flutter analyze` | exit 0 |
| Focused test | `flutter test test/parse_amount_test.dart` | all pass |
| Full tests | `flutter test` | all pass |

## Scope

**In scope**:
- `lib/domain/parse_amount.dart` (create)
- `test/parse_amount_test.dart` (create)
- The seven files listed above (replace the inline parse only)

**Out of scope (do NOT touch)**:
- Validation semantics at the call sites (`amount <= 0` rejection, snackbar
  copy) — unchanged.
- Keyboard types / input formatters on the TextFields.
- Displayed number formatting (`NumberFormat('#,##0.00')`) — output
  formatting is a separate concern (see the currency-setting direction note
  in `plans/README.md`).

## Git workflow

- Branch: `advisor/019-arabic-digit-amount-parsing`
- Commit per step; imperative messages.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: The helper

Create `lib/domain/parse_amount.dart`:

```dart
/// Parses user-typed money/count input in an Arabic-first app.
///
/// `double.tryParse` only understands Western digits, but Arabic keyboards
/// commonly emit Eastern Arabic-Indic digits (٠١٢٣٤٥٦٧٨٩ — or the Persian
/// variants ۰۱۲۳۴۵۶۷۸۹), the Arabic decimal separator (٫ U+066B) and the
/// Arabic thousands separator (٬ U+066C). This normalizes all of those,
/// treats both ',' and '٫' as decimal points (matching the app's historic
/// `replaceAll(',', '.')` behavior), strips '٬', and then parses.
double? parseAmount(String raw) {
  final s = _normalizeDigits(raw.trim());
  if (s.isEmpty) return null;
  return double.tryParse(s);
}

/// Same normalization for whole-number fields (e.g. a recurrence interval).
int? parseCount(String raw) {
  final s = _normalizeDigits(raw.trim());
  if (s.isEmpty) return null;
  return int.tryParse(s);
}

String _normalizeDigits(String input) {
  const easternZero = 0x0660; // ٠
  const persianZero = 0x06F0; // ۰
  final out = StringBuffer();
  for (final r in input.runes) {
    if (r >= easternZero && r <= easternZero + 9) {
      out.writeCharCode(0x30 + (r - easternZero));
    } else if (r >= persianZero && r <= persianZero + 9) {
      out.writeCharCode(0x30 + (r - persianZero));
    } else if (r == 0x066B /* ٫ */ || r == 0x2C /* , */) {
      out.write('.');
    } else if (r == 0x066C /* ٬ */) {
      // thousands separator — drop
    } else {
      out.writeCharCode(r);
    }
  }
  return out.toString();
}
```

**Verify**: `flutter analyze` → exit 0.

### Step 2: Tests first

Create `test/parse_amount_test.dart` (style: `test/savings_math_test.dart`):

- `parseAmount('12.50')` → 12.5; `parseAmount('12,50')` → 12.5 (historic
  comma behavior preserved)
- `parseAmount('١٢٣')` → 123; `parseAmount('١٢٫٥')` → 12.5;
  `parseAmount('١٬٢٣٤')` → 1234
- Persian variants: `parseAmount('۴۵')` → 45
- Mixed: `parseAmount('١٢.٥')` → 12.5
- Garbage: `parseAmount('abc')` → null; `parseAmount('')` → null;
  `parseAmount('  ')` → null
- `parseCount('٢')` → 2; `parseCount('3')` → 3; `parseCount('٢٫٥')` → null

**Verify**: `flutter test test/parse_amount_test.dart` → all pass.

### Step 3: Replace the seven call sites

At each site, import `../domain/parse_amount.dart` (adjust the relative path
for `home_screen.dart`/`budgets_screen.dart` — same `../domain/` depth) and
replace:

```dart
double.tryParse(X.replaceAll(',', '.'))  →  parseAmount(X)
int.tryParse(_intervalCtrl.text)         →  parseCount(_intervalCtrl.text)
```

(`add_recurrence_sheet.dart:99` keeps its `?? 1` fallback:
`parseCount(_intervalCtrl.text) ?? 1`.)

**Verify**: `grep -rn "replaceAll(',', '.')" lib/` → no matches;
`grep -rn "tryParse" lib/ui/` → no matches (all routed through the helper);
`flutter analyze` → exit 0.

### Step 4: Full suite

**Verify**: `dart format --output=none --set-exit-if-changed lib test integration_test test_driver && flutter analyze && flutter test`
→ all exit 0.

## Test plan

Covered in Step 2. The call-site behavior change is exactly "inputs that
previously failed now parse"; previously-valid inputs parse identically
(asserted by the Western-digit and comma cases).

## Done criteria

- [ ] `lib/domain/parse_amount.dart` exists with `parseAmount`/`parseCount`
- [ ] All seven sites use the helper; greps in Step 3 return no matches
- [ ] `flutter test` green including the new test file
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- Grep finds parse sites beyond the seven listed (drift) — add them to your
  report; extend only if they are amount/count fields.
- Any existing test fails after Step 3.

## Maintenance notes

- New numeric input fields must use `parseAmount`/`parseCount` — reviewers
  should flag any fresh `double.tryParse` in `lib/ui/`.
- This intentionally does not localize *displayed* numbers (they stay Western
  digits via `NumberFormat('#,##0.00')` app-wide — a deliberate existing
  look). If the app ever switches display to Eastern digits, do it centrally
  where the currency-setting direction item lands.
