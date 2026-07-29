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
import 'widgets/amount_input.dart';
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
  // The sheet only ever adds expenses (income has its own page); [_type] is kept
  // only so editing an existing row preserves whatever type it already had.
  TxnType _type = TxnType.expense;
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  int? _categoryId;
  // The note is collapsed behind a chip until wanted — most entries have none,
  // so it shouldn't cost a permanent row and crowd the category picker.
  bool _showNote = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _type = e.type;
      _amountCtrl.text = groupedAmount(e.amount);
      _noteCtrl.text = e.note ?? '';
      _date = e.date;
      _categoryId = e.categoryId;
      _showNote = (e.note ?? '').isNotEmpty;
    }
  }

  /// Appends a "+" or "−" to the amount (or swaps a trailing one), so a few
  /// prices add up without leaving the number pad. parseAmount evaluates it.
  void _appendOp(String op) {
    final t = _amountCtrl.text;
    if (t.isEmpty) return; // never start with an operator
    final last = t.substring(t.length - 1);
    final next = (last == '+' || last == '-')
        ? t.substring(0, t.length - 1) + op
        : t + op;
    _amountCtrl.text = next;
    _amountCtrl.selection = TextSelection.collapsed(offset: next.length);
  }

  Widget _opButton(String op) {
    // '+' takes the app's accent colour (whatever the user picked); '−' is
    // always red — so add vs. subtract read at a glance. Borderless tinted
    // circles, so they sit on the amount as deliberate affordances rather than
    // boxed-on buttons. The glyph is a proper minus, but '-' (ASCII) is inserted.
    final minus = op == '-';
    final color =
        minus ? Colors.red.shade400 : Theme.of(context).colorScheme.primary;
    return Material(
      color: color.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _appendOp(minus ? '-' : '+'),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Center(
            child: Text(
              minus ? '−' : '+',
              style: TextStyle(
                fontSize: 22,
                height: 1,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  String _dateLabel() {
    final now = DateTime.now();
    final sameDay = _date.year == now.year &&
        _date.month == now.month &&
        _date.day == now.day;
    return sameDay ? 'اليوم' : DateFormat('yyyy-MM-dd').format(_date);
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Sized to its content, so the whole [amount + ops] group
                      // sits centred and the buttons stay right beside the digits.
                      IntrinsicWidth(
                        child: TextField(
                          controller: _amountCtrl,
                          autofocus: !_isEditing,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: const [ThousandsInputFormatter()],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: AppTextSizes.heroMin,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: const InputDecoration(
                            hintText: '0.00',
                            suffixText: '⃁',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      // Calculator operators hug the number (beside it, not below,
                      // to stay clear of the pad). '+' takes the accent, '−' red.
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _opButton('+'),
                          const SizedBox(height: AppSpacing.sm),
                          _opButton('-'),
                        ],
                      ),
                    ],
                  ),
                  // Live result while an expression is being entered.
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _amountCtrl,
                    builder: (context, value, _) {
                      final t = value.text;
                      if (!t.contains('+') && !t.contains('-')) {
                        return const SizedBox.shrink();
                      }
                      final v = parseAmount(t);
                      if (v == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          '= ${groupedAmount(v)} ⃁',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: AppTextSizes.label,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  CategoryPicker(
                    db: widget.db,
                    type: _type,
                    selectedId: _categoryId,
                    onChanged: (id) => setState(() => _categoryId = id),
                  ),
                ],
              ),
            ),
          ),
          // Date, note and the save button are pinned below the scroll area, so
          // the date can never end up hidden under the button when the keyboard
          // is up and the category picker fills the space above.
          Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm,
                AppSpacing.lg, AppSpacing.lg + safeBottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Date and note as compact chips, not two permanent rows — the
                // date is "today" almost always and the note is usually empty,
                // so they stay one tap away without crowding the picker above.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text(_dateLabel()),
                      style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    if (!_showNote)
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _showNote = true),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('ملاحظة'),
                        style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact),
                      ),
                  ],
                ),
                if (_showNote) ...[
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _noteCtrl,
                    autofocus: !_isEditing,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظة (اختياري)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: _save,
                  child: Text(_isEditing ? 'حفظ التعديلات' : 'حفظ'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
