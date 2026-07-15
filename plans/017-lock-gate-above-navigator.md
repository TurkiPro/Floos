# Plan 017: Make the app lock cover every route, not just Home

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat db51b40..HEAD -- lib/app.dart test/widget_test.dart`
> If either changed since this plan was written, compare the "Current state"
> excerpts against the live code before proceeding; on a mismatch, STOP.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED (touches the root of the widget tree; must not lose navigation state)
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `db51b40`, 2026-07-15

## Why this matters

The Face ID / passcode lock and the app-switcher privacy cover (plan 002) are
implemented in `_LockGate` — which wraps **only the `home:` route**:

```dart
home: const _LockGate(child: HomeScreen()),   // lib/app.dart:44
```

`MaterialApp`'s Navigator sits *above* the home route. Any pushed screen —
Settings, Statistics, Savings, Months, Income, a bottom sheet, a dialog —
renders **on top of** the lock gate. Concretely, with the lock enabled:

- Background the app while on the Statistics screen → the app-switcher
  snapshot shows the statistics, not the cover. The plan-002 protection only
  works when the user happens to be on Home.
- Resume the app while on any pushed screen → `_LockGate` flips to "locked"
  *underneath* that screen; the user sees and freely uses the pushed screen.
  **The lock never appears at all.** The only thing protected is Home.

So the marquee privacy feature is bypassed by simply navigating anywhere.
The fix is structural and standard: mount the gate **above the Navigator**
via `MaterialApp.builder`, keeping the Navigator alive underneath an opaque
overlay so navigation state survives lock/unlock.

## Current state

- `lib/app.dart:29-49` — the MaterialApp:

```dart
child: Consumer<AppSettings>(
  builder: (context, s, _) => MaterialApp(
    title: 'فلوس',
    ...
    theme: _buildTheme(Brightness.light, s.accent),
    darkTheme: _buildTheme(Brightness.dark, s.accent),
    themeMode: s.themeMode,
    home: const _LockGate(child: HomeScreen()),
  ),
),
```

- `lib/app.dart:55-163` — `_LockGate`/`_LockGateState`: lifecycle-driven
  `_obscured`/`_unlocked` flags (correct, keep as-is), and a `build` that
  **returns either** the cover Scaffold, the interactive lock Scaffold, or
  `widget.child`. Returning something other than `child` is fine while the
  gate wraps a single screen, but once it wraps the Navigator it would
  unmount all routes on every lock — the rebuild below must switch to a
  Stack that keeps `child` mounted.
- The providers (`Provider<AppDatabase>`, `ChangeNotifierProvider<AppSettings>`)
  are **above** the MaterialApp (lib/app.dart:22-24), so a `builder:` context
  can still `context.read/watch<AppSettings>()`.
- Decision history to honor: `plans/002-lock-screen-privacy-overlay.md`
  established the inactive/hidden/paused → `_obscured` behavior and
  deliberately deferred Android `FLAG_SECURE` as a separate product decision.
  This plan does not change either decision — it relocates where the gate sits.
- `test/widget_test.dart` — pumps `FloosApp` with mock prefs (lock off) and
  asserts the home screen renders; the pattern to copy for the new test.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Deps | `flutter pub get` | exit 0 |
| Codegen | `dart run build_runner build --delete-conflicting-outputs` | exit 0 |
| Format | `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` | exit 0 |
| Analyze | `flutter analyze` | exit 0 |
| Focused test | `flutter test test/widget_test.dart test/lock_gate_test.dart` | all pass |
| Full tests | `flutter test` | all pass |

## Scope

**In scope**:
- `lib/app.dart` (move the gate; restructure `_LockGate.build` to a Stack)
- `test/lock_gate_test.dart` (create)

**Out of scope (do NOT touch)**:
- `lib/services/app_lock_service.dart` — authentication is correct and
  fails closed.
- The lifecycle logic in `didChangeAppLifecycleState` — plan 002's behavior
  is right; only the mount point and build structure change.
- Android `FLAG_SECURE` — recorded follow-up from plan 002; a separate
  product decision (it also blocks user screenshots).
- `_buildTheme`, `_appTextTheme`.

## Git workflow

- Branch: `advisor/017-lock-gate-above-navigator`
- Commit per step; imperative messages.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Mount the gate above the Navigator

In the `MaterialApp` construction (`lib/app.dart:29-49`):

```dart
builder: (context, child) =>
    _LockGate(child: child ?? const SizedBox.shrink()),
