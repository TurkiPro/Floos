# Plan 002: Stop the app lock leaking the balance in the app switcher

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat b756b1a..HEAD -- lib/app.dart`
> If `lib/app.dart` changed since this plan was written, compare the "Current
> state" excerpt against the live code before proceeding; on a mismatch, treat
> it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `b756b1a`, 2026-07-15

## Why this matters

Floos offers a Face ID / fingerprint / passcode lock for a reason — the balance
and spending history are sensitive. But the lock only re-engages on the
`paused` lifecycle state. On iOS the system captures the app-switcher thumbnail
as the app goes **inactive** (one state earlier), and the "inactive" state also
covers the moments when Control Centre or an incoming call slides over the app.
In all of those, the current screen — the balance, the transactions — is still
on display and gets snapshotted. A user who enabled the lock specifically to
hide this still sees it in the multitasking preview. This plan draws an opaque
cover the instant the app becomes inactive, so the snapshot and the transient
overlays show the cover, not the data.

## Current state

`lib/app.dart` gates the app behind `_LockGate`. Its lifecycle handling only
acts on `paused` and `resumed`:

```dart
// lib/app.dart:80
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused) {
    if (context.read<AppSettings>().appLockEnabled && mounted) {
      setState(() => _unlocked = false);
    }
  } else if (state == AppLifecycleState.resumed) {
    _maybeAuthenticate();
  }
}
```

The lock UI is rendered by `build` when `locked` is true:

```dart
// lib/app.dart:100
@override
Widget build(BuildContext context) {
  final locked = context.watch<AppSettings>().appLockEnabled && !_unlocked;
  if (!locked) return widget.child;
  // ... Scaffold with lock icon + "فتح" button ...
}
```

Two gaps:
1. Re-locking happens on `paused`, which on iOS is **after** the app-switcher
   snapshot is taken (the snapshot is taken around `inactive`). So the snapshot
   can capture the unlocked content.
2. Nothing covers the screen during `inactive` when the lock is *off* either —
   but that's by design (no lock, no expectation of privacy), so this plan only
   changes behaviour when `appLockEnabled` is true.

`AppSettings.appLockEnabled` is the flag (read via `context.read/watch<AppSettings>()`).
Relevant design tokens live in `lib/ui/theme/tokens.dart` (`AppSpacing`,
`AppTextSizes`, `AppColors`, `AppRadii`) — the existing lock Scaffold already
uses them.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Install | `flutter pub get` | exit 0 |
| Codegen | `dart run build_runner build --delete-conflicting-outputs` | exit 0 |
| Format check | `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` | exit 0 |
| Analyze | `flutter analyze` | `No issues found!` |
| Tests | `flutter test` | all pass |

## Scope

**In scope**:
- `lib/app.dart` (modify `_LockGate` only)
- `plans/README.md` (status update)

**Out of scope** (do NOT touch):
- `lib/services/app_lock_service.dart` — the authentication itself is correct.
- The theme/build in `_buildTheme`.
- `AppSettings` — no new setting is needed; reuse `appLockEnabled`.

## Git workflow

- Branch: `advisor/002-lock-screen-privacy-overlay`
- Commit style matches `git log` (imperative subject). Example:
  `Sign the iOS release build manually`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Track an "obscured" state driven by `inactive`

In `_LockGateState`, add a bool `_obscured = false`. Update
`didChangeAppLifecycleState` so that:

- On `AppLifecycleState.inactive` **or** `AppLifecycleState.hidden` **or**
  `AppLifecycleState.paused`: if `appLockEnabled`, set `_obscured = true` (and,
  as today, `_unlocked = false` so re-auth is required on return).
- On `AppLifecycleState.resumed`: set `_obscured = false`, then call
  `_maybeAuthenticate()` as today.

Guard every `setState` with `mounted`. The intent: the cover goes up the moment
the app stops being frontmost, before any snapshot, and comes down only after
a real resume.

Target shape:

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  final lockOn = context.read<AppSettings>().appLockEnabled;
  switch (state) {
    case AppLifecycleState.inactive:
    case AppLifecycleState.hidden:
    case AppLifecycleState.paused:
      if (lockOn && mounted) {
        setState(() {
          _obscured = true;
          _unlocked = false;
        });
      }
      break;
    case AppLifecycleState.resumed:
      if (mounted) setState(() => _obscured = false);
      _maybeAuthenticate();
      break;
    case AppLifecycleState.detached:
      break;
  }
}
```

