import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:floos/services/device_backup_exclusion.dart';

/// Only the non-iOS behaviour is testable here — the exclusion itself is an
/// iOS file-system flag set from AppDelegate.swift, and there is no iOS
/// simulator in this suite.
///
/// What these pin down is that the guard never gets in the way anywhere else:
/// Android blocks cloud backup in its manifest and needs nothing from this, so
/// a no-op that throws, hangs, or needs a platform channel would break startup
/// on the platform that was never at risk.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('excludeAppData is a silent no-op off iOS', () async {
    expect(Platform.isIOS, isFalse, reason: 'this suite runs on the host');
    // No MethodChannel handler is registered, so reaching the channel at all
    // would throw MissingPluginException.
    await expectLater(DeviceBackupExclusion.excludeAppData(), completes);
  });

  test('excludeFile reports success off iOS rather than failing', () async {
    // Callers treat false as "the privacy control did not take". Off iOS there
    // is nothing to take, and the manifest already covers it, so false would
    // be a lie that shows the user an error about a platform they are not on.
    expect(await DeviceBackupExclusion.excludeFile('/nonexistent/floos.sqlite'),
        isTrue);
  });
}
