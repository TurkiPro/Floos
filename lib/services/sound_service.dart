import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../data/enums.dart';

/// Plays the short confirmation chime when a transaction is saved: an "in" tone
/// for income, an "out" tone for expense. The clips are bundled assets
/// (assets/sound_effects/*.m4a) so nothing is fetched at runtime.
///
/// Feedback is a nicety, never a requirement: every call is guarded so a
/// platform without audio support (e.g. the Windows dev build, where just_audio
/// has no implementation) or a decode failure can't stop a save.
class SoundService {
  // Deliberately quiet — a save confirmation should be a gentle tick, not an
  // alert. 0.30 caps playback well below full volume (~-10 dB) regardless of
  // how hot the source file was recorded; this is the single knob to tune if
  // it's too loud/soft on device.
  static const _volume = 0.30;

  // One reusable player per sound, each preloaded once so a save replays
  // instantly (seek to 0 + play) instead of re-decoding.
  static AudioPlayer? _in;
  static AudioPlayer? _out;

  static Future<AudioPlayer?> _load(String asset) async {
    try {
      final p = AudioPlayer();
      await p.setVolume(_volume);
      await p.setAsset('assets/sound_effects/$asset');
      return p;
    } catch (_) {
      return null;
    }
  }

  static Future<void> playSaved({
    required bool enabled,
    required TxnType type,
  }) async {
    if (enabled) {
      try {
        if (type == TxnType.income) {
          _in ??= await _load('in_short.m4a');
          final p = _in;
          if (p != null) {
            await p.seek(Duration.zero);
            p.play(); // fire-and-forget; completes when the clip ends
          }
        } else {
          _out ??= await _load('out_short.m4a');
          final p = _out;
          if (p != null) {
            await p.seek(Duration.zero);
            p.play();
          }
        }
      } catch (_) {
        // Audio is best-effort; the save already succeeded.
      }
    }
    // A gentle haptic accompanies the sound (and stands in where audio can't
    // play). Guarded for the same reason.
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }
}