home: const HomeScreen(),
```

Add a comment carrying the intent:

```dart
// The gate must wrap the Navigator (via builder:), not the home route —
// otherwise every pushed screen renders above the lock and bypasses it.
```

**Verify**: `flutter analyze` → exit 0.

### Step 2: Keep the Navigator alive under an opaque overlay

Restructure `_LockGateState.build` so `widget.child` is **always in the
tree** and the cover/lock UI stacks on top:

```dart
@override
Widget build(BuildContext context) {
  final lockOn = context.watch<AppSettings>().appLockEnabled;
  final covering = lockOn && (_obscured || !_unlocked);

  return Stack(
    fit: StackFit.expand,
    children: [
      // Always mounted: locking must not destroy navigation state.
      widget.child,
      if (covering)
        // Opaque by construction — this is what the app switcher snapshots.
        _obscured ? const _ObscureCover() : const _UnlockScreen(),
    ],
  );
}
```

Extract the two existing Scaffolds into small private widgets:
`_ObscureCover` (the icon-only cover — current lines 123-130) and
`_UnlockScreen` (the interactive Scaffold with the 'فتح' button — current
lines 135-162; it needs the `_maybeAuthenticate` callback, so pass
`onUnlock: _maybeAuthenticate` as a field or keep it as a method-returning
widget on the State). The Scaffolds are opaque (theme background) — keep
them Scaffolds so nothing behind bleeds through.

Also unfocus any text field when the cover goes up, so the keyboard doesn't
float above the lock: in `didChangeAppLifecycleState`, alongside setting
`_obscured = true`, call `FocusManager.instance.primaryFocus?.unfocus()`.

**Verify**: `flutter analyze` → exit 0; `flutter test test/widget_test.dart`
→ passes (lock off ⇒ home renders and is interactive — the Stack adds no
barrier when `covering` is false).

### Step 3: Widget-test the gate

Create `test/lock_gate_test.dart`, modeled on `test/widget_test.dart`
(in-memory DB, `SharedPreferences.setMockInitialValues`):

1. **Lock on ⇒ unlock screen covers every route**: set
   `{'appLockEnabled': true}` in mock prefs, pump `FloosApp`,
   `pumpAndSettle`. In tests `local_auth` throws `MissingPluginException`,
   `AppLockService.authenticate` catches → `false` → stays locked. Assert
   `find.text('فلوس مقفل')` is visible, and that the add-transaction button
   cannot be tapped: `tester.tap(find.text('إضافة حركة'), warnIfMissed: false)`
   then `pumpAndSettle` and assert no bottom sheet appeared (e.g.
   `find.text('حفظ')` is nothing). This is the regression test for the
   bypass: before this plan, home was reachable.
2. **Lock off ⇒ unchanged**: default prefs, pump, assert the home empty-state
   renders (duplicates widget_test's assertion — keep it, it documents the
   contract of this file).
3. Reuse widget_test.dart's teardown comment/pattern (`pumpWidget(SizedBox.shrink())`
   + `pump(Duration.zero)`) so drift's stream-cleanup timer doesn't fail the test.

**Verify**: `flutter test test/lock_gate_test.dart` → all pass.

### Step 4: Full suite

**Verify**: `dart format --output=none --set-exit-if-changed lib test integration_test test_driver && flutter analyze && flutter test`
→ all exit 0.

## Test plan

Covered in Step 3. The on-device acceptance test from plan 002 must be
repeated after this change (app-switcher snapshot while on the **Statistics**
screen this time — the previously-bypassed case); record in your report that
it needs a physical device, same as plan 002 did.

## Done criteria

- [ ] `grep -n "builder:" lib/app.dart` shows the `_LockGate` in MaterialApp.builder
- [ ] `grep -n "home:" lib/app.dart` shows `home: const HomeScreen()` (no gate)
- [ ] `widget.child` is unconditionally present in `_LockGateState.build`'s Stack
- [ ] `flutter test` green, including the two new lock-gate tests
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- `lib/app.dart` no longer matches the "Current state" excerpts (drift).
- The new test at Step 3 can still open the add-transaction sheet with the
  lock on — that means the Stack/ordering is wrong; report the widget tree
  rather than adding pointer-absorbing hacks.
- Keeping the Navigator mounted under the lock breaks `pumpAndSettle` with
  endless animation — report which animation (likely a progress indicator)
  instead of switching to Offstage (Offstage would defeat the snapshot cover
  on some platforms).

## Maintenance notes

- Anyone adding a second `Navigator` (e.g. nested navigation) must keep it
  below `MaterialApp.builder` for the gate to keep covering everything —
  note for reviewers of future navigation changes.
- The plan-002 on-device iOS verification note still stands; this plan
  *widens* what it protects.
- Android `FLAG_SECURE` remains the recorded follow-up for stronger Android
  recents/screenshot protection (product decision: it also blocks deliberate
  user screenshots).
