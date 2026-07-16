import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_settings.dart';
import '../data/database.dart';
import '../data/enums.dart';
import '../domain/parse_amount.dart';
import '../services/alerts_coordinator.dart';
import '../services/sound_service.dart';
import 'theme/tokens.dart';
import 'widgets/category_picker.dart';

class AddTransactionSheet extends StatefulWidget {
  final AppDatabase db;
  // null => add mode. Non-null => edit this existing transaction in place
  // (tap-to-edit), e.g. to correct the day a salary actually landed.
  final Txn? existing;
  const AddTransactionSheet({super.key, required this.db, this.existing});

  @override
  State<AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<AddTransactionSheet> {
  TxnType _type = TxnType.expense;
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  int? _categoryId;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _type = e.type;
      _amountCtrl.text = e.amount.toString();
      _noteCtrl.text = e.note ?? '';
      _date = e.date;
      _categoryId = e.categoryId;
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
    if (amount == null || amount <= 0 || _categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل مبلغًا صحيحًا واختر فئة')),
      );
      return;
    }
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
    if (_isEditing) {
      await widget.db.transactionDao.updateFields(
        id: widget.existing!.id,
        amount: amount,
        categoryId: _categoryId!,
        type: _type,
        date: _date,
        note: note,
      );
    } else {
      await widget.db.transactionDao.add(
        amount: amount,
        categoryId: _categoryId!,
        type: _type,
        date: _date,
        note: note,
      );
    }
    if (!mounted) return;
    final settings = context.read<AppSettings>();
    // The confirmation chime is for *adding* — editing shouldn't chime.
    if (!_isEditing) {
      SoundService.playSaved(enabled: settings.soundEnabled, type: _type);
    }
    // Keeps the weekly-budget badge in step with the changed spending.
    refreshAlerts(widget.db, settings);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    // Clear the home indicator with the button when the keyboard is down; when
    // it's up, the keyboard already covers that area.
    final safeBottom =
        insets > 0 ? 0.0 : MediaQuery.of(context).viewPadding.bottom;
    return Padding(
      // Lift the whole sheet above the keyboard; the fields scroll while the
      // save button below stays pinned, so it never hides behind the keyboard.
      padding: EdgeInsets.only(bottom: insets),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isEditing) ...[
                    Text('تعديل العملية',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  SegmentedButton<TxnType>(
                    segments: const [
                      ButtonSegment(
                          value: TxnType.expense, label: Text('مصروف')),
                      ButtonSegment(value: TxnType.income, label: Text('دخل')),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) => setState(() {
                      _type = s.first;
                      _categoryId = null;
                    }),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Center(
                    child: IntrinsicWidth(
                      child: TextField(
                        controller: _amountCtrl,
                        autofocus: !_isEditing,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: AppTextSizes.heroMin,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: const InputDecoration(
                          hintText: '0.00',
                          suffixText: 'ر.س',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
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
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm,
                AppSpacing.lg, AppSpacing.lg + safeBottom),
            child: FilledButton(
              onPressed: _save,
              child: Text(_isEditing ? 'حفظ التعديلات' : 'حفظ'),
            ),
          ),
        ],
      ),
    );
  }
}
