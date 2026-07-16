import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../data/enums.dart';
import 'add_category_sheet.dart';
import 'theme/tokens.dart';
import 'widgets/category_icon_tile.dart';

class CategoryEditorScreen extends StatefulWidget {
  const CategoryEditorScreen({super.key});

  @override
  State<CategoryEditorScreen> createState() => _CategoryEditorScreenState();
}

enum _CatAction { edit, addSub, archive, unarchive }

class _CategoryEditorScreenState extends State<CategoryEditorScreen> {
  bool _showArchived = false;
  // Top-level categories start collapsed; ids the user has opened live here.
  final Set<int> _expanded = <int>{};

  Future<void> _confirmArchive(
      BuildContext context, AppDatabase db, Category c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('أرشفة الفئة؟'),
        content: Text(
            'سيتم إخفاء "${c.name}" من قوائم الاختيار. يمكنك إعادتها لاحقًا من عرض المؤرشفة.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('أرشفة'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await db.categoryDao.archive(c.id);
    }
  }

  void _openSheet(BuildContext context, AppDatabase db,
      {Category? existing, int? parentId, TxnType? fixedType}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddCategorySheet(
        db: db,
        existingCategory: existing,
        parentId: parentId,
        fixedType: fixedType,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();

    return Scaffold(
      appBar: AppBar(title: const Text('الفئات')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openSheet(context, db),
        icon: const Icon(Icons.add),
        label: const Text('فئة جديدة'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('نشطة')),
                ButtonSegment(value: true, label: Text('مؤرشفة')),
              ],
              selected: {_showArchived},
              onSelectionChanged: (s) =>
                  setState(() => _showArchived = s.first),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Category>>(
              stream: db.categoryDao.watchAll(),
              builder: (context, snapshot) {
                final all = snapshot.data ?? const <Category>[];
                if (_showArchived) {
                  return _archivedList(context, db, all);
                }
                return _activeTree(context, db, all);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _archivedList(
      BuildContext context, AppDatabase db, List<Category> all) {
    final archived = all.where((c) => c.archived).toList();
    if (archived.isEmpty) {
      return const Center(child: Text('لا توجد فئات مؤرشفة'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      itemCount: archived.length,
      itemBuilder: (context, i) {
        final c = archived[i];
        return ListTile(
          leading:
              CategoryIconTile(iconKey: c.iconKey, colorValue: c.colorValue),
          title: Text(c.name),
          trailing: IconButton(
            tooltip: 'إعادة تفعيل',
            icon: const Icon(Icons.unarchive_outlined),
            onPressed: () => db.categoryDao.unarchive(c.id),
          ),
        );
      },
    );
  }

  Widget _activeTree(BuildContext context, AppDatabase db, List<Category> all) {
    final active = all.where((c) => !c.archived).toList();
    final tops = active.where((c) => c.parentId == null).toList();
    if (tops.isEmpty) {
      return const Center(child: Text('لا توجد فئات بعد'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
      itemCount: tops.length,
      itemBuilder: (context, i) {
        final top = tops[i];
        final children = active.where((c) => c.parentId == top.id).toList();
        final expanded = _expanded.contains(top.id);
        return Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Column(
            children: [
              _row(context, db, top,
                  isSub: false,
                  subCount: children.length,
                  expanded: expanded,
                  onToggle: children.isEmpty
                      ? null
                      : () => setState(() {
                            if (expanded) {
                              _expanded.remove(top.id);
                            } else {
                              _expanded.add(top.id);
                            }
                          })),
              if (expanded)
                for (final child in children) ...[
                  const Divider(height: 1, indent: AppSpacing.xxl),
                  _row(context, db, child, isSub: true),
                ],
            ],
          ),
        );
      },
    );
  }

  Widget _row(BuildContext context, AppDatabase db, Category c,
      {required bool isSub,
      int subCount = 0,
      bool expanded = false,
      VoidCallback? onToggle}) {
    // A top-level row with sub-categories toggles them open/closed; tapping the
    // body expands, the chevron mirrors the state. Sub rows and childless tops
    // have no toggle.
    final expenseKind = c.type == TxnType.expense
        ? (c.kind == CategoryKind.essential ? 'أساسيات' : 'كماليات')
        : null;
    final subtitleText = [
      if (expenseKind != null) expenseKind,
      if (!isSub && subCount > 0) '$subCount تصنيفات فرعية',
    ].join('  •  ');
    return ListTile(
      onTap: onToggle,
      contentPadding: EdgeInsets.only(
        left: AppSpacing.md,
        right: isSub ? AppSpacing.xxl : AppSpacing.md,
      ),
      leading: CategoryIconTile(
          iconKey: c.iconKey, colorValue: c.colorValue, size: isSub ? 32 : 40),
      title: Text(c.name),
      subtitle: subtitleText.isEmpty
          ? null
          : Text(subtitleText,
              style: const TextStyle(fontSize: AppTextSizes.label)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onToggle != null)
            Icon(expanded ? Icons.expand_less : Icons.expand_more,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          _rowMenu(context, db, c, isSub: isSub),
        ],
      ),
    );
  }

  Widget _rowMenu(BuildContext context, AppDatabase db, Category c,
      {required bool isSub}) {
    return PopupMenuButton<_CatAction>(
      onSelected: (action) {
        switch (action) {
          case _CatAction.edit:
            _openSheet(context, db, existing: c);
            break;
          case _CatAction.addSub:
            _openSheet(context, db, parentId: c.id, fixedType: c.type);
            break;
          case _CatAction.archive:
            _confirmArchive(context, db, c);
            break;
          case _CatAction.unarchive:
            db.categoryDao.unarchive(c.id);
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: _CatAction.edit, child: Text('تعديل')),
        if (!isSub)
          const PopupMenuItem(
              value: _CatAction.addSub, child: Text('إضافة تصنيف فرعي')),
        const PopupMenuItem(value: _CatAction.archive, child: Text('أرشفة')),
      ],
    );
  }
}
