# Plan 013: Make the category color the user picks actually show up

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat db51b40..HEAD -- lib/ui/theme/tokens.dart lib/ui/widgets/category_icon_tile.dart`
> If either changed since this plan was written, compare the "Current state"
> excerpts against the live code before proceeding; on a mismatch, STOP.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED (visual change on several screens; the 11 seed tiles must not change)
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `db51b40`, 2026-07-15

## Why this matters

Every category has a user-editable color: the schema stores it
(`Categories.colorValue`), the editor sheet lets the user pick it
(`ColorSwatchPicker` in `add_category_sheet.dart`), and the backup preserves
it. But **nothing ever renders it**. Tile colors come from a hardcoded
11-entry map keyed by *icon key* (`categoryTileColors` in
`lib/ui/theme/tokens.dart`), and every icon key outside those 11 falls back to
the neutral "other" beige. Consequences:

- The color picker is a dead control — picking any color changes nothing,
  anywhere, ever. A user who customizes sees their choice silently ignored.
- Every sub-category (they all use non-seed icons like `local_cafe`) and every
  user-created category renders identical gray-beige tiles, so lists lose the
  color-coding that makes categories scannable.

The fix: tiles derive their tint from the category's `colorValue`, with the
curated map kept as an exact override for the 11 seed keys (their pairs are
design-brief-exact and must not shift).

## Current state

- `lib/ui/theme/tokens.dart:155-167` — the only source of tile colors:

```dart
const categoryTileColors = CategoryTileColors({
  'food': (Color(0xFFFAECE7), Color(0xFF712B13)),
  ...
  'investment': (Color(0xFFE3F0F5), Color(0xFF105B73)),
});
```

- `lib/ui/widgets/category_icon_tile.dart:23-38` — the lookup + fallback:

```dart
final pair =
    Theme.of(context).extension<CategoryTileColors>()?.byIconKey[iconKey] ??
        categoryTileColors.byIconKey['other']!;
