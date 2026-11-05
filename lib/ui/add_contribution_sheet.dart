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
  // "External" means the money is outside the tracked balance, in either
  // direction:
  //  - an external DEPOSIT is money that already existed (a gift, savings held
  //    elsewhere): it raises the goal without coming out of the balance.
  //  - an external WITHDRAWAL is money that left savings for somewhere else (a
  //    purchase paid straight from the savings account, a transfer to an
  //    account this app does not track): it lowers the goal without landing in
  //    the balance.
  // The data layer already treats both the same way — every balance, savings
  // rate and behaviour figure skips external rows, and only the goal's own
  // total counts them — so this flag is the whole feature.
  bool _external = false;
  // A withdrawal is stored as a negative contribution: it lowers the goal's
  // balance and, unless external, flows back into the spendable balance.
  bool _withdraw = false;
  // Withdrawals only, and independent of [_external]: was this the goal being
  // used as intended, rather than dipping into savings? It decides whether the
  // withdrawal counts against the saving-habit stats. The two flags answer
  // different questions, so all four combinations are offered:
  //   back to balance, planned   — moved it back on purpose
  //   back to balance, unplanned — raided it to cover spending
  //   elsewhere, planned         — the car fund paid for the car
  //   elsewhere, unplanned       — raided it for something untracked
  bool _planned = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _goalId = e.goalId;
      _withdraw = e.amount < 0;
      _amountCtrl.text = groupedAmount(e.amount.abs());
      _date = e.date;
      _noteCtrl.text = e.note ?? '';
      _external = e.external;
      _planned = e.planned;
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
    final e = widget.existing;
    // A withdrawal can't pull out more than the goal currently holds.
    if (_withdraw) {
      final all = await widget.db.savingsDao.watchAllContributions().first;
      var goalTotal = 0.0;
      for (final c in all) {
        if (c.goalId != _goalId) continue;
        // Exclude the row we're editing (its new value replaces it).
        if (e != null && c.id == e.id) continue;
        goalTotal += c.amount;
      }
      if (amount > goalTotal) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'المبلغ أكبر من رصيد الهدف (${groupedAmount(goalTotal)} ⃁)')),
        );
        return;
      }
    }
    // Withdrawals are stored negative. Whether either direction touches the
    // balance is the external flag's job, for both.
    final signed = _withdraw ? -amount : amount;
    final external = _external;
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
    if (e != null) {
      await widget.db.savingsDao.updateContribution(
        e.id,
        goalId: _goalId!,
        amount: signed,
        date: _date,
        note: note,
        external: external,
        planned: _withdraw && _planned,
      );
    } else {
      await widget.db.savingsDao.addContribution(
        goalId: _goalId!,
        amount: signed,
        date: _date,
        note: note,
        external: external,
        planned: _withdraw && _planned,
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
            Text(
                widget.existing == null
                    ? (_withdraw ? 'سحب من الادخار' : 'إيداع في الادخار')
                    : 'تعديل الحركة',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            // Direction: deposit moves money into the goal; withdraw takes it
            // out. Whether the balance is involved is the toggle below.
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                    value: false,
                    label: Text('إيداع'),
                    icon: Icon(Icons.savings_outlined)),
                ButtonSegment(
                    value: true,
                    label: Text('سحب'),
                    icon: Icon(Icons.account_balance_wallet_outlined)),
              ],
              selected: {_withdraw},
              // Switching direction clears the external toggle. It means two
              // different things in the two modes ("money I already had" vs
              // "money that went elsewhere"), so a tick made for one must never
              // quietly carry over into the other.
              onSelectionChanged: (s) => setState(() {
                if (s.first != _withdraw) {
                  _external = false;
                  // Meaningless on a deposit; never let it ride along.
                  _planned = false;
                }
                _withdraw = s.first;
              }),
            ),
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
            // Shown in both directions, worded for the direction chosen.
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _external,
              onChanged: (v) => setState(() => _external = v),
              title: Text(_withdraw
                  ? 'سحب خارجي (لا يُضاف إلى الرصيد)'
                  : 'إيداع خارجي (لا يُخصم من الرصيد)'),
              subtitle: Text(_withdraw
                  ? 'صُرف من الادخار مباشرة أو نُقل لحساب آخر — يُخصم من '
                      'الهدف دون أن يدخل رصيدك.'
                  : 'مبلغ موجود مسبقًا أو هدية — يُضاف للهدف دون التأثير '
                      'على رصيدك.'),
            ),
            // The second, independent question — withdrawals only. Where the
            // money went is the toggle above; whether taking it was a lapse is
            // this one.
            if (_withdraw)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _planned,
                onChanged: (v) => setState(() => _planned = v),
                title: const Text('سحب مخطط له (لا يُحسب تراجعًا في الادخار)'),
                subtitle: const Text(
                    'استُخدم المال لهدفه، كأن يدفع صندوق السيارة ثمن السيارة — '
                    'لا يُحتسب ضمن سلوك الادخار ولا يقطع سلسلة التزامك.'),
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
