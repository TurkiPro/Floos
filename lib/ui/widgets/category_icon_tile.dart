import 'package:flutter/material.dart';

import '../icon_registry.dart';
import '../theme/tokens.dart';

/// Rounded-square tinted icon tile for a category: light fill + darker
/// icon, looked up by iconKey from the theme's CategoryTileColors
/// extension. Shared across the home transaction list, both add-sheets'
/// category grids, and the category editor list.
class CategoryIconTile extends StatelessWidget {
  final String iconKey;
  // Category.colorValue; null keeps the icon-key-only lookup (curated pairs or
  // the neutral fallback). When set, non-seed icons tint from the user's color.
  final int? colorValue;
  final double size;
  final bool selected;

  const CategoryIconTile({
    super.key,
    required this.iconKey,
    this.colorValue,
    this.size = 40,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final pair = categoryTilePair(
      colorValue: colorValue,
      brightness: Theme.of(context).brightness,
    );
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: pair.$1,
        borderRadius: BorderRadius.circular(AppRadii.tile),
        border: selected
            ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
            : null,
      ),
      // An emoji icon renders as text (it carries its own colours); a built-in
      // key renders as a tinted Material glyph.
      child: isEmojiIconKey(iconKey)
          ? Text(emojiFromKey(iconKey), style: TextStyle(fontSize: size * 0.5))
          : Icon(iconForKey(iconKey), color: pair.$2, size: size * 0.5),
    );
  }
}
