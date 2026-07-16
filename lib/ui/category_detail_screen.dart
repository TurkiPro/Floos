import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../domain/category_breakdown.dart';
import '../domain/category_insights.dart';
import 'theme/tokens.dart';
import 'widgets/category_icon_tile.dart';
import 'widgets/transaction_row.dart';

/// Drill-down for one category over a period: its total, transaction count,
/// per-transaction average and per-week average, a breakdown by sub-category,
/// and the transactions themselves — sortable by amount (biggest first) or by
/// date (newest first). Reached by tapping a category in the statistics screens.
/// Rows are the shared [TransactionRow], so they can still be tapped to edit or
/// swiped to delete.
class CategoryDetailScreen extends StatefulWidget {
  final Category category;
  final List<TxnRow> transactions;

  /// e.g. "هذا الشهر" or "يوليو 2026" — shown under the title for context.
  final String periodLabel;

  /// How many weeks the period spans, for the per-week average.
  final double periodWeeks;

  const CategoryDetailScreen({
    super.key,
    required this.category,
    required this.transactions,
    required this.periodLabel,
    required this.periodWeeks,
  });

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

enum _Sort { amount, date }

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  _Sort _sort = _Sort.amount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final money = NumberFormat('#,##0.00');

    final rows = [...widget.transactions];
    if (_sort == _Sort.amount) {
      rows.sort((a, b) => b.txn.amount.compareTo(a.txn.amount));
    } else {
      rows.sort((a, b) => b.txn.date.compareTo(a.txn.date));
    }

    final total =
        widget.transactions.fold<double>(0, (s, r) => s + r.txn.amount);
    final count = widget.transactions.length;
    final avg = count == 0 ? 0.0 : total / count;
    final weekly = widget.periodWeeks > 0 ? total / widget.periodWeeks : 0.0;

