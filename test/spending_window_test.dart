import 'package:flutter_test/flutter_test.dart';
import 'package:floos/domain/spending_window.dart';

void main() {
  final today = DateTime(2026, 7, 15);

  group('weeklySpend', () {
    test('recommended = essential/weeks + luxury/weeks * 0.85', () {
      // Earliest 14 days ago => windowDays 14 => weeks 2.
      final w = weeklySpend(
        essentialWindow: 300,
        luxuryWindow: 400,
        earliestInWindow: today.subtract(const Duration(days: 13)),
        today: today,
      );
      // 300/2 + (400/2)*0.85 = 150 + 170.
      expect(w.recommended, closeTo(320, 1e-9));
    });

    test('pace ignores the discretionary discount', () {
      final w = weeklySpend(
        essentialWindow: 300,
        luxuryWindow: 400,
        earliestInWindow: today.subtract(const Duration(days: 13)),
        today: today,
      );
      // (300 + 400) / 2.
      expect(w.pace, closeTo(350, 1e-9));
    });

    test('weeks clamps to 1 for a sub-week window', () {
      final w = weeklySpend(
        essentialWindow: 100,
        luxuryWindow: 0,
        earliestInWindow: today.subtract(const Duration(days: 2)),
        today: today,
      );
      expect(w.recommended, closeTo(100, 1e-9)); // /1
    });

    test('weeks clamps to 12 for a window older than 84 days', () {
      final w = weeklySpend(
        essentialWindow: 1200,
        luxuryWindow: 0,
        earliestInWindow: today.subtract(const Duration(days: 200)),
        today: today,
      );
      expect(w.recommended, closeTo(100, 1e-9)); // 1200 / 12
    });

    test('no expenses in window => weeks 1, no divide-by-zero', () {
      final w = weeklySpend(
        essentialWindow: 0,
        luxuryWindow: 0,
        earliestInWindow: null,
        today: today,
      );
      expect(w.recommended, 0);
      expect(w.pace, 0);
    });
  });
}
