import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/enums.dart';
import '../theme/tokens.dart';
import 'category_icon_tile.dart';

/// Two-level category selector shared by every add-sheet. Shows top-level
/// categories of the given [type] as a grid; picking one that has
/// sub-categories reveals them as chips so the user can refine. The effective
/// selection ([selectedId]) is the sub-category when one is chosen, otherwise
/// the top-level category itself.
class CategoryPicker extends StatelessWidget {
  final AppDatabase db;
  final TxnType type;
  final int? selectedId;
  final ValueChanged<int> onChanged;

  const CategoryPicker({
    super.key,
    required this.db,
    required this.type,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Reactive, not a one-shot fetch: a category added while this sheet is
    // open shows up immediately instead of only on next open.
    return StreamBuilder<List<Category>>(
      stream: db.categoryDao.watchActive(),
      builder: (context, snapshot) {
        final cats = (snapshot.data ?? const <Category>[])
            .where((c) => c.type == type)
            .toList();
        if (cats.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text('لا توجد فئات بعد'),
          );
        }

        final tops = cats.where((c) => c.parentId == null).toList();
        Category? selected;
        for (final c in cats) {
          if (c.id == selectedId) {
            selected = c;
            break;
          }
        }
        // Which top-level row is "open": the selected leaf's parent, or the
        // selected top-level itself. Null until something is picked -- in that
        // case there are no sub-category chips to show (guarding against
        // `parentId == null` matching every top-level category).
        final expandedTopId =
            selected == null ? null : (selected.parentId ?? selected.id);
        final children = expandedTopId == null
            ? const <Category>[]
            : cats.where((c) => c.parentId == expandedTopId).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 0.8,
              children: [
                for (final c in tops)
                  GestureDetector(
                    onTap: () => onChanged(c.id),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CategoryIconTile(
                          iconKey: c.iconKey,
                          size: 48,
                          selected: c.id == expandedTopId,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: AppTextSizes.label),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (children.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'التصنيف الفرعي',
                style: TextStyle(
                    fontSize: AppTextSizes.label,
                    color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final c in children)
                    ChoiceChip(
                      label: Text(c.name),
                      selected: c.id == selectedId,
                      onSelected: (_) => onChanged(c.id),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
