import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_settings.dart';
import '../data/database.dart';
import '../data/enums.dart';
import '../domain/budget_advisor.dart';
import '../domain/budget_progress.dart';
import '../domain/parse_amount.dart';
import 'theme/tokens.dart';
import 'widgets/category_icon_tile.dart';

/// Set a monthly spending budget per top-level expense category and watch this
/// month's spend against it. The page also *advises*: it proposes a budget per
/// category — seeded from income on day one (scaled by the lifestyle chip), then
/// from the median of your own spending once there's history — which you can
/// apply with a single tap. The recommended weekly figure elsewhere is derived
/// from behaviour; this is the target you set (or accept) yourself.
class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final settings = context.watch<AppSettings>();
    final money = NumberFormat('#,##0.00');
    final now = DateTime.now();

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
              // Income rules feed both the day-one seed and the salary-cycle
              // windows the history median is taken over (see suggestBudgets).
              return StreamBuilder<List<RecurrenceRule>>(
                stream: db.recurrenceDao.watchByType(TxnType.income),
                builder: (context, incomeSnap) {
                  final incomeRules =
                      incomeSnap.data ?? const <RecurrenceRule>[];
                  return StreamBuilder<List<TxnRow>>(
                    stream: db.transactionDao.watchAllWithCategory(),
                    builder: (context, txnSnap) {
                      final rows = txnSnap.data ?? const <TxnRow>[];
                      final lines = {
                        for (final l in budgetProgress(budgets, rows, now))
                          l.categoryId: l,
                      };
                      final suggestions = {
                        for (final s in suggestBudgets(
                          rows: rows,
                          topExpenseCats: topExpense,
                          incomeRules: incomeRules,
                          now: now,
                          lifestyleFactor: settings.lifestyleFactor,
                        ))
                          s.categoryId: s,
                      };
                      return ListView(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        children: [
                          _AdvisorHeader(
                            settings: settings,
                            suggestions: suggestions.values.toList(),
                            money: money,
                            onApplyAll: () => _applyAll(
                                context, db, suggestions.values, budgetByCat),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          for (final cat in topExpense)
                            _BudgetTile(
                              category: cat,
                              budget: budgetByCat[cat.id],
                              line: lines[cat.id],
                              suggestion: suggestions[cat.id],
                              money: money,
                              onEdit: () => _editBudget(context, db, cat,
                                  budgetByCat[cat.id]?.amount),
                              onApplySuggestion: suggestions[cat.id] == null
                                  ? null
                                  : () => _applyOne(
                                      context,
                                      db,
                                      cat.id,
                                      suggestions[cat.id]!.amount,
                                      budgetByCat[cat.id]?.amount),
                            ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  /// Applies every suggestion at once, remembering the prior amounts so «تراجع»
  /// can put them all back (an unset budget is restored by removing it again).
  Future<void> _applyAll(
    BuildContext context,
    AppDatabase db,
    Iterable<BudgetSuggestion> suggestions,
    Map<int, CategoryBudget> budgetByCat,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final list = suggestions.toList();
    final previous = {
      for (final s in list) s.categoryId: budgetByCat[s.categoryId]?.amount,
    };
    for (final s in list) {
      await db.budgetDao.setBudget(s.categoryId, s.amount);
    }
    messenger.showSnackBar(SnackBar(
      content: Text('طُبِّقت ${list.length} ميزانية مقترحة'),
      action: SnackBarAction(
        label: 'تراجع',
        onPressed: () => _restore(db, previous),
      ),
    ));
  }

  /// Applies a single category's suggestion, with undo to its prior amount.
  Future<void> _applyOne(BuildContext context, AppDatabase db, int categoryId,
      double amount, double? previous) async {
    final messenger = ScaffoldMessenger.of(context);
    await db.budgetDao.setBudget(categoryId, amount);
    messenger.showSnackBar(SnackBar(
      content: const Text('طُبِّقت الميزانية المقترحة'),
      action: SnackBarAction(
        label: 'تراجع',
        onPressed: () => _restore(db, {categoryId: previous}),
      ),
    ));
  }

  Future<void> _restore(AppDatabase db, Map<int, double?> previous) async {
    for (final e in previous.entries) {
      if (e.value == null) {
        await db.budgetDao.removeBudget(e.key);
      } else {
        await db.budgetDao.setBudget(e.key, e.value!);
      }
    }
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
            suffixText: '⃁',
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

/// The advisor block at the top of the page: the lifestyle chip (only while the
/// income seed is still in play) and a one-tap "suggest all" action.
class _AdvisorHeader extends StatelessWidget {
  final AppSettings settings;
  final List<BudgetSuggestion> suggestions;
  final NumberFormat money;
  final VoidCallback onApplyAll;
  const _AdvisorHeader({
    required this.settings,
    required this.suggestions,
    required this.money,
    required this.onApplyAll,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final caption =
        TextStyle(fontSize: AppTextSizes.label, color: scheme.onSurfaceVariant);

    // No income and no history: nothing to suggest yet.
    if (suggestions.isEmpty) {
      return Text(
        'أضف دخلاً متكررًا (كالراتب) وسنقترح لك ميزانية لكل فئة، ثم نضبطها تلقائيًا حسب إنفاقك الفعلي.',
        style: caption,
      );
    }

    // Once every suggestion is learned from real spending, the lifestyle factor
    // no longer changes anything, so we retire the chip and say so.
    final allHistory =
        suggestions.every((s) => s.basis == BudgetSuggestionBasis.fromHistory);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (allHistory)
          Text('هذه الاقتراحات مبنية على إنفاقك الفعلي.', style: caption)
        else ...[
          Text('اقتراحات مبدئية حسب دخلك — اضبطها بنمط إنفاقك:',
              style: caption),
          const SizedBox(height: AppSpacing.sm),
          SegmentedButton<SpendingStyle>(
            segments: [
              for (final s in SpendingStyle.values)
                ButtonSegment(value: s, label: Text(s.label)),
            ],
            selected: {settings.budgetStyle},
            showSelectedIcon: false,
            onSelectionChanged: (sel) => settings.setBudgetStyle(sel.first),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: onApplyAll,
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: const Text('اقترِح ميزانياتي'),
        ),
      ],
    );
  }
}

class _BudgetTile extends StatelessWidget {
  final Category category;
  final CategoryBudget? budget;
  final BudgetLine? line;
  final BudgetSuggestion? suggestion;
  final NumberFormat money;
  final VoidCallback onEdit;
  final VoidCallback? onApplySuggestion;
  const _BudgetTile({
    required this.category,
    required this.budget,
    required this.line,
    required this.suggestion,
    required this.money,
    required this.onEdit,
    required this.onApplySuggestion,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasBudget = budget != null;
    final spent = line?.spent ?? 0;
    final over = line?.isOver ?? false;
    // Whether it's worth nudging: no budget yet, or the set one differs from the
    // suggestion by more than the rounding step.
    final s = suggestion;
    final showNudge =
        s != null && (!hasBudget || (budget!.amount - s.amount).abs() >= 10);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              CategoryIconTile(
                  iconKey: category.iconKey, colorValue: category.colorValue),
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
                        '${money.format(spent)} من ${money.format(budget!.amount)} ⃁',
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
                    ] else if (s == null)
                      Text(
                        'لا توجد ميزانية — اضغط للتحديد',
                        style: TextStyle(
                            fontSize: AppTextSizes.label,
                            color: scheme.onSurfaceVariant),
                      ),
                    if (showNudge)
                      _SuggestionNudge(suggestion: s, money: money),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (showNudge)
                // A discrete apply target for the suggestion; tapping elsewhere
                // on the tile still opens the manual editor.
                IconButton(
                  tooltip: 'تطبيق المقترح',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.check_circle_outline, color: scheme.primary),
                  onPressed: onApplySuggestion,
                )
              else
                Icon(Icons.edit_outlined,
                    size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// The inline "مقترح: X ⃁" line under a category, with its basis caption.
class _SuggestionNudge extends StatelessWidget {
  final BudgetSuggestion suggestion;
  final NumberFormat money;
  const _SuggestionNudge({required this.suggestion, required this.money});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final basis = suggestion.basis == BudgetSuggestionBasis.fromHistory
        ? '  •  آخر ${suggestion.cyclesUsed} دورات'
        : '';
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(
        'مقترح: ${money.format(suggestion.amount)} ⃁$basis',
        style: TextStyle(
          fontSize: AppTextSizes.label,
          fontWeight: FontWeight.w600,
          color: scheme.primary,
        ),
      ),
    );
  }
}
