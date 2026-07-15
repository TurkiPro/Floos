# Plan 010: Bundle the Arabic fonts so the app makes zero network requests

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat db51b40..HEAD -- lib/app.dart pubspec.yaml`
> If either file changed since this plan was written, compare the "Current
> state" excerpts against the live code before proceeding; on a mismatch, STOP.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED (visual regression risk — typography touches every screen)
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `db51b40`, 2026-07-15

## Why this matters

`README.md` states: "There is no networking code anywhere in the app," and the
store listing declares no data collection. This is currently **false in
practice**: the app uses the `google_fonts` package with no bundled font
assets, and `google_fonts` **downloads fonts over HTTPS at runtime** (from
`fonts.gstatic.com`) on first use, caching them in app support storage. So on
first launch (and after cache clears) the app makes network requests to
Google — leaking the user's IP and the fact they run the app, contradicting
the privacy stance the app is marketed on. A side effect: a user who first
launches offline gets the system fallback font instead of the intended
typography.

Bundling the two font families as assets and dropping the runtime dependency
makes the "no networking" claim true and the typography deterministic.

## Current state

- `pubspec.yaml:29` — `google_fonts: ^6.2.1` under dependencies; the
  `flutter:` section (lines 84–85) declares **no** `fonts:` and **no** `assets:`
  for fonts. `assets/` contains only icon artwork.
- `lib/app.dart:209–232` — the only google_fonts usage:

```dart
/// IBM Plex Sans Arabic as the primary font, Tajawal as fallback.
TextTheme _appTextTheme(Brightness brightness) {
  final base = ThemeData(brightness: brightness).textTheme;
  final theme = GoogleFonts.ibmPlexSansArabicTextTheme(base);
  final fallback = GoogleFonts.tajawal().fontFamily!;
  TextStyle? withFallback(TextStyle? s) =>
      s?.copyWith(fontFamilyFallback: [fallback]);
  return theme.copyWith(
    displayLarge: withFallback(theme.displayLarge),
    ...  // every TextTheme slot gets the fallback
  );
}
```

- `grep -rn "GoogleFonts" lib/` → only `lib/app.dart:211` and `lib/app.dart:212`.
- Font weights actually used in the app (grep `FontWeight.w` in `lib/`):
  w500, w600, w700, w800, plus the implicit w400 regular. **Note: IBM Plex
  Sans Arabic ships weights 100–700 only — there is no w800 cut.** Today
  google_fonts serves w700 and Flutter synthesizes the rest; after bundling,
  declaring up to 700 preserves exactly that behavior.
- Both fonts are SIL OFL 1.1 licensed (bundling requires shipping the license
  text alongside).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Deps | `flutter pub get` | exit 0 |
| Codegen | `dart run build_runner build --delete-conflicting-outputs` | exit 0 |
| Format | `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` | exit 0 |
| Analyze | `flutter analyze` | exit 0 |
| Tests | `flutter test` | all pass |

## Scope

**In scope** (the only files you should modify/create):
- `assets/fonts/` (create) — font files + `OFL.txt` license files
- `pubspec.yaml` — remove `google_fonts`, add `fonts:` declarations
- `lib/app.dart` — replace the google_fonts calls with font-family names
- `README.md` — only if it mentions google_fonts (it does not today; check)

**Out of scope** (do NOT touch):
- Any per-screen `TextStyle` — the family flows in through the theme.
- `web/`, platform folders — Flutter bundles declared fonts everywhere.

## Git workflow

- Branch: `advisor/010-bundle-fonts-offline`
- Commit per logical unit (assets, then wiring); imperative messages.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Obtain the font files

Download the official static TTFs (both repos are on GitHub under OFL):

- IBM Plex Sans Arabic — weights 400, 500, 600, 700 — from the IBM Plex
  release assets (`IBMPlexSansArabic-Regular.ttf`, `-Medium.ttf`,
  `-SemiBold.ttf`, `-Bold.ttf`).
- Tajawal — weights 400, 500, 700 (`Tajawal-Regular.ttf`, `-Medium.ttf`,
  `-Bold.ttf`) — from Google Fonts' download or the Tajawal repo.

Place them under `assets/fonts/`, and add the OFL license text for each family
(`assets/fonts/OFL-IBMPlexSansArabic.txt`, `assets/fonts/OFL-Tajawal.txt`).

**Verify**: `ls assets/fonts/` → 7 `.ttf` files + 2 `OFL-*.txt`.

### Step 2: Declare the fonts and drop google_fonts in pubspec.yaml

Remove the `google_fonts: ^6.2.1` dependency (and its comment). In the
`flutter:` section add:

```yaml
flutter:
  uses-material-design: true
  fonts:
    - family: IBM Plex Sans Arabic
      fonts:
        - asset: assets/fonts/IBMPlexSansArabic-Regular.ttf
        - asset: assets/fonts/IBMPlexSansArabic-Medium.ttf
          weight: 500
        - asset: assets/fonts/IBMPlexSansArabic-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/IBMPlexSansArabic-Bold.ttf
          weight: 700
    - family: Tajawal
      fonts:
        - asset: assets/fonts/Tajawal-Regular.ttf
        - asset: assets/fonts/Tajawal-Medium.ttf
          weight: 500
        - asset: assets/fonts/Tajawal-Bold.ttf
          weight: 700
