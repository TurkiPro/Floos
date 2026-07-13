import 'package:local_auth/local_auth.dart';

/// Unlocks the app with whatever the device offers — Face ID, fingerprint, or
/// the device passcode/password. `biometricOnly: false` is what makes the OS
/// pick the right method and fall back to the passcode automatically, so we
/// don't have to branch per platform.
class AppLockService {
  static final _auth = LocalAuthentication();

  /// Whether the device can authenticate at all (has biometrics or a passcode).
  static Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'افتح تطبيق فلوس',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
