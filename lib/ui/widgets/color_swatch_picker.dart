import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Curated, fixed swatch grid for picking a category color -- no new
/// color-picker package added (none requested, and a full HSV/RGB picker is
/// a bigger surface than this app needs). The first 15 are the original seed
/// categories' colors plus a few design-system accents; the rest widen the
/// palette so every category can hold its own distinct colour (see
/// [ColorSwatchPicker]'s used-colour enforcement) without running out.
const List<Color> categorySwatches = [
  Color(0xFFEF5350), // food (seed)
  Color(0xFF42A5F5), // transport (seed)
  Color(0xFFAB47BC), // shopping (seed)
  Color(0xFFFFCA28), // bills (seed)
  Color(0xFF26A69A), // health (seed)
  Color(0xFFEC407A), // entertainment (seed)
  Color(0xFF8D6E63), // home (seed)
  Color(0xFF78909C), // other (seed)
  Color(0xFF66BB6A), // salary (seed)
  Color(0xFF9CCC65), // extra_income (seed)
  Color(0xFF26C6DA), // investment (seed)
  AppColors.brand,
  Color(0xFF1B5E3A), // salary tile fg
  Color(0xFF0E6E52), // extra_income tile fg
  Color(0xFF105B73), // investment tile fg
  // Widened palette -- distinct hues spread around the wheel so a growing set
  // of categories can each stay unique.
  Color(0xFFD81B60), // magenta
  Color(0xFF8E24AA), // purple
  Color(0xFF5E35B1), // deep purple
  Color(0xFF3949AB), // indigo
  Color(0xFF1E88E5), // blue
  Color(0xFF039BE5), // sky
  Color(0xFF00897B), // teal
  Color(0xFF43A047), // green
  Color(0xFF7CB342), // lime green
  Color(0xFFC0CA33), // lime
  Color(0xFFFDD835), // yellow
  Color(0xFFFB8C00), // orange
  Color(0xFFF4511E), // deep orange
  Color(0xFF6D4C41), // dark brown
  Color(0xFF546E7A), // dark blue grey
];

/// The first swatch not already taken by another category, for defaulting a new
/// category to a distinct colour. Falls back to the first swatch when the whole
/// palette is in use.
Color firstFreeSwatch(Set<int> usedColors) {
  for (final c in categorySwatches) {
    if (!usedColors.contains(c.toARGB32())) return c;
  }
  return categorySwatches.first;
}

/// A grid of colour swatches. When [usedColors] (ARGB values already taken by
/// *other* categories) is non-empty, those swatches are dimmed and can't be
/// picked -- so every category ends up a distinct colour. The currently
/// [selected] colour is always pickable, even if it collides, so editing an
/// existing category never traps the user. If the whole palette is exhausted,
/// enforcement relaxes and every swatch becomes selectable again.
class ColorSwatchPicker extends StatelessWidget {
  final Color selected;
  final ValueChanged<Color> onChanged;
  final Set<int> usedColors;

  const ColorSwatchPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.usedColors = const {},
  });

  @override
  Widget build(BuildContext context) {
    final anyFree =
        categorySwatches.any((c) => !usedColors.contains(c.toARGB32()));
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final color in categorySwatches) _swatch(context, color, anyFree),
      ],
    );
  }

  Widget _swatch(BuildContext context, Color color, bool anyFree) {
    final isSelected = color.toARGB32() == selected.toARGB32();
    // Taken by another category: dimmed and locked out (unless it's the current
    // selection, or the palette is fully exhausted).
    final taken =
        !isSelected && anyFree && usedColors.contains(color.toARGB32());

    final dot = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: isSelected ? Border.all(color: Colors.white, width: 2.5) : null,
      ),
      child: isSelected
          ? const Icon(Icons.check, color: Colors.white, size: 18)
          : (taken
              ? const Icon(Icons.close, color: Colors.white70, size: 16)
              : null),
    );

    if (taken) {
      // Not tappable, visibly faded to read as "already used".
      return Opacity(opacity: 0.32, child: dot);
    }
    return GestureDetector(
      onTap: () => onChanged(color),
      child: dot,
    );
  }
}
