import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import 'theme/tokens.dart';

class AddGoalSheet extends StatefulWidget {
  final AppDatabase db;
  const AddGoalSheet({super.key, required this.db});

  @override
  State<AddGoalSheet> createState() => _AddGoalSheetState();
}

class _AddGoalSheetState extends State<AddGoalSheet> {
  final _nameCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  DateTime? _targetDate;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final target = double.tryParse(_targetCtrl.text.replaceAll(',', '.'));
    if (name.isEmpty || target == null || target <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل اسمًا ومبلغ هدف صحيح')),
      );
      return;
    }
    await widget.db.savingsDao.addGoal(
      name: name,
      targetAmount: target,
      targetDate: _targetDate,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy-MM-dd');
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
            Text('هدف ادخار جديد',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'اسم الهدف (مثال: رحلة)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _targetCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'المبلغ المستهدف',
                suffixText: 'ر.س',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(_targetDate == null
                      ? 'بدون تاريخ مستهدف'
                      : 'بحلول: ${fmt.format(_targetDate!)}'),
                ),
                if (_targetDate != null)
                  TextButton(
                    onPressed: () => setState(() => _targetDate = null),
                    child: const Text('إزالة'),
                  ),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _targetDate ?? DateTime.now(),
                      firstDate: DateTime(2015),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _targetDate = picked);
                  },
                  child: const Text('تحديد'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: _save, child: const Text('حفظ')),
          ],
        ),
      ),
    );
  }
}
