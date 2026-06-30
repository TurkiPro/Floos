import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../data/enums.dart';
import 'theme/tokens.dart';
import 'widgets/category_icon_tile.dart';

class AddTransactionSheet extends StatefulWidget {
  final AppDatabase db;
  const AddTransactionSheet({super.key, required this.db});

  @override
  State<AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<AddTransactionSheet> {
  TxnType _type = TxnType.expense;
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  int? _categoryId;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0 || _categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل مبلغًا صحيحًا واختر فئة')),
      );
      return;
    }
    await widget.db.transactionDao.add(
      amount: amount,
      categoryId: _categoryId!,
      type: _type,
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
            const SizedBox(height: AppSpacing.lg),
            Center(
              child: IntrinsicWidth(
                child: TextField(
                  controller: _amountCtrl,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
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
            // Reactive, not a one-shot fetch: a category added while this
            // sheet is open shows up immediately instead of only on next open.
            StreamBuilder<List<Category>>(
              stream: widget.db.categoryDao.watchActive(),
              builder: (context, snapshot) {
                final cats = (snapshot.data ?? const <Category>[])
                    .where((c) => c.type == _type)
                    .toList();
                if (cats.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: Text('لا توجد فئات بعد'),
                  );
                }
                return GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.sm,
                  childAspectRatio: 0.8,
                  children: [
                    for (final c in cats)
                      GestureDetector(
                        onTap: () => setState(() => _categoryId = c.id),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CategoryIconTile(
                              iconKey: c.iconKey,
                              size: 48,
                              selected: c.id == _categoryId,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style:
                                  const TextStyle(fontSize: AppTextSizes.label),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
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
