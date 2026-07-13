import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../data/enums.dart';
import '../domain/recurrence_engine.dart';
import '../domain/recurrence_math.dart' show dateOnly;
import 'recurring_screen.dart' show frequencyLabelAr;
import 'theme/tokens.dart';
import 'widgets/category_picker.dart';

class AddRecurrenceSheet extends StatefulWidget {
  final AppDatabase db;
  // null => create mode. Non-null => pre-fill and edit this rule instead.
  final RecurrenceRule? existingRule;
  // When set (create mode only), forces the type and hides the toggle -- used
  // by the monthly-obligations page to create expense-only rules.
  final TxnType? lockedType;
  const AddRecurrenceSheet({
    super.key,
    required this.db,
    this.existingRule,
    this.lockedType,
  });

  @override
  State<AddRecurrenceSheet> createState() => _AddRecurrenceSheetState();
}

class _AddRecurrenceSheetState extends State<AddRecurrenceSheet> {
  TxnType _type = TxnType.expense;
  Frequency _frequency = Frequency.monthly;
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _intervalCtrl = TextEditingController(text: '1');
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  int? _categoryId;

  bool get _isEditing => widget.existingRule != null;
  // Hide the expense/income toggle when editing (type is fixed) or when the
  // caller locked it.
  bool get _typeLocked => _isEditing || widget.lockedType != null;

  @override
  void initState() {
    super.initState();
    final rule = widget.existingRule;
    if (rule != null) {
      _type = rule.type;
      _frequency = rule.frequency;
      _titleCtrl.text = rule.title;
      _amountCtrl.text = rule.amount.toString();
      _intervalCtrl.text = rule.interval.toString();
      _startDate = rule.startDate;
      _endDate = rule.endDate;
      _categoryId = rule.categoryId;
    } else if (widget.lockedType != null) {
      _type = widget.lockedType!;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    _intervalCtrl.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final isIncome = _type == TxnType.income;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isIncome ? 'حذف الدخل المتكرر؟' : 'حذف القاعدة المتكررة؟'),
        content: const Text(
            'لن يتم حذف الحركات التي تم إنشاؤها سابقًا، لكن لن يتم إنشاء المزيد منها.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.db.recurrenceDao.deleteById(widget.existingRule!.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '.'));
    final interval = int.tryParse(_intervalCtrl.text) ?? 1;
    final title = _titleCtrl.text.trim();
    if (title.isEmpty || amount == null || amount <= 0 || _categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل اسمًا ومبلغًا صحيحًا واختر فئة')),
      );
      return;
    }
    final normalizedInterval = interval < 1 ? 1 : interval;
    if (!_isEditing) {
      await widget.db.recurrenceDao.add(
        title: title,
        amount: amount,
        categoryId: _categoryId!,
        type: _type,
        frequency: _frequency,
        interval: normalizedInterval,
        startDate: _startDate,
        endDate: _endDate,
      );
    } else {
      final old = widget.existingRule!;
      // Never backfill under a schedule the rule didn't have yet: only reset
      // the catch-up marker to today when the schedule itself changed
      // (mirrors reactivate()'s existing philosophy). Cosmetic-only edits
      // (amount/category/end date/etc) leave prior catch-up progress intact.
      final scheduleChanged = old.frequency != _frequency ||
          old.interval != normalizedInterval ||
          dateOnly(old.startDate) != dateOnly(_startDate);
      await widget.db.recurrenceDao.editRule(
        id: old.id,
        title: title,
        amount: amount,
        categoryId: _categoryId!,
        frequency: _frequency,
        interval: normalizedInterval,
        startDate: _startDate,
        endDate: _endDate,
        clearEndDate: _endDate == null && old.endDate != null,
        resetMarkerToToday: scheduleChanged,
      );
    }
    // Catch up immediately so a rule whose start date is already in the past
    // materializes its due occurrences now, instead of waiting for a relaunch.
    await RecurrenceEngine(widget.db).catchUp();
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
            // Type is fixed after creation (changing it would misrepresent
            // transactions already generated under the old type) and when the
            // caller locked it, so the toggle only appears for free creation.
            if (!_typeLocked) ...[
              SegmentedButton<TxnType>(
                segments: const [
                  ButtonSegment(value: TxnType.expense, label: Text('مصروف')),
                  ButtonSegment(value: TxnType.income, label: Text('دخل')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() {
                  _type = s.first;
                  _categoryId = null;
                }),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'الاسم (مثال: الإيجار)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _amountCtrl,
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
              type: _type,
              selectedId: _categoryId,
              onChanged: (id) => setState(() => _categoryId = id),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<Frequency>(
                    initialValue: _frequency,
                    decoration: const InputDecoration(
                      labelText: 'التكرار',
                      border: OutlineInputBorder(),
                    ),
                    items: Frequency.values
                        .map((f) => DropdownMenuItem(
                              value: f,
                              child: Text(frequencyLabelAr(f)),
                            ))
                        .toList(),
                    onChanged: (f) =>
                        setState(() => _frequency = f ?? _frequency),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _intervalCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'كل',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(child: Text('يبدأ: ${fmt.format(_startDate)}')),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _startDate,
                      firstDate: DateTime(2015),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _startDate = picked);
                  },
                  child: const Text('تغيير'),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(_endDate == null
                      ? 'بدون تاريخ انتهاء'
                      : 'ينتهي: ${fmt.format(_endDate!)}'),
                ),
                if (_endDate != null)
                  TextButton(
                    onPressed: () => setState(() => _endDate = null),
                    child: const Text('إزالة'),
                  ),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _endDate ?? _startDate,
                      firstDate: _startDate,
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _endDate = picked);
                  },
                  child: const Text('تحديد'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _save,
              child: Text(_isEditing ? 'حفظ التعديلات' : 'حفظ'),
            ),
            if (_isEditing) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: _delete,
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child:
                    Text(_type == TxnType.income ? 'حذف الدخل' : 'حذف القاعدة'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
