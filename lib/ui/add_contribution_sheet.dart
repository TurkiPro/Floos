import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../domain/parse_amount.dart';
import 'theme/tokens.dart';
import 'widgets/amount_input.dart';
import 'widgets/picker_field.dart';

/// Add or edit a deposit to a savings goal. When [existing] is given the sheet
/// opens in edit mode — prefilled, saving over the same row, with a delete
/// action. Otherwise it's an add: when [goalId] is null it shows a goal picker
/// (the savings screen's general "إيداع" action); otherwise it deposits straight
/// into the given goal. Every deposit can be dated and annotated with a note.
class AddContributionSheet extends StatefulWidget {
  final AppDatabase db;
  final int? goalId;
  final SavingsContribution? existing;
  const AddContributionSheet({
    super.key,
    required this.db,
    this.goalId,
    this.existing,
  });

  @override
  State<AddContributionSheet> createState() => _AddContributionSheetState();
}

class _AddContributionSheetState extends State<AddContributionSheet> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  int? _goalId;
  bool _external = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _goalId = e.goalId;
      _amountCtrl.text = groupedAmount(e.amount);
      _date = e.date;
      _noteCtrl.text = e.note ?? '';
      _external = e.external;
    } else {
      _goalId = widget.goalId;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseAmount(_amountCtrl.text);
    if (_goalId == null || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر هدفًا وأدخل مبلغًا صحيحًا')),
      );
      return;
    }
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
    final e = widget.existing;
    if (e != null) {
      await widget.db.savingsDao.updateContribution(
        e.id,
        goalId: _goalId!,
        amount: amount,
        date: _date,
        note: note,
        external: _external,
      );
    } else {
      await widget.db.savingsDao.addContribution(
        goalId: _goalId!,
        amount: amount,
        date: _date,
        note: note,
        external: _external,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final e = widget.existing;
    if (e == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await widget.db.savingsDao.deleteContribution(e.id);
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: const Text('تم حذف الإيداع'),
      action: SnackBarAction(
        label: 'تراجع',
        onPressed: () => widget.db.savingsDao.restoreContribution(e),
      ),
    ));
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
            Text(widget.existing == null ? 'إضافة إيداع' : 'تعديل الإيداع',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.lg),
            // Goal picker only when no goal was pre-selected.
            if (widget.goalId == null) ...[
              StreamBuilder<List<SavingsGoal>>(
                stream: widget.db.savingsDao.watchGoals(),
                builder: (context, snapshot) {
                  final goals = snapshot.data ?? const <SavingsGoal>[];
                  if (goals.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Text('لا توجد أهداف ادخار بعد'),
                    );
                  }
                  return PickerField<int>(
                    label: 'الهدف',
                    value: _goalId,
                    options: [
                      for (final g in goals) PickerOption(g.id, g.name),
                    ],
                    onChanged: (v) => setState(() => _goalId = v),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            TextField(
              controller: _amountCtrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: const [ThousandsInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'المبلغ',
                suffixText: '⃁',
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
                labelText: 'ملاحظة / المصدر (اختياري)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _external,
              onChanged: (v) => setState(() => _external = v),
              title: const Text('إيداع خارجي (لا يُخصم من الرصيد)'),
              subtitle: const Text(
                  'مبلغ موجود مسبقًا أو هدية — يُضاف للهدف دون التأثير على رصيدك.'),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: _save, child: const Text('حفظ')),
            if (widget.existing != null) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton.icon(
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text('حذف الإيداع',
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