    // Sub-category slices: group by the transaction's actual category (a
    // sub-category, or the parent itself when logged directly to it). Only worth
    // showing when the spend actually splits across more than one.
    final subGroups = <int, List<TxnRow>>{};
    for (final r in widget.transactions) {
      subGroups.putIfAbsent(r.category.id, () => []).add(r);
    }
    final subs = subGroups.entries.toList()
      ..sort((a, b) {
        final ta = a.value.fold<double>(0, (s, r) => s + r.txn.amount);
        final tb = b.value.fold<double>(0, (s, r) => s + r.txn.amount);
        return tb.compareTo(ta);
      });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category.name),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // Summary: total, count, per-transaction and per-week averages.
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(AppRadii.card),
              boxShadow: const [AppShadows.card],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CategoryIconTile(
                        iconKey: widget.category.iconKey,
                        colorValue: widget.category.colorValue,
                        size: 40),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.category.name,
                              style: const TextStyle(
                                  fontSize: AppTextSizes.row,
                                  fontWeight: FontWeight.w700)),
                          Text(widget.periodLabel,
                              style: TextStyle(
                                  fontSize: AppTextSizes.label,
                                  color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: AppSpacing.xl),
                Row(
                  children: [
                    _stat(context, 'الإجمالي', '${money.format(total)} ⃁'),
                    _stat(context, 'العمليات', '$count'),
                    _stat(context, 'متوسط العملية', '${money.format(avg)} ⃁'),
                    _stat(context, 'أسبوعيًا', '${money.format(weekly)} ⃁'),
                  ],
                ),
              ],
            ),
          ),
          // Sub-category breakdown (only when it splits across more than one).
          if (subs.length > 1) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(AppRadii.card),
                boxShadow: const [AppShadows.card],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('حسب التصنيف الفرعي',
                      style: TextStyle(
                          fontSize: AppTextSizes.label,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant)),
                  const SizedBox(height: AppSpacing.sm),
                  for (final e in subs) ...[
                    const Divider(height: AppSpacing.lg),
                    _subRow(context, e.value, total, money),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          // Sort control.
          SegmentedButton<_Sort>(
            segments: const [
              ButtonSegment(
                  value: _Sort.amount,
                  label: Text('الأعلى مبلغًا'),
                  icon: Icon(Icons.sort, size: 18)),
              ButtonSegment(
                  value: _Sort.date,
                  label: Text('الأحدث'),
                  icon: Icon(Icons.schedule, size: 18)),
            ],
            selected: {_sort},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _sort = s.first),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final r in rows)
            TransactionRow(key: ValueKey(r.txn.id), row: r, money: money),
        ],
      ),
    );
  }

  /// One sub-category line: name, its share of the category, total, count and
  /// per-week average — tap to see just that sub-category's transactions.
  Widget _subRow(BuildContext context, List<TxnRow> txns, double parentTotal,
      NumberFormat money) {
    final scheme = Theme.of(context).colorScheme;
    final cat = txns.first.category;
    final total = txns.fold<double>(0, (s, r) => s + r.txn.amount);
    final share = parentTotal > 0 ? total / parentTotal : 0.0;
    final weekly = widget.periodWeeks > 0 ? total / widget.periodWeeks : 0.0;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.tile),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CategoryDetailScreen(
          category: cat,
          transactions: txns,
          periodLabel: widget.periodLabel,
          periodWeeks: widget.periodWeeks,
        ),
      )),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: Text(cat.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Text('${(share * 100).toStringAsFixed(0)}٪  ',
                          style: TextStyle(
                              fontSize: AppTextSizes.label,
                              color: scheme.onSurfaceVariant)),
                      Text('${money.format(total)} ⃁',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  Text(
                    '${txns.length} عملية • ${money.format(weekly)} ⃁ أسبوعيًا',
                    style: TextStyle(
                        fontSize: AppTextSizes.label,
                        color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_left, size: 18, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: AppTextSizes.label,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value,
                style: const TextStyle(
                    fontSize: AppTextSizes.label, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// A small ↑/↓ badge for a category's trend vs the user's norm. For an expense,
/// rising is bad (red), falling is good (green); steady/none show nothing.
Widget? categoryTrendBadge(BuildContext context, CategoryTrend? trend) {
  if (trend == null || trend.direction == TrendDirection.steady) return null;
  final up = trend.direction == TrendDirection.up;
  final color = up ? Colors.red.shade400 : AppColors.income;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(up ? Icons.arrow_upward : Icons.arrow_downward,
          size: 13, color: color),
      Text('${trend.pctChange.abs().toStringAsFixed(0)}٪',
          style: TextStyle(
              fontSize: AppTextSizes.label,
              fontWeight: FontWeight.w700,
              color: color)),
    ],
  );
}

/// One tappable category slice: icon, name, share of the period, total, its
/// transaction count + average, an optional trend badge, and a bar. Tapping
/// opens the category's transactions for [periodLabel]. Shared by the statistics
/// screen and the per-period behaviour cards, so both drill down the same way.
Widget categoryStatRow(BuildContext context, CategoryStat stat,
    double periodTotal, NumberFormat money, Map<int, Category> byId,
    {required String periodLabel,
    required double periodWeeks,
    CategoryTrend? trend}) {
  final scheme = Theme.of(context).colorScheme;
  final cat = byId[stat.categoryId];
  final share = periodTotal > 0 ? stat.total / periodTotal : 0.0;
  final badge = categoryTrendBadge(context, trend);
  return InkWell(
    borderRadius: BorderRadius.circular(AppRadii.tile),
    onTap: cat == null
        ? null
        : () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => CategoryDetailScreen(
                category: cat,
                transactions: stat.transactions,
                periodLabel: periodLabel,
                periodWeeks: periodWeeks,
              ),
            )),
    child: Row(
      children: [
        CategoryIconTile(
            iconKey: cat?.iconKey ?? 'other',
            colorValue: cat?.colorValue,
            size: 34),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(cat?.name ?? '—')),
                  if (badge != null) ...[badge, const SizedBox(width: 6)],
                  Text('${(share * 100).toStringAsFixed(0)}٪  ',
                      style: TextStyle(
                          fontSize: AppTextSizes.label,
                          color: scheme.onSurfaceVariant)),
                  Text('${money.format(stat.total)} ⃁',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${stat.count} عملية • متوسط ${money.format(stat.average)} ⃁',
                style: TextStyle(
                    fontSize: AppTextSizes.label,
                    color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.chip),
                child: LinearProgressIndicator(
                  value: share,
                  minHeight: 5,
                  backgroundColor:
                      scheme.onSurfaceVariant.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(
                      Theme.of(context).extension<AccentPalette>()!.progress),
                ),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_left, size: 18, color: scheme.onSurfaceVariant),
      ],
    ),
  );
}
