import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../data/enums.dart';
import '../domain/budget_progress.dart';
import '../domain/parse_amount.dart';
import 'theme/tokens.dart';
import 'widgets/category_icon_tile.dart';

/// Set a monthly spending budget per top-level expense category and watch this
/// month's spend against it. The recommended weekly figure elsewhere is derived
/// from behaviour; this is the target the user sets themselves.
class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final money = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(title: const Text('الميزانيات')),
      body: StreamBuilder<List<Category>>(
        stream: db.categoryDao.watchActive(),
        builder: (context, catSnap) {
          final topExpense = (catSnap.data ?? const <Category>[])
              .where((c) => c.parentId == null && c.type == TxnType.expense)
              .toList();
          if (topExpense.isEmpty) {
            return const Center(child: Text('لا توجد فئات مصاريف بعد'));
          }
          return StreamBuilder<List<CategoryBudget>>(
            stream: db.budgetDao.watchAll(),
            builder: (context, budgetSnap) {
              final budgets = budgetSnap.data ?? const <CategoryBudget>[];
              final budgetByCat = {for (final b in budgets) b.categoryId: b};
              return StreamBuilder<List<TxnRow>>(
                stream: db.transactionDao.watchAllWithCategory(),
                builder: (context, txnSnap) {
                  final rows = txnSnap.data ?? const <TxnRow>[];
                  final lines = {
                    for (final l
                        in budgetProgress(budgets, rows, DateTime.now()))
                      l.categoryId: l,
                  };
                  return ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      Text(
                        'حدّد سقفًا شهريًا لكل فئة، وتابع ما أنفقته منه هذا الشهر.',
                        style: TextStyle(
                          fontSize: AppTextSizes.label,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      for (final cat in topExpense)
                        _BudgetTile(
                          category: cat,
                          budget: budgetByCat[cat.id],
                          line: lines[cat.id],
                          money: money,
                          onEdit: () => _editBudget(
                              context, db, cat, budgetByCat[cat.id]?.amount),
                        ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _editBudget(BuildContext context, AppDatabase db, Category cat,
      double? current) async {
    final ctrl = TextEditingController(
        text: current == null ? '' : current.toStringAsFixed(0));
    final result = await showDialog<_BudgetEdit>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ميزانية ${cat.name}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'المبلغ الشهري',
            suffixText: 'ر.س',
          ),
        ),
        actions: [
          if (current != null)
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(const _BudgetEdit.remove()),
              child: const Text('إزالة',
                  style: TextStyle(color: Colors.redAccent)),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final amount = parseAmount(ctrl.text);
              Navigator.of(context).pop(_BudgetEdit.save(amount));
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result.remove) {
      await db.budgetDao.removeBudget(cat.id);
    } else if (result.amount != null && result.amount! > 0) {
      await db.budgetDao.setBudget(cat.id, result.amount!);
    }
  }
}

class _BudgetEdit {
  final bool remove;
  final double? amount;
  const _BudgetEdit.save(this.amount) : remove = false;
  const _BudgetEdit.remove()
      : remove = true,
        amount = null;
}

class _BudgetTile extends StatelessWidget {
  final Category category;
  final CategoryBudget? budget;
  final BudgetLine? line;
  final NumberFormat money;
  final VoidCallback onEdit;
  const _BudgetTile({
    required this.category,
    required this.budget,
    required this.line,
    required this.money,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasBudget = budget != null;
    final spent = line?.spent ?? 0;
    final over = line?.isOver ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              CategoryIconTile(iconKey: category.iconKey),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(category.name,
                        style: const TextStyle(
                            fontSize: AppTextSizes.row,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    if (hasBudget) ...[
                      Text(
                        '${money.format(spent)} من ${money.format(budget!.amount)} ر.س',
                        style: TextStyle(
                          fontSize: AppTextSizes.label,
                          color:
                              over ? Colors.redAccent : scheme.onSurfaceVariant,
                          fontWeight:
                              over ? FontWeight.w700 : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadii.chip),
                        child: LinearProgressIndicator(
                          value: (line?.ratio ?? 0).clamp(0.0, 1.0).toDouble(),
                          minHeight: 6,
                          backgroundColor:
                              scheme.onSurfaceVariant.withValues(alpha: 0.15),
                          valueColor: AlwaysStoppedAnimation(
                            over
                                ? Colors.redAccent
                                : Theme.of(context)
                                    .extension<AccentPalette>()!
                                    .progress,
                          ),
                        ),
                      ),
                    ] else
                      Text(
                        'لا توجد ميزانية — اضغط للتحديد',
                        style: TextStyle(
                            fontSize: AppTextSizes.label,
                            color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.edit_outlined,
                  size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
