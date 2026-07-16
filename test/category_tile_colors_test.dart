import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:floos/ui/theme/tokens.dart';

void main() {
  group('categoryTilePair', () {
    test(
        'every category derives its pair from colorValue (no curated override)',
        () {
      // The whole point of the unified style: a color is turned into a
      // pale-bg/deep-fg pair regardless of icon — it must NOT jump to the old
      // hardcoded 'food' pair the way seeded icons used to.
      final pair = categoryTilePair(
        colorValue: 0xFF112233,
        brightness: Brightness.light,
      );
      expect(pair, isNot(categoryTileColors.byIconKey['food']));
      expect(HSLColor.fromColor(pair.$1).lightness, closeTo(0.93, 0.01));
      expect(HSLColor.fromColor(pair.$2).lightness, closeTo(0.28, 0.01));
    });

    test('derives a pale-bg / deep-fg pair from the color', () {
      final pair = categoryTilePair(
        colorValue: 0xFFEF5350,
        brightness: Brightness.light,
      );
      expect(pair, isNot(categoryTileColors.byIconKey['other']));
      expect(HSLColor.fromColor(pair.$1).lightness, closeTo(0.93, 0.01));
      expect(HSLColor.fromColor(pair.$2).lightness, closeTo(0.28, 0.01));
    });

    test('a null color falls back to the neutral pair', () {
      final pair = categoryTilePair(
        colorValue: null,
        brightness: Brightness.light,
      );
      expect(pair, categoryTileColors.byIconKey['other']);
    });

    test('dark mode derives a different pair than light for the same input',
        () {
      final light = categoryTilePair(
        colorValue: 0xFFEF5350,
        brightness: Brightness.light,
      );
      final dark = categoryTilePair(
        colorValue: 0xFFEF5350,
        brightness: Brightness.dark,
      );
      expect(dark, isNot(light));
      // Dark bg is dim, dark fg is bright.
      expect(HSLColor.fromColor(dark.$1).lightness, closeTo(0.16, 0.01));
      expect(HSLColor.fromColor(dark.$2).lightness, closeTo(0.72, 0.01));
    });
  });
}
