import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_settings.dart';
import '../data/database.dart';
import '../domain/calendar_format.dart';
import '../domain/category_breakdown.dart';
import '../domain/period_summary.dart';
import 'category_detail_screen.dart';
import 'theme/tokens.dart';

/// Which period the behaviour breakdown groups by.
enum BehaviorScope { monthly, yearly }

/// Income vs spending vs savings vs what was left, one row per period.
/// Used for both the per-month and per-year views -- the only difference is
/// how the rows are aggregated and labelled. Each period expands to show its
/// top spending categories (with per-category averages) and drills into any
/// category's transactions.
class BehaviorScreen extends StatelessWidget {
  final BehaviorScope scope;
  const BehaviorScreen({super.key, required this.scope});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final money = NumberFormat('#,##0');
    final hijri = context.watch<AppSettings>().useHijri;
    final monthly = scope == BehaviorScope.monthly;

    return Scaffold(
      appBar: AppBar(
        title: Text(monthly ? 'سلوك كل شهر' : 'سلوك كل سنة'),
      ),
      body: StreamBuilder<List<Category>>(
        stream: db.categoryDao.watchAll(),
        builder: (context, catSnap) {
          final byId = {
            for (final c in (catSnap.data ?? const <Category>[])) c.id: c
          };
          return StreamBuilder<List<TxnRow>>(
            stream: db.transactionDao.watchAllWithCategory(),
            builder: (context, txnSnap) {
              final rows = txnSnap.data ?? const <TxnRow>[];
              return StreamBuilder<List<SavingsContribution>>(
                stream: db.savingsDao.watchAllContributions(),
                builder: (context, contribSnap) {
                  final contributions =
                      contribSnap.data ?? const <SavingsContribution>[];
                  final periods = monthly
                      ? monthlySummaries(rows, contributions)
                      : yearlySummaries(rows, contributions);
                  if (periods.isEmpty) {
                    return const Center(child: Text('لا توجد بيانات بعد'));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: periods.length,
                    itemBuilder: (context, i) {
                      final p = periods[i];
                      // This period's transactions, for its category breakdown.
                      final periodRows = rows.where((r) {
                        final d = r.txn.date;
                        return monthly
                            ? (d.year == p.year && d.month == p.month)
                            : d.year == p.year;
                      }).toList();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: _PeriodCard(
                          period: p,
                          periodRows: periodRows,
                          byId: byId,
                          money: money,
                          hijri: hijri,
                        ),
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
}

class _PeriodCard extends StatefulWidget {
  final PeriodSummary period;
  final List<TxnRow> periodRows;
  final Map<int, Category> byId;
  final NumberFormat money;
  final bool hijri;
  const _PeriodCard({
    required this.period,
    required this.periodRows,
    required this.byId,
    required this.money,
    required this.hijri,
  });

  @override
  State<_PeriodCard> createState() => _PeriodCardState();
}

class _PeriodCardState extends State<_PeriodCard> {
  bool _expanded = false;

  static const _spentColor = Color(0xFFE8A13A);
  static const _luxury = Color(0xFFE8A13A);

  @override
  Widget build(BuildContext context) {
    final period = widget.period;
    final money = widget.money;
    final scheme = Theme.of(context).colorScheme;
    final key = period.monthKey;
    final title = key == null
        ? '${period.year}'
        : monthLabelFor(key, hijri: widget.hijri);
    final periodWeeks = period.month == null
        ? DateTime(period.year + 1).difference(DateTime(period.year)).inDays /
            7.0
        : DateTime(period.year, period.month! + 1, 0).day / 7.0;

    // The bar shows how the income was split: spent / saved / left over.
    final income = period.income;
    final spentPct = income > 0 ? (period.spent / income).clamp(0.0, 1.0) : 0.0;
    final savedPct = income > 0 ? (period.saved / income).clamp(0.0, 1.0) : 0.0;
    final leftPct = (1 - spentPct - savedPct).clamp(0.0, 1.0);
    final rate = period.savingsRate;

    final breakdown = categoryBreakdown(widget.periodRows);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: const [AppShadows.card],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: AppTextSizes.row,
                        fontWeight: FontWeight.w700)),
              ),
              if (rate != null)
                Text(
                  'ادخار ${(rate * 100).toStringAsFixed(0)}٪',
                  style: TextStyle(
                    fontSize: AppTextSizes.label,
                    fontWeight: FontWeight.w600,
                    color: rate >= 0.2 ? AppColors.income : _luxury,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (income > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.chip),
              child: Row(
                children: [
                  Expanded(
                    flex: (spentPct * 1000).round().clamp(0, 1000),
                    child: Container(height: 10, color: _spentColor),
                  ),
                  Expanded(
                    flex: (savedPct * 1000).round().clamp(0, 1000),
                    child: Container(height: 10, color: scheme.primary),
                  ),
                  Expanded(
                    flex: (leftPct * 1000).round().clamp(0, 1000),
                    child: Container(
                      height: 10,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.2),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _stat(context, 'الدخل', period.income, AppColors.income),
              _stat(context, 'المصروف', period.spent, _spentColor),
              _stat(context, 'المدخر', period.saved, scheme.primary),
              _stat(
                context,
                'المتبقي',
                period.remaining,
                period.remaining >= 0 ? scheme.onSurface : Colors.red.shade400,
              ),
            ],
          ),
          if (breakdown.isNotEmpty) ...[
            const Divider(height: AppSpacing.xl),
            InkWell(
              borderRadius: BorderRadius.circular(AppRadii.tile),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('أكثر الفئات إنفاقًا',
                          style: TextStyle(
                              fontSize: AppTextSizes.label,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant)),
                    ),
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                        color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
            if (_expanded)
              for (final stat in breakdown.take(5)) ...[
                const SizedBox(height: AppSpacing.sm),
                categoryStatRow(context, stat, period.spent, money, widget.byId,
                    periodLabel: title, periodWeeks: periodWeeks),
              ],
          ],
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, double value, Color color) {
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
            child: Text(
              widget.money.format(value),
              style: TextStyle(
                  fontSize: AppTextSizes.label,
                  fontWeight: FontWeight.w700,
                  color: color),
            ),
          ),
        ],
      ),
    );
  }
}
