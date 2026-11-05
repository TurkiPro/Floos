import 'dart:convert';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';

/// Password protection for backup files.
///
/// A backup is the whole financial history, and it leaves the device the
/// moment it is shared — into iCloud Drive, Google Drive, a chat. The app keeps
/// its database out of OS cloud backups precisely so this data never leaves
/// unprotected; an unencrypted backup file undid that. (OWASP Mobile M9.)
///
/// The plaintext is exactly the existing v1 backup JSON, so restoring an
/// encrypted file runs the very same reader and validation as a plain one. An
/// encrypted file wraps it in an envelope:
///
/// ```json
/// {"floosEncrypted": 1,
///  "kdf": {"name": "argon2id", "memoryKiB": 19456, "iterations": 2,
///          "parallelism": 1},
///  "salt": "<base64>", "nonce": "<base64>",
///  "ciphertext": "<base64>", "mac": "<base64>"}
/// ```
///
/// AES-256-GCM, with the key derived from the password by Argon2id at the
/// OWASP-recommended minimum. Fresh salt and nonce for every file. The header
/// (format and KDF parameters) is bound in as associated data, so a file whose
/// parameters were tampered with fails to open rather than deriving a
/// different key quietly. The reader always uses the parameters written in the
/// file, never its own defaults, so they can be raised later without breaking
/// old backups.
///
/// The password is never stored, and is deliberately not the app-lock PIN or
/// biometrics: a backup must open on a new phone.
const encryptedBackupVersion = 1;

/// Argon2id parameters. Memory is in KiB.
class KdfParams {
  final int memoryKiB;
  final int iterations;
  final int parallelism;
  const KdfParams({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  /// OWASP's first recommended Argon2id configuration: m=19 MiB, t=2, p=1.
  static const owasp =
      KdfParams(memoryKiB: 19456, iterations: 2, parallelism: 1);

  Map<String, Object> toJson() => {
        'name': 'argon2id',
        'memoryKiB': memoryKiB,
        'iterations': iterations,
        'parallelism': parallelism,
      };
}

/// Wrong password, or a file that was altered: AES-GCM cannot tell the two
/// apart, and the user is told the same thing either way.
class BackupPasswordException implements Exception {
  const BackupPasswordException();
  @override
  String toString() => 'wrong password or damaged file';
}

/// Whether [text] is an encrypted backup (rather than a plain v1 one).
bool isEncryptedBackup(String text) {
  try {
    final parsed = jsonDecode(text);
    return parsed is Map<String, dynamic> && parsed['floosEncrypted'] != null;
  } on FormatException {
    return false;
  }
}

/// Encrypts the backup JSON [plain] under [password].
Future<String> encryptBackup(
  String plain,
  String password, {
  KdfParams kdf = KdfParams.owasp,
}) async {
  final aes = AesGcm.with256bits();
  final salt = SecretKeyData.random(length: 16).bytes;
  final nonce = aes.newNonce();
  final header = _header(kdf);
  final key = await _deriveKey(password, salt, kdf);
  final box = await aes.encrypt(
    utf8.encode(plain),
    secretKey: SecretKey(key),
    nonce: nonce,
    aad: utf8.encode(header),
  );
  return jsonEncode({
    'floosEncrypted': encryptedBackupVersion,
    'kdf': kdf.toJson(),
    'salt': base64Encode(salt),
    'nonce': base64Encode(box.nonce),
    'ciphertext': base64Encode(box.cipherText),
    'mac': base64Encode(box.mac.bytes),
  });
}

/// Decrypts an envelope written by [encryptBackup] back to the backup JSON.
/// Throws [BackupPasswordException] for a wrong password or an altered file,
/// and [FormatException] for something that is not an envelope at all.
Future<String> decryptBackup(String envelope, String password) async {
  final Map<String, dynamic> e;
  try {
    e = jsonDecode(envelope) as Map<String, dynamic>;
  } on TypeError {
    throw const FormatException('not an encrypted backup');
  }
  if (e['floosEncrypted'] != encryptedBackupVersion) {
    throw FormatException(
        'unsupported encrypted backup version ${e['floosEncrypted']}');
  }
  final k = e['kdf'];
  if (k is! Map<String, dynamic> || k['name'] != 'argon2id') {
    throw const FormatException('unsupported key derivation');
  }
  final kdf = KdfParams(
    memoryKiB: k['memoryKiB'] as int,
    iterations: k['iterations'] as int,
    parallelism: k['parallelism'] as int,
  );
  final salt = base64Decode(e['salt'] as String);
  final box = SecretBox(
    base64Decode(e['ciphertext'] as String),
    nonce: base64Decode(e['nonce'] as String),
    mac: Mac(base64Decode(e['mac'] as String)),
  );
  final key = await _deriveKey(password, salt, kdf);
  try {
    final clear = await AesGcm.with256bits().decrypt(
      box,
      secretKey: SecretKey(key),
      aad: utf8.encode(_header(kdf)),
    );
    return utf8.decode(clear);
  } on SecretBoxAuthenticationError {
    throw const BackupPasswordException();
  }
}

/// What the ciphertext is bound to: the format and the exact KDF parameters.
String _header(KdfParams kdf) =>
    jsonEncode({'floosEncrypted': encryptedBackupVersion, 'kdf': kdf.toJson()});

/// Argon2id is deliberately slow and memory-hard, so it runs on its own
/// isolate: on the UI isolate it would freeze the app for the duration.
Future<List<int>> _deriveKey(
    String password, List<int> salt, KdfParams kdf) {
  final memory = kdf.memoryKiB, iterations = kdf.iterations;
  final parallelism = kdf.parallelism;
  return Isolate.run(() async {
    final argon = Argon2id(
      memory: memory,
      iterations: iterations,
      parallelism: parallelism,
      hashLength: 32,
    );
    final key = await argon.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return key.extractBytes();
  });
}
