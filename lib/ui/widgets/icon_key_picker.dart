import 'package:flutter/material.dart';

import '../icon_registry.dart';
import '../theme/tokens.dart';
import 'category_icon_tile.dart';

/// 4-column grid over the full set of available icon keys. Shows all keys
/// regardless of the sheet's selected TxnType -- iconKey and type are
/// independent Category columns, nothing enforces an icon-to-type pairing
/// beyond the seed data's own convention.
class IconKeyPicker extends StatelessWidget {
  final String selectedKey;
  final ValueChanged<String> onChanged;

  const IconKeyPicker({
    super.key,
    required this.selectedKey,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.md,
      crossAxisSpacing: AppSpacing.md,
      children: [
        for (final key in availableIconKeys)
          GestureDetector(
            onTap: () => onChanged(key),
            child: CategoryIconTile(
              iconKey: key,
              size: 48,
              selected: key == selectedKey,
            ),
          ),
      ],
    );
  }
}
