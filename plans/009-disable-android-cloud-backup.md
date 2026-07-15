# Plan 009: Keep the finance database out of Android cloud backups

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat db51b40..HEAD -- android/app/src/main/AndroidManifest.xml`
> If the manifest changed since this plan was written, compare the "Current
> state" excerpt against the live file before proceeding; on a mismatch, STOP.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `db51b40`, 2026-07-15

## Why this matters

Floos's entire privacy stance — stated in `README.md` ("Every byte stays in a
local SQLite file on the device"), in the published privacy policy, and in the
store data-safety declarations ("nothing collected") — is that the user's
financial data never leaves the device. But `android/app/src/main/AndroidManifest.xml`
never sets `android:allowBackup`, and **the Android default is `true`**: the
app's data directory, including `floos.sqlite` (every transaction, income,
savings goal and note the user ever entered), is eligible for Google's
device-to-cloud backup and device-to-device transfer. That means the finance
database is silently uploaded to Google servers on backup-enabled devices —
directly contradicting the promise the app is built around. One attribute
closes the gap.

## Current state

- `android/app/src/main/AndroidManifest.xml` — the `<application>` element
  (lines 22–25) declares only label, name and icon:

```xml
<application
    android:label="فلوس"
    android:name="${applicationName}"
    android:icon="@mipmap/ic_launcher">
```

No `android:allowBackup`, no `android:fullBackupContent`, no
`android:dataExtractionRules` anywhere in the file (verify with
`grep -n "allowBackup\|dataExtractionRules\|fullBackupContent" android/app/src/main/AndroidManifest.xml`
→ no matches today).

- The debug/profile manifests (`android/app/src/debug/AndroidManifest.xml`,
  `android/app/src/profile/AndroidManifest.xml`) only add the INTERNET
  permission for Flutter dev tooling — they are not part of this problem.
- Repo convention: manifest entries carry explanatory comments (see the
  exact-alarm comment block at the top of the same file). Match that style.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Deps | `flutter pub get` | exit 0 |
| Codegen | `dart run build_runner build --delete-conflicting-outputs` | exit 0 |
| Format | `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` | exit 0 |
| Analyze | `flutter analyze` | exit 0, no issues |
| Tests | `flutter test` | all pass |
| Android assemble (proves manifest merge) | `flutter build appbundle --release` | exit 0 |

## Scope

**In scope** (the only file you should modify):
- `android/app/src/main/AndroidManifest.xml`

**Out of scope** (do NOT touch, even though they look related):
- `android/app/src/debug/AndroidManifest.xml` and `.../profile/AndroidManifest.xml`
  — the INTERNET permission there is required by Flutter's debug tooling.
- iOS: the iOS keychain/backup story is different (iOS encrypts app data in
  iCloud backups under the user's account) and is a separate product decision.
- `lib/` — no Dart change is needed.

## Git workflow

- Branch: `advisor/009-disable-android-cloud-backup`
- One commit; imperative message, e.g. "Exclude app data from Android backups"
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Disable backups in the application element

In `android/app/src/main/AndroidManifest.xml`, change the `<application>`
element to:

```xml
<application
    android:label="فلوس"
    android:allowBackup="false"
    android:fullBackupContent="false"
    android:name="${applicationName}"
    android:icon="@mipmap/ic_launcher">
```

and add a short comment above it, matching the file's existing comment style,
explaining the deliberate choice — e.g.:

```xml
<!-- The whole privacy promise is that the finance database never leaves the
     device. allowBackup=false keeps floos.sqlite out of Google's cloud
     device backup and out of device-to-device transfer; users get an
     explicit, user-controlled backup file instead (see plans/016). -->
```

**Verify**: `grep -n 'allowBackup="false"' android/app/src/main/AndroidManifest.xml`
→ one match.

### Step 2: Prove the manifest still merges and the app assembles

**Verify**: `flutter pub get && dart run build_runner build --delete-conflicting-outputs && flutter build appbundle --release`
→ exit 0. (If no Android SDK is available in your environment, run
`flutter analyze` instead and note in your report that the assemble step must
be confirmed by CI, which builds the AAB on every push.)

## Test plan

No unit test can observe a manifest attribute; the verification is the
grep in Step 1 plus a green `flutter build appbundle --release` (locally or in
CI — `.github/workflows/ci.yml` builds the AAB on every push).

## Done criteria

- [ ] `grep -c 'allowBackup="false"' android/app/src/main/AndroidManifest.xml` → 1
- [ ] `flutter analyze` exits 0
- [ ] `flutter test` exits 0 (unchanged, proves nothing broke)
- [ ] AAB assembles (locally or in CI)
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The `<application>` element already sets `allowBackup` or
  `dataExtractionRules` (the manifest drifted — the decision may already have
  been made differently).
- The release build fails on a manifest-merge conflict mentioning
  `allowBackup` (a plugin manifest may be forcing it; report which one —
  the fix would then need `tools:replace`, which is a deliberate escalation
  the maintainer should see).

## Maintenance notes

- This deliberately trades away Google's automatic device-migration restore.
  The user-facing replacement is the explicit local backup/restore feature
  (plan 016, building on `lib/data/backup.dart`): user-controlled, in the
  user's custody, consistent with the README's stated stance.
- If the maintainer ever *wants* cloud backup, the right shape is
  `android:dataExtractionRules` with explicit include/exclude lists — a
  deliberate decision, not the silent default.
- Reviewer should check: no other manifest attributes accidentally reordered;
  the comment explains *why* so the next reader doesn't "fix" it back.
