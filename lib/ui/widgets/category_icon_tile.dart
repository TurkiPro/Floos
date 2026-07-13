import 'package:flutter/material.dart';

import '../icon_registry.dart';
import '../theme/tokens.dart';

/// Rounded-square tinted icon tile for a category: light fill + darker
/// icon, looked up by iconKey from the theme's CategoryTileColors
/// extension. Shared across the home transaction list, both add-sheets'
/// category grids, and the category editor list.
class CategoryIconTile extends StatelessWidget {
  final String iconKey;
  final double size;
  final bool selected;

  const CategoryIconTile({
    super.key,
    required this.iconKey,
    this.size = 40,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final pair =
        Theme.of(context).extension<CategoryTileColors>()?.byIconKey[iconKey] ??
            categoryTileColors.byIconKey['other']!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: pair.$1,
        borderRadius: BorderRadius.circular(AppRadii.tile),
        border: selected
            ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
            : null,
      ),
      child: Icon(iconForKey(iconKey), color: pair.$2, size: size * 0.5),
    );
  }
}
