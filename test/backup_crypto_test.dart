import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/backup_crypto.dart';

/// Password-protected backups. Most tests use cheap KDF parameters so the
/// suite stays fast; one runs the real (OWASP) parameters end to end.
void main() {
  const fast = KdfParams(memoryKiB: 256, iterations: 1, parallelism: 1);
  const plain = '{"version":1,"transactions":[{"note":"راتب"}]}';

  test('round-trips under the right password', () async {
    final env = await encryptBackup(plain, 'سر-123', kdf: fast);
    expect(isEncryptedBackup(env), isTrue);
    expect(env, isNot(contains('راتب')), reason: 'nothing readable inside');
    expect(await decryptBackup(env, 'سر-123'), plain);
  });

  test('a wrong password is refused', () async {
    final env = await encryptBackup(plain, 'right', kdf: fast);
    await expectLater(
        decryptBackup(env, 'wrong'), throwsA(isA<BackupPasswordException>()));
  });

  test('an altered file is refused the same way', () async {
    final env = jsonDecode(await encryptBackup(plain, 'pw', kdf: fast))
        as Map<String, dynamic>;
    final bytes = base64Decode(env['ciphertext'] as String);
    bytes[0] ^= 0x01;
    env['ciphertext'] = base64Encode(bytes);
    await expectLater(decryptBackup(jsonEncode(env), 'pw'),
        throwsA(isA<BackupPasswordException>()));
  });

  test('altering the KDF parameters is refused, not silently re-keyed',
      () async {
    final env = jsonDecode(await encryptBackup(plain, 'pw', kdf: fast))
        as Map<String, dynamic>;
    (env['kdf'] as Map<String, dynamic>)['iterations'] = 2;
    await expectLater(decryptBackup(jsonEncode(env), 'pw'),
        throwsA(isA<BackupPasswordException>()));
  });

  test('every file gets a fresh salt and nonce', () async {
    final a = jsonDecode(await encryptBackup(plain, 'pw', kdf: fast)) as Map;
    final b = jsonDecode(await encryptBackup(plain, 'pw', kdf: fast)) as Map;
    expect(a['salt'], isNot(b['salt']));
    expect(a['nonce'], isNot(b['nonce']));
    expect(a['ciphertext'], isNot(b['ciphertext']));
  });

  test('the reader uses the parameters written in the file', () async {
    // Written with non-default parameters; decrypting must not assume the
    // defaults, or raising them later would orphan every older backup.
    final env = await encryptBackup(plain, 'pw', kdf: fast);
    final kdf = (jsonDecode(env) as Map)['kdf'] as Map;
    expect(kdf['memoryKiB'], 256);
    expect(await decryptBackup(env, 'pw'), plain);
  });

  test('a plain backup is not mistaken for an encrypted one', () {
    expect(isEncryptedBackup(plain), isFalse);
    expect(isEncryptedBackup('not json'), isFalse);
  });

  test('the real parameters work end to end', () async {
    final watch = Stopwatch()..start();
    final env = await encryptBackup(plain, 'pw');
    final kdf = (jsonDecode(env) as Map)['kdf'] as Map;
    expect(kdf['memoryKiB'], 19456);
    expect(kdf['iterations'], 2);
    expect(await decryptBackup(env, 'pw'), plain);
    // ignore: avoid_print
    print('argon2id (OWASP params), encrypt + decrypt: '
        '${watch.elapsedMilliseconds} ms on this machine');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
