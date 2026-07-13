import 'package:app_badge_plus/app_badge_plus.dart';

/// Shows the remaining weekly budget on the app icon in place of an unread
/// count. Only some platforms/launchers support a numeric badge, so every call
/// is guarded, and we skip the platform round-trip when the value hasn't moved.
class BadgeService {
  static int? _last;

  static Future<void> setWeeklyBudget(int amount) async {
    if (_last == amount) return;
    _last = amount;
    try {
      if (await AppBadgePlus.isSupported()) {
        await AppBadgePlus.updateBadge(amount);
      }
    } catch (_) {
      // Badge is decorative; never let it surface as an error.
    }
  }

  static Future<void> clear() async {
    _last = 0;
    try {
      if (await AppBadgePlus.isSupported()) {
        await AppBadgePlus.updateBadge(0);
      }
    } catch (_) {}
  }
}
