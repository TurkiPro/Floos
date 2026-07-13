import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/enums.dart';
import 'icon_registry.dart';
import 'theme/tokens.dart';
import 'widgets/color_swatch_picker.dart';
import 'widgets/icon_key_picker.dart';

/// Create/edit a category or sub-category.
/// - [existingCategory] set => edit mode (name/icon/color/kind only).
/// - [parentId]/[fixedType] set => creating a sub-category under that parent
///   (type is inherited, no expense/income toggle).
class AddCategorySheet extends StatefulWidget {
  final AppDatabase db;
  final Category? existingCategory;
  final int? parentId;
  final TxnType? fixedType;

  const AddCategorySheet({
    super.key,
    required this.db,
    this.existingCategory,
    this.parentId,
    this.fixedType,
  });

  @override
  State<AddCategorySheet> createState() => _AddCategorySheetState();
}

class _AddCategorySheetState extends State<AddCategorySheet> {
  final _nameCtrl = TextEditingController();
  TxnType _type = TxnType.expense;
  String _iconKey = availableIconKeys.first;
  Color _color = categorySwatches.first;
  CategoryKind _kind = CategoryKind.essential;

  bool get _isEditing => widget.existingCategory != null;
  bool get _isSub => widget.parentId != null;

  @override
  void initState() {
    super.initState();
    final c = widget.existingCategory;
    if (c != null) {
      _nameCtrl.text = c.name;
      _type = c.type;
      _iconKey = c.iconKey;
      _color = Color(c.colorValue);
      _kind = c.kind;
    } else if (widget.fixedType != null) {
      _type = widget.fixedType!;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل اسم الفئة')),
      );
      return;
    }
    if (_isEditing) {
      await widget.db.categoryDao.updateCategory(
        id: widget.existingCategory!.id,
        name: name,
        iconKey: _iconKey,
        colorValue: _color.toARGB32(),
        kind: _kind,
      );
    } else {
      // Computed fresh at save time (not a literal 0) so the new category
      // appends after every existing one under ORDER BY sortOrder ASC.
      final existing = await widget.db.categoryDao.getAll();
      await widget.db.categoryDao.add(
        name: name,
        iconKey: _iconKey,
        colorValue: _color.toARGB32(),
        type: _type,
        parentId: widget.parentId,
        kind: _kind,
        sortOrder: existing.length,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final title =
        _isEditing ? 'تعديل الفئة' : (_isSub ? 'تصنيف فرعي جديد' : 'فئة جديدة');

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'اسم الفئة',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Type is fixed for sub-categories (inherited) and when editing.
            if (!_isEditing && !_isSub) ...[
              SegmentedButton<TxnType>(
                segments: const [
                  ButtonSegment(value: TxnType.expense, label: Text('مصروف')),
                  ButtonSegment(value: TxnType.income, label: Text('دخل')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            // Essentials/luxuries only applies to spending.
            if (_type == TxnType.expense) ...[
              SegmentedButton<CategoryKind>(
                segments: const [
                  ButtonSegment(
                      value: CategoryKind.essential, label: Text('أساسيات')),
                  ButtonSegment(
                      value: CategoryKind.luxury, label: Text('كماليات')),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            Text('الأيقونة', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppSpacing.sm),
            IconKeyPicker(
              selectedKey: _iconKey,
              onChanged: (key) => setState(() => _iconKey = key),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('اللون', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppSpacing.sm),
            ColorSwatchPicker(
              selected: _color,
              onChanged: (color) => setState(() => _color = color),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _save,
              child: Text(_isEditing ? 'حفظ التعديلات' : 'حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}
