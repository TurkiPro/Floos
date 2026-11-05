# Plan 031: Password-protect backup files

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If any
> STOP condition occurs, stop and report — do not improvise. When done, update
> the status row for this plan in `plans/README.md`.

## Status

- **Priority**: P1 (the open item from the OWASP Mobile Top 10 review —
  M9 Insecure Data Storage)
- **Effort**: M
- **Risk**: MED (a forgotten password makes a backup unrecoverable, by design)
- **Depends on**: —
- **Category**: security / feature (batch 5)
- **Planned at**: commit `f54f113`, 2026-11-05

## Why this matters

`writeBackupFile` (`lib/data/backup.dart:190`) writes the entire financial
history as plain JSON and hands it to the share sheet, from where it lands in
iCloud Drive, Google Drive, WhatsApp, email. The app keeps the database out of
OS cloud backups precisely so this data never leaves the device unprotected —
the backup file currently undoes that the moment it is shared.

## Design

### Envelope, not a new backup format

The plaintext stays exactly today's v1 JSON (`backupFormatVersion` stays 1).
An encrypted file wraps it:

```json
{
  "floosEncrypted": 1,
  "kdf": {"name": "argon2id", "memoryKiB": 19456, "iterations": 2, "parallelism": 1},
  "salt": "<base64, 16 bytes>",
  "nonce": "<base64, 12 bytes>",
  "ciphertext": "<base64, AES-256-GCM, tag appended>"
}
```

- AES-256-GCM; key from the password via Argon2id at the OWASP minimum
  parameters above. Fresh random salt and nonce per file.
- `restoreBackupJson` first checks for `floosEncrypted`; if present, asks for
  the password, decrypts, then parses the inner JSON with the **existing**
  reader — so every validation and lenient-read rule applies unchanged.
  Plain v1 files keep restoring as today.
- A wrong password and a tampered file are the same error to the user
  («كلمة المرور غير صحيحة أو الملف تالف») — GCM cannot tell them apart.

### Dependency

`cryptography` (pure Dart: AES-GCM, Argon2id) plus `cryptography_flutter` for
native acceleration. Both are offline libraries. **Before adding them, grep
their source for any `http`/`HttpClient`/`Socket` use** and STOP if found — the
app's promise is zero network calls (plan 010).

Measure Argon2id on the slowest test device. If it exceeds ~2 s, drop
`memoryKiB` to 12288 with iterations 3 (the other OWASP-listed set) and record
the numbers in the file's `kdf` block — the reader must always honour the
parameters written in the file, never assume them.

### UX — encrypted by default (decided 2026-11-05)

- Encryption is on by default. «نسخة احتياطية» asks for a
  password (twice) with a clear line: «إذا نسيت كلمة المرور فلا يمكن استرجاع
  هذه النسخة.» A small «بدون كلمة مرور» option remains for people who keep the
  file somewhere they trust.

Do **not** store the password anywhere, and do not reuse the app-lock PIN or
biometrics — a backup must be restorable on a new phone.

## Steps

1. Pure `encryptBackup(String json, String password)` /
   `decryptBackup(String envelope, String password)` in
   `lib/data/backup_crypto.dart`. Tests: round trip; wrong password throws the
   typed error; flipped ciphertext byte throws; salt/nonce differ between two
   encryptions of the same input; KDF parameters are read from the file.
2. Wire into `writeBackupFile` / the restore path; the plain path stays.
3. Settings UI: password dialog on backup, password prompt on restoring an
   encrypted file; widget test for both.
4. Extend `test/backup_roundtrip_test.dart`: an encrypted backup restores to an
   identical database.

## Verification

```
flutter analyze
flutter test test/backup_crypto_test.dart test/backup_roundtrip_test.dart
flutter test
```

## STOP conditions

- Either crypto package performs network access → STOP.
- You find yourself writing your own AES, GCM, or KDF code → STOP.
