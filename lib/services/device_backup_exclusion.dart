import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Keeps the finance database and its backup files out of the device's own
/// cloud backup.
///
/// Android closes this in the manifest (`allowBackup="false"`,
/// `fullBackupContent="false"`). iOS has no manifest equivalent: everything
/// under `Documents/` is swept into iCloud and Finder backups by default, and
/// that is where `floos.sqlite` and every exported backup JSON live. So the
/// app's central promise — that the data stays on the device — held on one
/// platform and not the other.
///
/// The fix is per-file: iOS exposes `isExcludedFromBackup` as a resource value
/// on the file URL, set through a small platform channel in AppDelegate.swift.
///
/// Note what this does NOT do: it does not encrypt anything. A file excluded
/// from backup is still a plaintext SQLite database on the device. This closes
/// the "leaves the device" hole, not the "readable with file access" one.
class DeviceBackupExclusion {
  static const _channel =
      MethodChannel('com.turkisecurity.floos/device_backup');

  /// The database and the sidecar files SQLite keeps beside it. The -wal file
  /// in particular holds committed data that has not been checkpointed yet, so
  /// excluding only the main file would still leak recent transactions.
  static const _dbFiles = [
    'floos.sqlite',
    'floos.sqlite-wal',
    'floos.sqlite-shm',
  ];

  /// Marks one file as excluded, and reports whether it is excluded afterwards.
  ///
  /// The native side reads the flag back rather than trusting the write, so a
  /// `true` here means the OS confirmed it — this is a privacy control, and an
  /// unverified one is exactly what the audit found.
  static Future<bool> excludeFile(String path) async {
    if (!Platform.isIOS) return true;
    try {
      final ok = await _channel.invokeMethod<bool>('exclude', {'path': path});
      return ok ?? false;
    } on MissingPluginException {
      // No handler registered (an older build of the host app).
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Excludes the database, its sidecars, and every backup file sitting in the
  /// documents directory.
  ///
  /// Throws when a file that exists could not be confirmed excluded, so the
  /// caller can surface it. Silence here would re-create the original problem:
  /// a privacy control everyone assumes is on, with nothing checking.
  static Future<void> excludeAppData() async {
    if (!Platform.isIOS) return;

    final dir = await getApplicationDocumentsDirectory();
    final targets = <String>[
      for (final name in _dbFiles) p.join(dir.path, name),
    ];

    // Backups accumulate — every export writes a new timestamped file and
    // nothing deletes them — so they are swept in by name.
    if (dir.existsSync()) {
      for (final entity in dir.listSync()) {
        final name = p.basename(entity.path);
        if (entity is File &&
            name.startsWith('floos_backup_') &&
            name.endsWith('.json')) {
          targets.add(entity.path);
        }
      }
    }

    final failed = <String>[];
    for (final path in targets) {
      // A file that is not there yet cannot be excluded, and does not need to
      // be; it gets marked when it is created.
      if (!File(path).existsSync()) continue;
      if (!await excludeFile(path)) failed.add(p.basename(path));
    }

    if (failed.isNotEmpty) {
      throw StateError(
        'تعذّر استثناء هذه الملفات من النسخ الاحتياطي للجهاز: '
        '${failed.join('، ')}',
      );
    }
  }
}
