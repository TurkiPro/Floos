import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/enums.dart';
import '../theme/tokens.dart';
import 'category_icon_tile.dart';

/// Two-pane (master-detail) category selector shared by every add-sheet. Main
/// categories scroll on the leading side (the right, in RTL); tapping one
/// selects it AND lists its sub-categories on the trailing side, where a sub
/// can refine the choice. Both panes scroll independently, so the picker keeps
/// a fixed footprint no matter how many categories are added over time.
///
/// The effective selection ([selectedId]) is the sub-category when one is
/// chosen, otherwise the top-level category itself — unchanged from before, so
/// this is a drop-in replacement for the old grid+chips picker.
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
    // open (including via the quick add-sub below) shows up immediately.
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
        // The "open" main: the selected leaf's parent, or the selected top-level
        // itself. Null until something is picked.
        final expandedTopId =
            selected == null ? null : (selected.parentId ?? selected.id);
        Category? activeTop;
        for (final t in tops) {
          if (t.id == expandedTopId) {
            activeTop = t;
            break;
          }
        }
        final children = expandedTopId == null
            ? const <Category>[]
            : cats.where((c) => c.parentId == expandedTopId).toList();

        return Container(
          height: 240,
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              // Main categories — leading side (right in RTL).
              Expanded(
                flex: 10,
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  children: [
                    for (final t in tops)
                      _MainRow(
                        category: t,
                        selected: t.id == expandedTopId,
                        onTap: () => onChanged(t.id),
                      ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              // Sub-categories of the active main — trailing side (left in RTL).
              Expanded(
                flex: 11,
                child: activeTop == null
                    ? Center(
                        child: Text('اختر فئة',
                            style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: AppTextSizes.label)),
                      )
                    : _SubsPane(
                        subs: children,
                        selectedId: selectedId,
                        onPick: onChanged,
                        onAddSub: () => _addSub(context, activeTop!),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Quick sub-category creation without leaving the sheet: a name field, the
  /// icon/colour/kind inherited from the parent (editable later in الفئات).
  /// The new sub is auto-selected so the flow continues in one step.
  Future<void> _addSub(BuildContext context, Category parent) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تصنيف فرعي في «${parent.name}»'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'الاسم'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final id = await db.categoryDao.add(
      name: name.trim(),
      iconKey: parent.iconKey,
      colorValue: parent.colorValue,
      type: parent.type,
      parentId: parent.id,
      kind: parent.kind,
    );
    onChanged(id); // auto-select the new sub
  }
}

/// One main-category row: a tinted icon tile + name, its background washed with
/// the category's own colour when active.
class _MainRow extends StatelessWidget {
  final Category category;
  final bool selected;
  final VoidCallback onTap;
  const _MainRow({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A translucent wash of the category's own colour — reads over both the
    // dark and light card while keeping the icon and text fully visible. (An
    // opaque pale tile fill made white dark-mode text disappear.)
    final bg =
        selected ? Color(category.colorValue).withValues(alpha: 0.20) : null;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
        child: Row(
          children: [
            CategoryIconTile(
                iconKey: category.iconKey,
                colorValue: category.colorValue,
                size: 30),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: AppTextSizes.label,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
              ),
            ),
            if (selected)
              Icon(Icons.check, size: 16, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// The sub-category pane for the active main: the sub rows, an empty-state
/// message when there are none, and a persistent quick "add sub" action.
class _SubsPane extends StatelessWidget {
  final List<Category> subs;
  final int? selectedId;
  final ValueChanged<int> onPick;
  final VoidCallback onAddSub;
  const _SubsPane({
    required this.subs,
    required this.selectedId,
    required this.onPick,
    required this.onAddSub,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      children: [
        if (subs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.md),
            child: Text('لا توجد تصنيفات فرعية',
                style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: AppTextSizes.label)),
          ),
        for (final s in subs)
          InkWell(
            onTap: () => onPick(s.id),
            child: Container(
              color: s.id == selectedId
                  ? scheme.primary.withValues(alpha: 0.12)
                  : null,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppTextSizes.label,
                        fontWeight: s.id == selectedId
                            ? FontWeight.w700
                            : FontWeight.normal,
                        color: s.id == selectedId ? scheme.primary : null,
                      ),
                    ),
                  ),
                  if (s.id == selectedId)
                    Icon(Icons.check, size: 16, color: scheme.primary),
                ],
              ),
            ),
          ),
        InkWell(
          onTap: onAddSub,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Row(
              children: [
                Icon(Icons.add, size: 18, color: scheme.primary),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text('إضافة تصنيف فرعي',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: scheme.primary, fontSize: AppTextSizes.label)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
