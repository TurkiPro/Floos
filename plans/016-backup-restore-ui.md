# Plan 016: Ship backup & restore in Settings

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat db51b40..HEAD -- lib/data/backup.dart lib/ui/settings_screen.dart pubspec.yaml`
> Plan 011 (budgets in the backup format) **must be DONE first** — check its
> status row in `plans/README.md`; if it isn't DONE, STOP.

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: MED (adds two plugins; restore is destructive by design)
- **Depends on**: plans/011-backup-include-budgets.md (must be DONE). Pairs
  with plans/009 (this feature is the user-controlled replacement for the
  Android cloud backup 009 turns off).
- **Category**: direction
- **Planned at**: commit `db51b40`, 2026-07-15

## Why this matters

Today a lost or replaced phone means **total loss of the user's financial
history** — the README's "Not in v1" list defers cloud sync deliberately (the
project refuses to become custodian of anyone's financial data), but the local
backup engine that squares that circle already exists and is tested:
`lib/data/backup.dart` (plan 004's spike) serializes and restores the whole
database. What's missing is purely the last mile: a Settings entry that saves
the backup file somewhere the *user* controls (share sheet → their own iCloud
Drive / Google Drive / Files) and an import flow that restores it. This is the
single highest-value feature available for its cost, it fixes the
export-without-import asymmetry, and it stays fully inside the privacy stance:
the file never touches a server the project runs.

## Current state

- Engine (do not rewrite): `lib/data/backup.dart` —
  `buildBackupJson(db) → String` and `restoreBackupJson(db, json)` with
  **Replace** semantics, transaction-wrapped, throwing `BackupFormatException`
  on invalid input. Tested by `test/backup_roundtrip_test.dart`.
- Design contract: `plans/004-backup-restore-design.md`. Decisions already
  made there that this plan honors:
  - Replace semantics ⇒ the UI **must** put restore behind an explicit,
    clearly-worded confirmation (§2).
  - The file includes archived rows (§6 — confirmed desired: they carry history).
  - Delivery needs a file picker + share sheet and a Settings entry (§6).
- Decisions §6 left open, **made now** so you don't have to:
  - **Encryption: not in this iteration.** The file goes where the user
    explicitly sends it; a passphrase flow (with the support burden of
    forgotten passphrases irrecoverably locking data) is a separate feature.
    The confirmation copy must say the file is unencrypted.
  - **Version compatibility: exact-match stays.** `backupFormatVersion` is 1
    and no other version has ever existed; the error message must be clear
    ("ملف نسخة احتياطية من إصدار غير مدعوم").
- UI home: `lib/ui/settings_screen.dart` — the "البيانات" section (lines
  ~287-295) currently holds "تصدير CSV" (line 87-96 pattern for an async
  tile) and "حذف كل البيانات" with its `_confirmClear` AlertDialog
  (lines 318-349) — copy that dialog's shape for the restore confirmation.
- File I/O conventions: `lib/data/export.dart` writes to
  `getApplicationDocumentsDirectory()` with a `yyyyMMdd_HHmmss` stamp — reuse
  the stamp style for the backup filename (`floos_backup_20260715_213000.json`).
- Dependency policy: the repo adds packages sparingly with a one-line comment
  in `pubspec.yaml` explaining each (see existing entries). Add exactly two:
  - `share_plus` — share sheet for the exported file (the README/export.dart
    comment already anticipates it).
  - `file_selector` — open a JSON file for restore (first-party
    flutter.dev-maintained; avoids `file_picker`'s heavier platform surface).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Deps | `flutter pub get` | exit 0 |
| Codegen | `dart run build_runner build --delete-conflicting-outputs` | exit 0 |
| Format | `dart format --output=none --set-exit-if-changed lib test integration_test test_driver` | exit 0 |
| Analyze | `flutter analyze` | exit 0 |
| Tests | `flutter test` | all pass |
| Android assemble | `flutter build appbundle --release` | exit 0 |

## Scope

**In scope**:
- `pubspec.yaml` (two new deps, commented)
- `lib/data/backup.dart` — ONLY to add a small `writeBackupFile(db) → File`
  helper mirroring `exportTransactionsCsvToFile` (engine logic untouched)
- `lib/ui/settings_screen.dart` — the two new tiles + confirmation dialog
- `test/backup_roundtrip_test.dart` — no changes expected; run it
- `README.md` — move backup/import out of the "Not in v1" list, one sentence
  on where the file lives
- `STORE_LISTING.md` — only if it claims "no export of your data" anywhere
  (check; likely no change)

**Out of scope (do NOT touch)**:
- Restore-file *creation* on iCloud/Drive — the share sheet delegates that to
  the OS; no cloud SDKs, no networking code.
- Encryption, scheduled/automatic backups, merge-import — recorded as
  follow-ups in the design doc.
- `lib/data/export.dart` (CSV) — unrelated.
- The engine's Replace semantics.

## Git workflow

- Branch: `advisor/016-backup-restore-ui`
- Commit per step; imperative messages.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add the dependencies

In `pubspec.yaml` dependencies (with the repo's comment style):

```yaml
  # Share sheet for handing the backup file to the user's own storage
  # (Files/iCloud/Drive). The file never touches a server we run.
  share_plus: ^10.0.0
  # System file-open dialog for picking a backup file to restore.
  file_selector: ^1.0.3
