import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_settings.dart';
import '../data/database.dart';
import '../data/enums.dart';
import '../domain/calendar_format.dart';
import '../domain/category_breakdown.dart';
import '../domain/financial_period.dart';
import '../domain/period_summary.dart';
import 'category_detail_screen.dart';
import 'theme/tokens.dart';

/// Which window the behaviour breakdown groups by: the salary cycle (the app's
/// default unit) or the calendar year.
enum BehaviorScope { cycle, yearly }

/// Income vs spending vs savings vs what was left, one row per window. Used for
/// both the per-cycle and per-year views — the only difference is how the rows
/// are aggregated and labelled. Each window expands to show its top spending
/// categories (with per-category averages) and drills into any category's
/// transactions.
class BehaviorScreen extends StatelessWidget {
  final BehaviorScope scope;
  const BehaviorScreen({super.key, required this.scope});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final money = NumberFormat('#,##0');
    final hijri = context.watch<AppSettings>().useHijri;
    final byCycle = scope == BehaviorScope.cycle;
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text(byCycle ? 'سلوك كل دورة' : 'سلوك كل سنة'),
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
                  return StreamBuilder<List<RecurrenceRule>>(
                    stream: db.recurrenceDao.watchByType(TxnType.income),
                    builder: (context, rulesSnap) {
                      final incomeRules =
                          rulesSnap.data ?? const <RecurrenceRule>[];
                      final items = byCycle
                          ? _cycleItems(rows, contributions, incomeRules, now)
                          : _yearItems(rows, contributions);
                      if (items.isEmpty) {
                        return const Center(child: Text('لا توجد بيانات بعد'));
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          return Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.md),
                            child: _PeriodCard(
                              item: items[i],
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
          );
        },
      ),
    );
  }

  List<_BehaviorItem> _cycleItems(
    List<TxnRow> rows,
    List<SavingsContribution> contributions,
    List<RecurrenceRule> incomeRules,
    DateTime now,
  ) {
    return [
      for (final cs in cycleSummaries(rows, contributions, incomeRules, now))
        _BehaviorItem(
          period: cs.period,
          income: cs.income,
          spent: cs.spent,
          saved: cs.saved,
          rows: [
            for (final r in rows)
              if (cs.period.contains(r.txn.date)) r
          ],
          weeks: cs.period.end.difference(cs.period.start).inDays / 7.0,
        ),
    ];
  }

  List<_BehaviorItem> _yearItems(
    List<TxnRow> rows,
    List<SavingsContribution> contributions,
  ) {
    return [
      for (final p in yearlySummaries(rows, contributions))
        _BehaviorItem(
          year: p.year,
          income: p.income,
          spent: p.spent,
          saved: p.saved,
          rows: [
            for (final r in rows)
              if (r.txn.date.year == p.year) r
          ],
          weeks: DateTime(p.year + 1).difference(DateTime(p.year)).inDays / 7.0,
        ),
    ];
  }
}

/// One window's numbers, decoupled from whether it's a cycle or a year.
class _BehaviorItem {
  final FinancialPeriod? period; // set for a cycle
  final int? year; // set for a year
  final double income;
  final double spent;
  final double saved;
  final List<TxnRow> rows;
  final double weeks;

  const _BehaviorItem({
    this.period,
    this.year,
    required this.income,
    required this.spent,
    required this.saved,
    required this.rows,
    required this.weeks,
  });

  double get remaining => income - spent - saved;
  double? get savingsRate => income > 0 ? saved / income : null;
  String title(bool hijri) =>
      period != null ? cycleLabelFor(period!, hijri: hijri) : '$year';
}

class _PeriodCard extends StatefulWidget {
  final _BehaviorItem item;
  final Map<int, Category> byId;
  final NumberFormat money;
  final bool hijri;
  const _PeriodCard({
    required this.item,
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
    final item = widget.item;
    final money = widget.money;
    final scheme = Theme.of(context).colorScheme;
    final title = item.title(widget.hijri);

    // The bar shows how the income was split: spent / saved / left over.
    final income = item.income;
    final spentPct = income > 0 ? (item.spent / income).clamp(0.0, 1.0) : 0.0;
    final savedPct = income > 0 ? (item.saved / income).clamp(0.0, 1.0) : 0.0;
    final leftPct = (1 - spentPct - savedPct).clamp(0.0, 1.0);
    final rate = item.savingsRate;

    final breakdown = categoryBreakdown(item.rows);

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
              _stat(context, 'الدخل', item.income, AppColors.income),
              _stat(context, 'المصروف', item.spent, _spentColor),
              _stat(context, 'المدخر', item.saved, scheme.primary),
              _stat(
                context,
                'المتبقي',
                item.remaining,
                item.remaining >= 0 ? scheme.onSurface : Colors.red.shade400,
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
                categoryStatRow(context, stat, item.spent, money, widget.byId,
                    periodLabel: title, periodWeeks: item.weeks),
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
