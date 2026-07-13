import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Host side of the screenshot run: receives each frame the integration test
/// captures on the device and writes it out as a PNG for CI to upload.
Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes,
        [Map<String, Object?>? _]) async {
      final file = File('screenshots/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      stdout.writeln('wrote ${file.path} (${bytes.length} bytes)');
      return true;
    },
  );
}
