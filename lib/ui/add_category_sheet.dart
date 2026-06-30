import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/enums.dart';
import 'icon_registry.dart';
import 'theme/tokens.dart';
import 'widgets/color_swatch_picker.dart';
import 'widgets/icon_key_picker.dart';

class AddCategorySheet extends StatefulWidget {
  final AppDatabase db;
  const AddCategorySheet({super.key, required this.db});

  @override
  State<AddCategorySheet> createState() => _AddCategorySheetState();
}

class _AddCategorySheetState extends State<AddCategorySheet> {
  final _nameCtrl = TextEditingController();
  TxnType _type = TxnType.expense;
  String _iconKey = availableIconKeys.first;
  Color _color = categorySwatches.first;

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
    // Computed fresh at save time (not a literal 0) so the new category
    // appends after every existing one under ORDER BY sortOrder ASC,
    // instead of jumping to the front.
    final existing = await widget.db.categoryDao.getAll();
    await widget.db.categoryDao.add(
      name: name,
      iconKey: _iconKey,
      colorValue: _color.toARGB32(),
      type: _type,
      sortOrder: existing.length,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
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
            Text('فئة جديدة', style: Theme.of(context).textTheme.titleMedium),
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
            SegmentedButton<TxnType>(
              segments: const [
                ButtonSegment(value: TxnType.expense, label: Text('مصروف')),
                ButtonSegment(value: TxnType.income, label: Text('دخل')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: AppSpacing.lg),
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
            FilledButton(onPressed: _save, child: const Text('حفظ')),
          ],
        ),
      ),
    );
  }
}
