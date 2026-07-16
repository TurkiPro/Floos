import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:floos/ui/theme/tokens.dart';

void main() {
  group('categoryTilePair', () {
    test('a seeded icon key returns its curated pair (colorValue ignored)', () {
      final pair = categoryTilePair(
        iconKey: 'food',
        colorValue: 0xFF112233,
        brightness: Brightness.light,
      );
      expect(pair, categoryTileColors.byIconKey['food']);
    });

    test('a non-seed key derives a pale-bg / deep-fg pair from the color', () {
      final pair = categoryTilePair(
        iconKey: 'local_cafe',
        colorValue: 0xFFEF5350,
        brightness: Brightness.light,
      );
      expect(pair, isNot(categoryTileColors.byIconKey['other']));
      expect(HSLColor.fromColor(pair.$1).lightness, closeTo(0.93, 0.01));
      expect(HSLColor.fromColor(pair.$2).lightness, closeTo(0.28, 0.01));
    });

    test('a non-seed key with no color falls back to the neutral pair', () {
      final pair = categoryTilePair(
        iconKey: 'local_cafe',
        colorValue: null,
        brightness: Brightness.light,
      );
      expect(pair, categoryTileColors.byIconKey['other']);
    });

    test('dark mode derives a different pair than light for the same input',
        () {
      final light = categoryTilePair(
        iconKey: 'local_cafe',
        colorValue: 0xFFEF5350,
        brightness: Brightness.light,
      );
      final dark = categoryTilePair(
        iconKey: 'local_cafe',
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