```

**Verify**: `flutter pub get` → exit 0;
`grep -n google_fonts pubspec.yaml` → no matches.

### Step 3: Rewire lib/app.dart

Replace `_appTextTheme` with a version that applies the family names (no
package import):

```dart
/// IBM Plex Sans Arabic as the primary font, Tajawal as fallback. Both are
/// bundled assets — the app must never fetch fonts (or anything) at runtime.
TextTheme _appTextTheme(Brightness brightness) {
  final base = ThemeData(brightness: brightness).textTheme;
  return base.apply(
    fontFamily: 'IBM Plex Sans Arabic',
    fontFamilyFallback: const ['Tajawal'],
  );
}
```

Remove the `import 'package:google_fonts/google_fonts.dart';` line.

Note: `TextTheme.apply` sets family + fallback on every slot, which is exactly
what the old per-slot `copyWith` loop achieved.

**Verify**: `grep -rn "google_fonts\|GoogleFonts" lib/` → no matches;
`flutter analyze` → exit 0.

### Step 4: Full verification

**Verify**: `dart format --output=none --set-exit-if-changed lib test integration_test test_driver && flutter analyze && flutter test`
→ all exit 0. If a device/emulator is available, `flutter run` and visually
confirm Arabic text renders in Plex (sharp, geometric) not the system font.

## Test plan

- Existing `test/widget_test.dart` pumps the full `FloosApp` and will catch a
  missing-asset crash. No new test needed — fonts are asset wiring, and the
  widget test is the regression net.

## Done criteria

- [ ] `grep -rn "google_fonts" pubspec.yaml lib/` → no matches
- [ ] `pubspec.lock` no longer contains `google_fonts` after `flutter pub get`
- [ ] `assets/fonts/` contains the 7 TTFs and both OFL license files
- [ ] `flutter analyze` exits 0, `flutter test` all pass
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- You cannot obtain the font files from an official source (IBM Plex GitHub
  releases / Google Fonts download) — do not substitute look-alike fonts.
- `flutter test` fails with font/asset loading errors after Step 3 that a
  re-read of the pubspec indentation doesn't explain (the `fonts:` block is
  indentation-sensitive).
- You find another `GoogleFonts` usage outside `lib/app.dart` (drift).

## Maintenance notes

- The wordmark uses `FontWeight.w800` (`lib/ui/home_screen.dart:270`), which
  IBM Plex Sans Arabic doesn't ship; Flutter falls back to the w700 cut, same
  as today's behavior. If the maintainer wants a heavier wordmark, that's a
  design decision, not a regression from this plan.
- After this lands, the "no networking code anywhere" README claim is
  literally true; the store listing's privacy answers need no change.
- Follow-up worth considering (not in scope): a CI grep that fails if any
  `http`/`socket` package sneaks into `pubspec.yaml`, keeping the promise
  enforced mechanically.
