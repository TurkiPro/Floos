import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_settings.dart';
import '../data/database.dart';
import '../domain/parse_amount.dart';
import '../services/alerts_coordinator.dart';
import 'theme/tokens.dart';
import 'widgets/amount_input.dart';

/// Records money coming back for a purchase — in full or in part.
///
/// The refund lands in the purchase's category, dated the day the money came
/// back: this week and this cycle get the headroom back, and finished cycles
/// are never rewritten. It is never income.
class RefundSheet extends StatefulWidget {
  final AppDatabase db;
  final Txn purchase;
  const RefundSheet({super.key, required this.db, required this.purchase});

  @override
  State<RefundSheet> createState() => _RefundSheetState();
}

class _RefundSheetState extends State<RefundSheet> {
  final _amount = TextEditingController();
  DateTime _date = DateTime.now();
  double? _left;

  @override
  void initState() {
    super.initState();
    widget.db.transactionDao.unrefunded(widget.purchase.id).then((left) {
      if (!mounted) return;
      setState(() {
        _left = left;
        // Most refunds are the whole thing; a partial one is one edit away.
        _amount.text = groupedAmount(left);
      });
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseAmount(_amount.text);
    final left = _left ?? 0;
    if (amount == null || amount <= 0 || amount - left >= 0.005) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('أدخل مبلغًا حتى ${groupedAmount(left)} ⃁'),
      ));
      return;
    }
    await widget.db.transactionDao.addRefund(
      purchaseId: widget.purchase.id,
      amount: amount,
      date: _date,
    );
    if (!mounted) return;
    refreshAlerts(widget.db, context.read<AppSettings>());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final left = _left;
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('تسجيل استرداد',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              [
                if ((widget.purchase.note ?? '').isNotEmpty)
                  widget.purchase.note!,
                'الشراء ${groupedAmount(widget.purchase.amount)} ⃁',
                if (left != null && left < widget.purchase.amount - 0.005)
                  'تبقّى ${groupedAmount(left)} ⃁',
              ].join('  •  '),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: const [ThousandsInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'المبلغ المسترد',
                suffixText: '⃁',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: widget.purchase.date,
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _date = picked);
              },
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text(
                  'تاريخ الاسترداد ${DateFormat('yyyy-MM-dd').format(_date)}'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'يُخصم من مصروف فئة الشراء في يوم الاسترداد، ولا يُحسب دخلًا.',
              style: TextStyle(
                fontSize: AppTextSizes.label,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: left == null || left < 0.005 ? null : _save,
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}