```

**Verify**: `flutter pub get` → exit 0.

### Step 2: File helper in backup.dart

Add (below `buildBackupJson`, mirroring `export.dart`'s
`exportTransactionsCsvToFile` including its imports pattern):

```dart
/// Writes the backup JSON to the app documents directory and returns the
/// file. The caller hands it to the OS share sheet — where it goes from
/// there (Files, iCloud, Drive, AirDrop) is the user's choice and custody.
Future<File> writeBackupFile(AppDatabase db) async {
  final json = await buildBackupJson(db);
  final dir = await getApplicationDocumentsDirectory();
  final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  final file = File(p.join(dir.path, 'floos_backup_$stamp.json'));
  await file.writeAsString(json);
  return file;
}
```

**Verify**: `flutter analyze` → exit 0.

### Step 3: Settings tiles

In `lib/ui/settings_screen.dart`, in the "البيانات" section **above** the
delete tile, add two `_navTile`s:

1. **"نسخة احتياطية"** (icon: `Icons.backup_outlined`): calls
   `writeBackupFile(db)` then
   `SharePlus.instance.share(ShareParams(files: [XFile(file.path)]))`
   (or `Share.shareXFiles([XFile(file.path)])` if the installed share_plus
   major uses the older static API — match whichever the resolved version
   documents). Guard `context.mounted` after each await (the file's existing
   CSV tile at lines 87-96 is the pattern). On failure, snackbar
   'تعذّر إنشاء النسخة الاحتياطية'.

2. **"استعادة نسخة احتياطية"** (icon: `Icons.restore_outlined`):
   - `openFile` from `file_selector` with a JSON `XTypeGroup`
     (`XTypeGroup(label: 'JSON', extensions: ['json'])`); bail silently if
     the user cancels.
   - Read the string, then show a confirmation `AlertDialog` modeled on
     `_confirmClear` with copy that satisfies the design doc's §2 requirement,
     e.g. title 'استعادة النسخة الاحتياطية؟' and body
     'سيتم **حذف كل البيانات الحالية** واستبدالها بمحتوى النسخة الاحتياطية.
     لا يمكن التراجع. (الملف غير مشفّر — احتفظ به في مكان آمن.)'
   - On confirm: `await restoreBackupJson(db, jsonString)`; snackbar
     'تمت الاستعادة'. Catch `BackupFormatException` → snackbar with a clear
     reason ('ملف غير صالح' / the unsupported-version message); catch
     everything else → 'فشلت الاستعادة — لم تتغير بياناتك.' (true, thanks to
     the transaction rollback).
   - After a successful restore call
     `refreshAlerts(db, context.read<AppSettings>())` (already imported in
     this file) — the restored rules change the salary/budget alerts.

**Verify**: `flutter analyze` → exit 0.

### Step 4: Docs

- `README.md`: in "Not in v1 (deliberately)", the backup bullet is now
  delivered — move it to the feature docs area (the Design decisions section
  or Structure list): one sentence, e.g. "Backup & restore: Settings writes a
  full-fidelity JSON of the database and hands it to the OS share sheet; the
  file stays in the user's custody. Restore replaces the database wholesale
  behind a confirmation."
- `plans/004-backup-restore-design.md`: mark §6's "Delivery / dependencies"
  question answered (share_plus + file_selector, this plan).

**Verify**: `grep -n "share_plus" README.md pubspec.yaml` → pubspec hit;
README updated per above.

### Step 5: Full verification

**Verify**: `dart format --output=none --set-exit-if-changed lib test integration_test test_driver && flutter analyze && flutter test && flutter build appbundle --release`
→ all exit 0. (The assemble step proves the two new plugins survive R8/manifest
merge; if no Android SDK locally, note that CI covers it.)

If a device/simulator is available: run the app, create a backup, share it to
Files, wipe data via 'حذف كل البيانات', restore the file, confirm the data is
back (transactions, goals, budgets, categories).

## Test plan

- Engine behavior is already covered by `test/backup_roundtrip_test.dart`
  (including budgets, after plan 011). Run it unchanged.
- The new UI is thin glue over plugins that no-op headlessly; the on-device
  walkthrough in Step 5 is the acceptance test. Record in your report whether
  it was performed or deferred to a device owner.

## Done criteria

- [ ] Settings shows نسخة احتياطية and استعادة نسخة احتياطية tiles in البيانات
- [ ] Restore is behind an AlertDialog stating data will be replaced and the
      file is unencrypted
- [ ] `BackupFormatException` surfaces as a clear Arabic snackbar, generic
      failure states data unchanged
- [ ] `refreshAlerts` runs after a successful restore
- [ ] `flutter analyze` + `flutter test` green; AAB assembles
- [ ] README updated; no files outside scope modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- Plan 011 is not DONE (budgets missing from the format — shipping restore
  now would wipe users' budgets).
- `share_plus`/`file_selector` fail to resolve against Flutter 3.44.4 — report
  the resolution error; do not substitute other plugins.
- The Android release assemble fails on a plugin manifest conflict.
- Any `test/backup_roundtrip_test.dart` test fails before your changes.

## Maintenance notes

- **Follow-ups deliberately deferred** (record in index if picked up):
  passphrase encryption of the file; an automatic "backup reminder" nudge
  (e.g. monthly notification if no recent backup); merge-import.
- When schema v7 lands someday: bump `backupFormatVersion` and decide the
  old-file migration story *then* (design doc §6) — the exact-match rejection
  keeps that decision honest.
- Reviewer: confirm no networking-capable package snuck in via transitive
  deps of share_plus/file_selector (both are method-channel wrappers; a
  `flutter pub deps` glance suffices) — the README's "no networking" claim
  (plan 010) must survive this feature.