```

`CategoryIconTile` takes only `iconKey`, `size`, `selected` — no color.

- `grep -rn "colorValue" lib/ui/` → only `add_category_sheet.dart` (read into
  the picker, written on save). Confirms no rendering path uses it.
- Call sites of `CategoryIconTile` (all pass `iconKey` and have the full
  `Category` — or its color — in hand):
  - `lib/ui/widgets/transaction_row.dart:43` (`row.category`)
  - `lib/ui/widgets/category_picker.dart:80-84` (`c`)
  - `lib/ui/category_editor_screen.dart:115` and `:163` (`c`)
  - `lib/ui/budgets_screen.dart:165` (`category`)
  - `lib/ui/statistics_screen.dart:516` (`cat` — nullable, `cat?.iconKey ?? 'other'`)
  - `lib/ui/widgets/icon_key_picker.dart:47` (no Category exists — an icon
    is being chosen; see Step 3 for what to pass)
- Repo conventions: design tokens live in `tokens.dart`; pure logic gets a
  unit test under `test/` (see `test/budget_progress_test.dart` for the
  plain-function test style).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Deps | `flutter pub get` | exit 0 |
| Codegen | `dart run build_runner build --delete-conflicting-outputs` | exit 0 |
| Format | `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` | exit 0 |
| Analyze | `flutter analyze` | exit 0 |
| Focused test | `flutter test test/category_tile_colors_test.dart` | all pass |
| Full tests | `flutter test` | all pass |

## Scope

**In scope** (the only files you should modify/create):
- `lib/ui/theme/tokens.dart` (add the derivation function)
- `lib/ui/widgets/category_icon_tile.dart` (accept an optional color)
- The six call-site files listed above (pass the category color through)
- `test/category_tile_colors_test.dart` (create)

**Out of scope** (do NOT touch):
- The 11 curated pairs in `categoryTileColors` — they are design-brief-exact.
- `add_category_sheet.dart`'s save/read logic and `ColorSwatchPicker` itself.
- The data layer.

## Git workflow

- Branch: `advisor/013-render-category-colors`
- Commit per step; imperative messages.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add a pure derivation function to tokens.dart

In `lib/ui/theme/tokens.dart`, add:

```dart
/// Tile colors for a category: the curated design-brief pair when the icon
/// key is one of the 11 seeded ones, otherwise a pair derived from the
/// category's own [colorValue] — pale tint background, readable foreground —
/// so user-created categories and sub-categories carry the color the user
/// picked instead of all falling back to the neutral "other" pair.
(Color bg, Color fg) categoryTilePair({
  required String iconKey,
  required int? colorValue,
  required Brightness brightness,
}) {
  final curated = categoryTileColors.byIconKey[iconKey];
  if (curated != null) return curated;
  if (colorValue == null) return categoryTileColors.byIconKey['other']!;
  final color = Color(colorValue);
  final hsl = HSLColor.fromColor(color);
  if (brightness == Brightness.light) {
    // Pale tint like the curated pairs (~93% lightness), deep saturated fg.
    final bg = hsl.withLightness(0.93).withSaturation(
        hsl.saturation.clamp(0.35, 0.75)).toColor();
    final fg = hsl.withLightness(0.28).toColor();
    return (bg, fg);
  }
  // Dark mode: dim tint that reads on the #1A1A1C card, brighter fg.
  final bg = hsl.withLightness(0.16).toColor();
  final fg = hsl.withLightness(0.72).toColor();
  return (bg, fg);
}
```

**Verify**: `flutter analyze` → exit 0.

### Step 2: Let CategoryIconTile take the color

In `lib/ui/widgets/category_icon_tile.dart`, add an optional `colorValue`:

```dart
final String iconKey;
final int? colorValue; // Category.colorValue; null keeps the key-only lookup
final double size;
final bool selected;
```

and replace the pair lookup with:

```dart
final pair = categoryTilePair(
  iconKey: iconKey,
  colorValue: colorValue,
  brightness: Theme.of(context).brightness,
);
```

Note this drops the `Theme.of(context).extension<CategoryTileColors>()` read
in favor of the same const map the extension carries — the extension has no
theme-varying content today. Leave the extension registered in `app.dart`
(removing it is out of scope).

**Verify**: `flutter analyze` → exit 0 (call sites still compile because the
new parameter is optional).

### Step 3: Thread the color through the call sites

Pass `colorValue:` at each site:

- `transaction_row.dart:43` → `colorValue: row.category.colorValue`
- `category_picker.dart` grid tile → `colorValue: c.colorValue`
- `category_editor_screen.dart` `_archivedList` and `_row` → `colorValue: c.colorValue`
- `budgets_screen.dart` `_BudgetTile` → `colorValue: category.colorValue`
- `statistics_screen.dart:516` → `colorValue: cat?.colorValue`
- `icon_key_picker.dart`: the picker previews icons for a category being
  edited — pass the sheet's currently-selected color so the preview matches
  what will be saved: add a `final int? colorValue;` field to `IconKeyPicker`,
  pass it to each `CategoryIconTile(colorValue: colorValue, ...)`, and supply
  `colorValue: _color.toARGB32()` from `add_category_sheet.dart:152`.

**Verify**: `flutter analyze` → exit 0.

### Step 4: Unit-test the derivation

Create `test/category_tile_colors_test.dart` (model after the plain-function
style of `test/budget_progress_test.dart`):

- seed key returns the curated pair exactly: `categoryTilePair(iconKey: 'food',
  colorValue: 0xFF112233, brightness: Brightness.light)` equals
  `categoryTileColors.byIconKey['food']` (curated wins over colorValue).
- non-seed key + color derives: for `iconKey: 'local_cafe'`,
  `colorValue: 0xFFEF5350`, light mode → bg is *not* the 'other' pair, bg
  lightness ≈ 0.93 and fg lightness ≈ 0.28 (use `HSLColor.fromColor(...)` in
  the assertions with `closeTo(..., 0.01)`).
- non-seed key + null color falls back to the 'other' pair.
- dark mode returns a different pair than light mode for the same inputs.

**Verify**: `flutter test test/category_tile_colors_test.dart` → all pass.

### Step 5: Full suite

**Verify**: `dart format --output=none --set-exit-if-changed lib test integration_test test_driver && flutter analyze && flutter test`
→ all exit 0.

## Test plan

Covered in Step 4. The 11 seed categories are pinned by the "curated wins"
test, which is the visual-regression guard for the store screenshots.

## Done criteria

- [ ] `categoryTilePair` exists in `tokens.dart` and is unit-tested (4 cases)
- [ ] All six call sites pass `colorValue` (grep: `grep -rn "colorValue:" lib/ui/ | grep -c CategoryIconTile` is unreliable — instead check `grep -rn "CategoryIconTile(" lib/ui/` and confirm each listed site passes it)
- [ ] `flutter test` exits 0 including the new test file
- [ ] Seed categories render identically (curated-wins test passes)
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- `CategoryIconTile` already takes a color parameter (drift).
- The derived light-mode colors are illegible for any of the 15 swatches in
  `categorySwatches` (`lib/ui/widgets/color_swatch_picker.dart`) — eyeball via
  the unit test's lightness assertions; if a swatch lands outside sane
  contrast, report rather than invent a new formula.

## Maintenance notes

- If a designer later specifies exact dark-mode pairs for the seed keys, they
  slot into `categoryTileColors` (or a dark variant map) without touching the
  derivation.
- Reviewer should screenshot home + category editor in both themes; the 11
  seed tiles must be pixel-identical to before, custom/sub-categories now
  tinted.
- Deferred (deliberately): removing the now-redundant `CategoryTileColors`
  ThemeExtension registration in `app.dart`.
