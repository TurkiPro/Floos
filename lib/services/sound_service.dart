import 'package:flutter/services.dart';

/// Plays the confirmation feedback when a transaction is saved.
///
/// Uses the platform's own sound + haptic rather than a bundled audio clip:
/// the Windows implementation of every Flutter audio plugin we tried fails to
/// compile against the installed MSVC toolchain, and a click/alert that the OS
/// already owns is both zero-dependency and consistent with system volume and
/// silent-mode settings.
///
/// Feedback is a nicety, never a requirement: calls are guarded so a platform
/// without support can't stop a transaction from being saved.
class SoundService {
  static Future<void> playSaved({required bool enabled}) async {
    if (!enabled) return;
    try {
      await SystemSound.play(SystemSoundType.alert);
      await HapticFeedback.mediumImpact();
    } catch (_) {
      // Ignore -- the save already succeeded.
    }
  }
}
