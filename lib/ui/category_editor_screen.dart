import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import 'add_category_sheet.dart';
import 'theme/tokens.dart';
import 'widgets/category_icon_tile.dart';

class CategoryEditorScreen extends StatefulWidget {
  const CategoryEditorScreen({super.key});

  @override
  State<CategoryEditorScreen> createState() => _CategoryEditorScreenState();
}

class _CategoryEditorScreenState extends State<CategoryEditorScreen> {
  bool _showArchived = false;

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

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();

    return Scaffold(
      appBar: AppBar(title: const Text('الفئات')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => AddCategorySheet(db: db),
        ),
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
            // Single reactive stream for both views -- watchAll() covers
            // archived + active, so toggling the segmented control just
            // re-filters the latest snapshot instead of switching data
            // sources (keeps both views live, including after unarchive()).
            child: StreamBuilder<List<Category>>(
              stream: db.categoryDao.watchAll(),
              builder: (context, snapshot) {
                final all = snapshot.data ?? const <Category>[];
                final visible =
                    all.where((c) => c.archived == _showArchived).toList();

                if (visible.isEmpty) {
                  return Center(
                    child: Text(_showArchived
                        ? 'لا توجد فئات مؤرشفة'
                        : 'لا توجد فئات بعد'),
                  );
                }
                return ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  itemCount: visible.length,
                  itemBuilder: (context, i) {
                    final c = visible[i];
                    return ListTile(
                      leading: CategoryIconTile(iconKey: c.iconKey),
                      title: Text(c.name),
                      trailing: _showArchived
                          ? IconButton(
                              tooltip: 'إعادة تفعيل',
                              icon: const Icon(Icons.unarchive_outlined),
                              onPressed: () => db.categoryDao.unarchive(c.id),
                            )
                          : IconButton(
                              tooltip: 'أرشفة',
                              icon: const Icon(Icons.archive_outlined),
                              onPressed: () =>
                                  _confirmArchive(context, db, c),
                            ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
