import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_settings.dart';
import '../data/database.dart';
import '../data/enums.dart';
import '../domain/parse_amount.dart';
import '../services/alerts_coordinator.dart';
import 'theme/tokens.dart';
import 'widgets/amount_input.dart';
import 'widgets/category_picker.dart';

/// Splits one purchase across categories — 420 at Panda as 300 groceries and
/// 120 household — or edits a purchase that is already split.
///
/// The first part always takes what is left, so the parts add up to the
/// purchase by construction: a split re-files money, it never changes how
/// much was spent. Date and note belong to the purchase and apply to every
/// part.
class SplitSheet extends StatefulWidget {
  final AppDatabase db;

  /// Any row of the purchase: the row being split, or any part of a split.
  final int txnId;
  const SplitSheet({super.key, required this.db, required this.txnId});

  @override
  State<SplitSheet> createState() => _SplitSheetState();
}

class _Part {
  final TextEditingController amount;
  int? categoryId;
  _Part({String text = '', this.categoryId})
      : amount = TextEditingController(text: text);
}

class _SplitSheetState extends State<SplitSheet> {
  bool _loaded = false;
  bool _wasSplit = false;
  bool _saving = false;
  double _total = 0;
  DateTime _date = DateTime.now();
  final _note = TextEditingController();

  /// [_parts.first] is the remainder; its controller is unused.
  final _parts = <_Part>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await widget.db.transactionDao.splitParts(widget.txnId);
    if (!mounted) return;
    setState(() {
      _wasSplit = rows.first.splitGroupId != null;
      _total = rows.fold(0, (s, r) => s + r.amount);
      _date = rows.first.date;
      _note.text = rows.first.note ?? '';
      _parts.add(_Part(categoryId: rows.first.categoryId));
      if (_wasSplit) {
        for (final r in rows.skip(1)) {
          _parts.add(
              _Part(text: groupedAmount(r.amount), categoryId: r.categoryId));
        }
      } else {
        _parts.add(_Part());
      }
      _loaded = true;
    });
  }

  @override
  void dispose() {
    for (final p in _parts) {
      p.amount.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  double _amountOf(_Part p) => parseAmount(p.amount.text) ?? 0;

  double get _remainder =>
      _total - _parts.skip(1).fold<double>(0, (s, p) => s + _amountOf(p));

  bool get _valid =>
      _remainder >= 0.01 &&
      _parts.every((p) => p.categoryId != null) &&
      _parts.skip(1).every((p) => _amountOf(p) > 0);

  Future<void> _pickCategory(_Part part) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: CategoryPicker(
            db: widget.db,
            type: TxnType.expense,
            selectedId: part.categoryId,
            onChanged: (id) => Navigator.of(sheetContext).pop(id),
          ),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => part.categoryId = picked);
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

  Future<void> _save() async {
    setState(() => _saving = true);
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    await widget.db.transactionDao.saveSplit(
      widget.txnId,
      parts: [
        (amount: _remainder, categoryId: _parts.first.categoryId!),
        for (final p in _parts.skip(1))
          (amount: _amountOf(p), categoryId: p.categoryId!),
      ],
      date: _date,
      note: note,
    );
    _done();
  }

  Future<void> _unsplit() async {
    setState(() => _saving = true);
    await widget.db.transactionDao.unsplit(widget.txnId);
    _done();
  }

  void _done() {
    if (!mounted) return;
    // Category totals and budgets move with the split.
    refreshAlerts(widget.db, context.read<AppSettings>());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const SizedBox(
          height: 200, child: Center(child: CircularProgressIndicator()));
    }
    final money = NumberFormat('#,##0.00');
    final scheme = Theme.of(context).colorScheme;
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final remainder = _remainder;

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: StreamBuilder<List<Category>>(
        stream: widget.db.categoryDao.watchAll(),
        builder: (context, snap) {
          final names = {
            for (final c in snap.data ?? const <Category>[]) c.id: c.name
          };
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_wasSplit ? 'عملية مقسّمة' : 'تقسيم على أكثر من فئة',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text('الإجمالي ${money.format(_total)} ⃁',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: AppSpacing.md),
                for (var i = 0; i < _parts.length; i++)
                  _partRow(i, names, money, remainder),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _parts.add(_Part())),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('إضافة جزء'),
                  ),
                ),
                if (remainder < 0.01)
                  Text(
                    'الأجزاء تتجاوز إجمالي العملية',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.error),
                  ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text(DateFormat('yyyy-MM-dd').format(_date)),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        controller: _note,
                        decoration: const InputDecoration(
                          labelText: 'ملاحظة',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: _valid && !_saving ? _save : null,
                  child: const Text('حفظ التقسيم'),
                ),
                if (_wasSplit)
                  TextButton(
                    onPressed: _saving ? null : _unsplit,
                    child: const Text('إلغاء التقسيم'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _partRow(
      int i, Map<int, String> names, NumberFormat money, double remainder) {
    final part = _parts[i];
    final first = i == 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _pickCategory(part),
              child: Text(
                names[part.categoryId] ?? 'اختر فئة',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 120,
            child: first
                // The remainder: whatever the other parts leave.
                ? InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'الباقي',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: Text(money.format(remainder < 0 ? 0 : remainder)),
                  )
                : TextField(
                    controller: part.amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: const [ThousandsInputFormatter()],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'المبلغ',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
          ),
          SizedBox(
            width: 40,
            child: first || _parts.length <= 2
                ? null
                : IconButton(
                    tooltip: 'حذف الجزء',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => setState(() {
                      _parts.removeAt(i).amount.dispose();
                    }),
                  ),
          ),
        ],
      ),
    );
  }
}
