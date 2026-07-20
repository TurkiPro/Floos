import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../domain/parse_amount.dart';
import 'theme/tokens.dart';
import 'widgets/amount_input.dart';

/// Add or edit an investment entry — a name and the amount put in. A standalone
/// (external) entry is pre-existing money invested outside the app, so it
/// doesn't come out of the balance; otherwise it's money moved from the balance
/// into the portfolio (not counted as spending).
class AddInvestmentSheet extends StatefulWidget {
  final AppDatabase db;
  final Investment? existing;
  const AddInvestmentSheet({super.key, required this.db, this.existing});

  @override
  State<AddInvestmentSheet> createState() => _AddInvestmentSheetState();
}

class _AddInvestmentSheetState extends State<AddInvestmentSheet> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  bool _external = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _amountCtrl.text = groupedAmount(e.amount);
      _noteCtrl.text = e.note ?? '';
      _date = e.date;
      _external = e.external;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final amount = parseAmount(_amountCtrl.text);
    if (name.isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل اسم الاستثمار ومبلغًا صحيحًا')),
      );
      return;
    }
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
    final e = widget.existing;
    if (e != null) {
      await widget.db.investmentDao.updateInvestment(
        e.id,
        name: name,
        amount: amount,
        date: _date,
        note: note,
        external: _external,
      );
    } else {
      await widget.db.investmentDao.add(
        name: name,
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
    await widget.db.investmentDao.deleteInvestment(e.id);
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: const Text('تم حذف الاستثمار'),
      action: SnackBarAction(
        label: 'تراجع',
        onPressed: () => widget.db.investmentDao.restore(e),
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
            Text(widget.existing == null ? 'استثمار جديد' : 'تعديل الاستثمار',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'الاسم (سهم، صندوق، محفظة…)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: const [ThousandsInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'المبلغ المستثمَر',
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
                labelText: 'ملاحظة (اختياري)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _external,
              onChanged: (v) => setState(() => _external = v),
              title: const Text('مبلغ مستقل (لا يُخصم من الرصيد)'),
              subtitle: const Text(
                  'استثمار موجود مسبقًا خارج التطبيق — يُسجَّل دون التأثير على رصيدك.'),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: _save, child: const Text('حفظ')),
            if (widget.existing != null) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton.icon(
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text('حذف الاستثمار',
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
