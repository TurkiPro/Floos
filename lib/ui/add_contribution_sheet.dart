import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import 'theme/tokens.dart';

class AddContributionSheet extends StatefulWidget {
  final AppDatabase db;
  final int goalId;
  const AddContributionSheet({
    super.key,
    required this.db,
    required this.goalId,
  });

  @override
  State<AddContributionSheet> createState() => _AddContributionSheetState();
}

class _AddContributionSheetState extends State<AddContributionSheet> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل مبلغًا صحيحًا')),
      );
      return;
    }
    await widget.db.savingsDao.addContribution(
      goalId: widget.goalId,
      amount: amount,
      date: _date,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
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
            Text('إضافة إيداع', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _amountCtrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'المبلغ',
                suffixText: 'ر.س',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                    child: Text(
                        'التاريخ: ${DateFormat('yyyy-MM-dd').format(_date)}')),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2015),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                  child: const Text('تغيير'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'ملاحظة (اختياري)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: _save, child: const Text('حفظ')),
          ],
        ),
      ),
    );
  }
}
