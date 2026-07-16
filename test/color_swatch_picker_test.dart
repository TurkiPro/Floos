import 'package:flutter_test/flutter_test.dart';
import 'package:floos/ui/widgets/color_swatch_picker.dart';

void main() {
  test('firstFreeSwatch returns the first unused swatch', () {
    expect(firstFreeSwatch(const {}).toARGB32(),
        categorySwatches.first.toARGB32());

    // First swatch taken -> falls through to the second.
    final firstUsed = {categorySwatches.first.toARGB32()};
    expect(
        firstFreeSwatch(firstUsed).toARGB32(), categorySwatches[1].toARGB32());
  });

  test('firstFreeSwatch falls back to the first swatch when all are used', () {
    final allUsed = {for (final c in categorySwatches) c.toARGB32()};
    expect(
        firstFreeSwatch(allUsed).toARGB32(), categorySwatches.first.toARGB32());
  });

  test('every swatch in the palette is distinct', () {
    final values = {for (final c in categorySwatches) c.toARGB32()};
    expect(values.length, categorySwatches.length,
        reason: 'duplicate swatches would defeat unique-colour enforcement');
  });
}
