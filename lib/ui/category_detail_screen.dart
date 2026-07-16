import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../domain/category_breakdown.dart';
import 'theme/tokens.dart';
import 'widgets/category_icon_tile.dart';
import 'widgets/transaction_row.dart';

/// Drill-down for one category over a period: its total, transaction count and
/// per-transaction average, plus the transactions themselves — sortable by
/// amount (biggest first) or by date (newest first). Reached by tapping a
/// category in the statistics screens. Rows are the shared [TransactionRow], so
/// they can still be tapped to edit or swiped to delete.
class CategoryDetailScreen extends StatefulWidget {
  final Category category;
  final List<TxnRow> transactions;

  /// e.g. "هذا الشهر" or "يوليو 2026" — shown under the title for context.
  final String periodLabel;

  const CategoryDetailScreen({
    super.key,
    required this.category,
    required this.transactions,
    required this.periodLabel,
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

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category.name),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // Summary: total, count, average.
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
                    _stat(context, 'المتوسط', '${money.format(avg)} ⃁'),
                  ],
                ),
              ],
            ),
          ),
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
          for (final r in rows) TransactionRow(row: r, money: money),
        ],
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
                    fontSize: AppTextSizes.row, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// One tappable category slice: icon, name, share of the period, total, its
/// transaction count + average, and a bar. Tapping opens the category's
/// transactions for [periodLabel]. Shared by the statistics screen and the
/// per-period behaviour cards, so both drill down the same way.
Widget categoryStatRow(BuildContext context, CategoryStat stat,
    double periodTotal, NumberFormat money, Map<int, Category> byId,
    {required String periodLabel}) {
  final scheme = Theme.of(context).colorScheme;
  final cat = byId[stat.categoryId];
  final share = periodTotal > 0 ? stat.total / periodTotal : 0.0;
  return InkWell(
    borderRadius: BorderRadius.circular(AppRadii.tile),
    onTap: cat == null
        ? null
        : () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => CategoryDetailScreen(
                category: cat,
                transactions: stat.transactions,
                periodLabel: periodLabel,
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
