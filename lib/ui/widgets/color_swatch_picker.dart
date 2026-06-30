import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Curated, fixed swatch grid for picking a category color -- no new
/// color-picker package added (none requested, and a full HSV/RGB picker is
/// a bigger surface than this app needs). Reuses the existing seed
/// categories' colors plus a few design-system accents, all already
/// proven legible against the tile-tint treatment.
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
];

class ColorSwatchPicker extends StatelessWidget {
  final Color selected;
  final ValueChanged<Color> onChanged;

  const ColorSwatchPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final color in categorySwatches)
          GestureDetector(
            onTap: () => onChanged(color),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: color == selected
                    ? Border.all(color: Colors.white, width: 2.5)
                    : null,
              ),
              child: color == selected
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : null,
            ),
          ),
      ],
    );
  }
}