**Verify**: `flutter analyze` → `No issues found!` (all `AppLifecycleState`
cases handled or explicitly defaulted).

### Step 2: Paint an opaque cover while obscured

In `build`, when `appLockEnabled && _obscured` is true, return an opaque
full-screen cover **instead of** the child, even if the lock screen would
otherwise show. The cover must be fully opaque (no transparency) so nothing
behind it is captured. Reuse the lock visual so it reads as intentional: a
filled `Scaffold` (theme background) with the app lock icon centred is enough —
it does not need the "فتح" button (that belongs to the interactive lock state).

Keep the existing `locked` path for when the app is resumed-but-not-yet-unlocked
(that path shows the "فتح" button and calls `_maybeAuthenticate`). Precedence in
`build`:

1. If `appLockEnabled && _obscured` → opaque cover (no data, no button).
2. Else if `appLockEnabled && !_unlocked` → existing interactive lock screen.
3. Else → `widget.child`.

**Verify**:
- `flutter analyze` → `No issues found!`
- `flutter test test/widget_test.dart` → passes (default settings have the lock
  **off**, so the home screen and its empty-state text still render — this
  proves the lock-off path is unchanged).

### Step 3: Format, analyze, full test

**Verify** (all must pass):
- `dart format lib test integration_test test_driver` then
  `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` → exit 0
- `flutter analyze` → `No issues found!`
- `flutter test` → all pass.

## Test plan

- `flutter test` must stay green. `test/widget_test.dart` already builds
  `FloosApp` with default settings (lock off) and asserts the home screen shows;
  that is the regression guard that the lock-off path is untouched.
- A widget test that toggles `appLockEnabled` on and pumps lifecycle states is
  **optional** and only worth adding if it's cheap; driving
  `didChangeAppLifecycleState` in a widget test is fiddly. If you add one, model
  it after `test/widget_test.dart` (in-memory DB, `SharedPreferences.setMockInitialValues`).
  Do not block completion on it.
- The real validation is manual and device-only (see Maintenance notes) — call
  that out in your completion report rather than claiming it's verified here.

## Done criteria

ALL must hold:

- [ ] `flutter analyze` → `No issues found!`
- [ ] `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` exits 0
- [ ] `flutter test` exits 0 (existing tests still pass)
- [ ] `lib/app.dart` handles `inactive`/`hidden` by obscuring when the lock is on
- [ ] With the lock **off**, `build` still returns `widget.child` unchanged
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- The `didChangeAppLifecycleState` in the live code differs from the "Current
  state" excerpt (drift).
- Handling `hidden` causes an analyzer error about an unknown enum value — the
  `hidden` state exists in the Flutter version this repo uses (3.44.4), but if
  analysis disagrees, report it rather than removing the case blindly.
- Making the change appears to require a new field in `AppSettings` or touching
  `AppLockService` — it should not.

## Maintenance notes

- **This fix must be verified on a real iOS device**, which cannot be done in
  CI or on the Windows dev machine: enable the lock, open the app to the home
  screen, swipe into the app switcher, and confirm the thumbnail shows the cover
  and not the balance. Repeat by opening Control Centre. State clearly in the PR
  that this manual check is the real acceptance test.
- Android's Recents behaves differently (it does not snapshot as aggressively),
  but the same cover is harmless there. A stronger Android-only option is
  `FLAG_SECURE`; it is intentionally **not** in scope here (it also blocks
  screenshots, a broader product decision). Note it as a possible follow-up.
- Reviewer should confirm the cover is fully opaque and that the lock-off path
  returns `widget.child` with no new wrapper.
