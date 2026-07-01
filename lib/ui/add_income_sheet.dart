import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../data/enums.dart';
import '../domain/recurrence_engine.dart';
import 'theme/tokens.dart';
import 'widgets/category_picker.dart';

/// Dedicated income-only add sheet. Every income added here is independently
/// named (so a user can have several distinct incomes -- "راتب", "عمل حر",
/// "إيجار عقار" -- each with its own amount/category/date), and can
/// optionally be made to repeat automatically every month. Finer scheduling
/// control (weekly/yearly, custom interval, end date) is deliberately not
/// exposed here -- that lives in the edit flow (AddRecurrenceSheet), reached
/// by tapping a recurring income in IncomeScreen after creation.
class AddIncomeSheet extends StatefulWidget {
  final AppDatabase db;
  const AddIncomeSheet({super.key, required this.db});

  @override
  State<AddIncomeSheet> createState() => _AddIncomeSheetState();
}

class _AddIncomeSheetState extends State<AddIncomeSheet> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  int? _categoryId;
  bool _recurring = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '.'));
    if (name.isEmpty || amount == null || amount <= 0 || _categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل اسمًا ومبلغًا صحيحًا واختر فئة')),
      );
      return;
    }
    if (_recurring) {
      await widget.db.recurrenceDao.add(
        title: name,
        amount: amount,
        categoryId: _categoryId!,
        type: TxnType.income,
        frequency: Frequency.monthly,
        interval: 1,
        startDate: _date,
        // insertGenerated() copies the rule's `note` (not `title`) onto each
        // materialized transaction -- without this, the name typed above
        // would only ever show up in the recurring-rule list, never on the
        // actual transaction rows it generates.
        note: name,
      );
      // Materializes today's occurrence immediately if due, instead of
      // waiting for the next launch/resume catch-up.
      await RecurrenceEngine(widget.db).catchUp();
    } else {
      await widget.db.transactionDao.add(
        amount: amount,
        categoryId: _categoryId!,
        type: TxnType.income,
        date: _date,
        note: name,
      );
    }
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
            Text('إضافة دخل',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'الاسم (مثال: راتب، عمل حر)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
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
            CategoryPicker(
              db: widget.db,
              type: TxnType.income,
              selectedId: _categoryId,
              onChanged: (id) => setState(() => _categoryId = id),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                    child: Text(_recurring
                        ? 'تاريخ التكرار: ${DateFormat('yyyy-MM-dd').format(_date)}'
                        : 'التاريخ: ${DateFormat('yyyy-MM-dd').format(_date)}')),
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('يتكرر كل شهر'),
              subtitle: const Text('سيتم إنشاؤه تلقائيًا كل شهر في نفس التاريخ'),
              value: _recurring,
              onChanged: (v) => setState(() => _recurring = v),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: _save, child: const Text('حفظ')),
          ],
        ),
      ),
    );
  }
}
