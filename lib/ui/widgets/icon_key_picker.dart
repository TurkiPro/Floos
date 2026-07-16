import 'package:flutter/material.dart';

import '../icon_registry.dart';
import '../theme/tokens.dart';
import 'category_icon_tile.dart';

/// Scrollable, grouped icon picker: each themed group (طعام، مواصلات، …) is a
/// labelled section of tinted icon tiles. Capped in height so it sits inside
/// a bottom sheet without eating the whole screen.
class IconKeyPicker extends StatelessWidget {
  final String selectedKey;
  final ValueChanged<String> onChanged;
  // The color currently chosen in the editor sheet, so a non-seed icon's
  // preview tile matches what will be saved.
  final int? colorValue;

  const IconKeyPicker({
    super.key,
    required this.selectedKey,
    required this.onChanged,
    this.colorValue,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 260,
      child: ListView(
        children: [
          for (final group in iconGroups) ...[
            Padding(
              padding: const EdgeInsets.only(
                  top: AppSpacing.sm, bottom: AppSpacing.sm),
              child: Text(
                group.label,
                style: TextStyle(
                  fontSize: AppTextSizes.label,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                for (final key in group.keys)
                  GestureDetector(
                    onTap: () => onChanged(key),
                    child: CategoryIconTile(
                      iconKey: key,
                      colorValue: colorValue,
                      size: 46,
                      selected: key == selectedKey,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}
