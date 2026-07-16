import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../data/enums.dart';
import '../data/export.dart';
import '../domain/category_breakdown.dart';
import '../domain/category_insights.dart';
import '../domain/date_grouping.dart';
import '../domain/financial_period.dart';
import '../domain/statistics_summary.dart';
import 'behavior_screen.dart';
import 'category_detail_screen.dart';
import 'theme/tokens.dart';
import 'widgets/category_icon_tile.dart';

/// Spending analytics, all derived in a single pass over the transaction
/// stream (no per-frame DB queries), so it stays cheap even as history grows.
class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key});

  static const _luxuryColor = Color(0xFFE8A13A);

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final money = NumberFormat('#,##0.00');

    // Categories resolve each transaction to its top-level parent + kind,
    // transactions carry the amounts, contributions give the savings rate.
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإحصائيات'),
        actions: [
          IconButton(
            tooltip: 'تصدير الإحصائيات',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () async {
              final path = await exportStatsCsvToFile(db);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('تم تصدير الإحصائيات: $path')),
                );
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<List<Category>>(
        stream: db.categoryDao.watchAll(),
        builder: (context, catSnap) {
          final cats = catSnap.data ?? const <Category>[];
          final byId = {for (final c in cats) c.id: c};
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
                      final now = DateTime.now();
                      final period = financialPeriod(incomeRules, now);
                      // Stats follow the salary cycle too (same period as the
                      // home dashboard), not the calendar month.
                      final s = StatisticsSummary.from(
                          rows, contributions, now, period);
                      // Per-category slices of this period's spend, for the
                      // top-categories card and its drill-downs.
                      final breakdown = categoryBreakdown(rows
                          .where((r) => period.contains(r.txn.date))
                          .toList());
                      final periodWeeks =
                          period.end.difference(period.start).inDays / 7.0;
                      final thisCycleTotals = {
                        for (final st in breakdown) st.categoryId: st.total
                      };
                      // How each top category compares to the user's own norm,
                      // and which are worth trimming.
                      final trends = categoryTrends(
                          rows: rows,
                          incomeRules: incomeRules,
                          now: now,
                          thisCycleTotals: thisCycleTotals);
                      final cuts = cutSuggestions(
                          breakdown: breakdown,
                          byId: byId,
                          trends: trends,
                          periodTotal: s.spentThisMonth);
                      if (s.allExpenseCount == 0) {
                        return const Center(
                            child: Text('لا توجد بيانات كافية بعد'));
                      }
                      return ListView(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        children: [
                          _behaviorLinks(context),
                          const SizedBox(height: AppSpacing.md),
                          _thisMonthCard(context, s, money),
                          const SizedBox(height: AppSpacing.md),
                          _paceCard(context, s, money),
                          const SizedBox(height: AppSpacing.md),
                          _weeklyBudgetCard(context, s, money),
                          const SizedBox(height: AppSpacing.md),
                          _savingsRateCard(context, s, money),
                          const SizedBox(height: AppSpacing.md),
                          _essentialsCard(context, s, money),
                          const SizedBox(height: AppSpacing.md),
                          _quickFactsCard(context, s, money),
                          const SizedBox(height: AppSpacing.md),
                          if (cuts.isNotEmpty) ...[
                            _whereToCutCard(context, cuts, breakdown, byId,
                                trends, money, periodWeeks),
                            const SizedBox(height: AppSpacing.md),
                          ],
                          _topCategoriesCard(
                              context,
                              breakdown,
                              s.spentThisMonth,
                              money,
                              byId,
                              trends,
                              periodWeeks,
                              periodLabel: 'هذا الشهر'),
                          const SizedBox(height: AppSpacing.md),
                          _trendCard(context, s, money),
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

  // ---------------------------------------------------------------- chrome

  /// Entry points to the per-month and per-year behaviour breakdowns.
  Widget _behaviorLinks(BuildContext context) {
    Widget tile(IconData icon, String label, BehaviorScope scope) => Expanded(
          child: Card(
            margin: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadii.card),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => BehaviorScreen(scope: scope)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.lg, horizontal: AppSpacing.md),
                child: Column(
                  children: [
                    Icon(icon, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: AppSpacing.xs),
                    Text(label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: AppTextSizes.label,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        );

    return Row(
      children: [
        tile(Icons.calendar_month_outlined, 'سلوك كل شهر',
            BehaviorScope.monthly),
        const SizedBox(width: AppSpacing.md),
        tile(Icons.event_note_outlined, 'سلوك كل سنة', BehaviorScope.yearly),
      ],
    );
  }

  Widget _card(BuildContext context, {required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadii.card),
          boxShadow: const [AppShadows.card],
        ),
        child: child,
      );

  Widget _label(BuildContext context, String text) => Text(
        text,
        style: TextStyle(
          fontSize: AppTextSizes.label,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );

  Widget _miniStat(
      BuildContext context, String label, String value, Color color) {
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
                style: TextStyle(
                    fontSize: AppTextSizes.row,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- cards

  Widget _thisMonthCard(
      BuildContext context, StatisticsSummary s, NumberFormat money) {
    final scheme = Theme.of(context).colorScheme;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, 'إنفاق هذا الشهر'),
          const SizedBox(height: AppSpacing.xs),
          Text('${money.format(s.spentThisMonth)} ⃁',
              style: const TextStyle(
                  fontSize: AppTextSizes.heroMin, fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _miniStat(context, 'المعدل اليومي',
                  '${money.format(s.dailyAvgThisMonth)} ⃁', scheme.onSurface),
              const SizedBox(width: AppSpacing.lg),
              _miniStat(context, 'المتوقع للشهر',
                  '${money.format(s.projectedThisMonth)} ⃁', scheme.primary),
            ],
          ),
          if (s.lastMonthSpent > 0) ...[
            const Divider(height: AppSpacing.xl),
            Row(
              children: [
                Icon(
                  s.projectedVsLastMonth >= 0
                      ? Icons.trending_up
                      : Icons.trending_down,
                  size: 18,
                  color: s.projectedVsLastMonth >= 0
                      ? Colors.red.shade400
                      : AppColors.income,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'الشهر الماضي ${money.format(s.lastMonthSpent)} ⃁ — '
                    'متوقع أن ${s.projectedVsLastMonth >= 0 ? 'ترتفع' : 'تنخفض'} '
                    '${s.projectedVsLastMonth.abs().toStringAsFixed(0)}٪',
                    style: TextStyle(
                        fontSize: AppTextSizes.label,
                        color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _paceCard(
      BuildContext context, StatisticsSummary s, NumberFormat money) {
    final scheme = Theme.of(context).colorScheme;
    final allowance = s.dailyAllowanceRemaining;
    final over = allowance != null && allowance < 0;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, 'المتاح يوميًا لبقية الشهر'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            allowance == null ? '—' : '${money.format(allowance.abs())} ⃁',
            style: TextStyle(
              fontSize: AppTextSizes.heroMin,
              fontWeight: FontWeight.w700,
              color: allowance == null
                  ? scheme.onSurface
                  : (over ? Colors.red.shade400 : AppColors.income),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            allowance == null
                ? 'أضف دخلًا لهذا الشهر لحساب المتاح يوميًا.'
                : over
                    ? 'تجاوزت دخل هذا الشهر — قلّل الإنفاق أو استخدم من رصيدك.'
                    : 'ما تبقّى من دخلك موزّعًا على ${s.daysLeftInMonth} يوم متبقٍ.',
            style: TextStyle(
                fontSize: AppTextSizes.label, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _weeklyBudgetCard(
      BuildContext context, StatisticsSummary s, NumberFormat money) {
    final scheme = Theme.of(context).colorScheme;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, 'ميزانية هذا الأسبوع'),
          const SizedBox(height: AppSpacing.xs),
          Text('${money.format(s.recommendedWeekly)} ⃁',
              style: TextStyle(
                  fontSize: AppTextSizes.heroMin,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'محسوبة من متوسط إنفاقك (أساسياتك + ٨٥٪ من كمالياتك)، وتتكيّف مع '
            'شهرك: تجاوزك في أسابيع سابقة يخفّضها، وتوفيرك يرفعها.',
            style: TextStyle(
                fontSize: AppTextSizes.label, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'وتيرتك الحالية: ${money.format(s.currentWeeklyPace)} ⃁ أسبوعيًا',
            style: TextStyle(
                fontSize: AppTextSizes.label,
                color: s.currentWeeklyPace > s.recommendedWeekly
                    ? Colors.red.shade400
                    : AppColors.income),
          ),
        ],
      ),
    );
  }

  Widget _savingsRateCard(
      BuildContext context, StatisticsSummary s, NumberFormat money) {
    final scheme = Theme.of(context).colorScheme;
    final rate = s.savingsRate;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, 'معدل الادخار هذا الشهر'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            rate == null ? '—' : '${(rate * 100).toStringAsFixed(0)}٪',
            style: TextStyle(
              fontSize: AppTextSizes.heroMin,
              fontWeight: FontWeight.w700,
              color: rate == null
                  ? scheme.onSurface
                  : (rate >= 0.2 ? AppColors.income : _luxuryColor),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (rate != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.chip),
              child: LinearProgressIndicator(
                value: rate.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor:
                    scheme.onSurfaceVariant.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation(
                    Theme.of(context).extension<AccentPalette>()!.progress),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Text(
            rate == null
                ? 'أضف دخلًا لهذا الشهر لحساب معدل الادخار.'
                : 'ادّخرت ${money.format(s.monthSaved)} من دخل '
                    '${money.format(s.monthIncome)} ⃁. '
                    '${rate >= 0.2 ? 'ممتاز — أنت فوق هدف ٢٠٪.' : 'الهدف الشائع هو ٢٠٪.'}',
            style: TextStyle(
                fontSize: AppTextSizes.label, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _essentialsCard(
      BuildContext context, StatisticsSummary s, NumberFormat money) {
    final total = s.essentialThisMonth + s.luxuryThisMonth;
    final essentialPct = total > 0 ? s.essentialThisMonth / total : 0.0;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, 'أساسيات مقابل كماليات (هذا الشهر)'),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.chip),
            child: Row(
              children: [
                Expanded(
                  flex: (essentialPct * 1000).round().clamp(0, 1000),
                  child: Container(height: 12, color: AppColors.income),
                ),
                Expanded(
                  flex: ((1 - essentialPct) * 1000).round().clamp(0, 1000),
                  child: Container(height: 12, color: _luxuryColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _legend(context, 'أساسيات',
                  '${money.format(s.essentialThisMonth)} ⃁', AppColors.income),
              const SizedBox(width: AppSpacing.lg),
              _legend(context, 'كماليات',
                  '${money.format(s.luxuryThisMonth)} ⃁', _luxuryColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickFactsCard(
      BuildContext context, StatisticsSummary s, NumberFormat money) {
    final scheme = Theme.of(context).colorScheme;
    final facts = <(IconData, String, String)>[
      (
        Icons.receipt_long,
        'عدد العمليات',
        '${s.txnCountThisMonth}',
      ),
      (
        Icons.straighten,
        'متوسط العملية',
        '${money.format(s.avgTxnThisMonth)} ⃁',
      ),
      if (s.biggestExpense != null)
        (
          Icons.arrow_upward,
          'أكبر مصروف',
          '${money.format(s.biggestExpense!.txn.amount)} ⃁'
              ' • ${s.biggestExpense!.category.name}',
        ),
      if (s.highestDayAmount > 0)
        (
          Icons.calendar_today,
          'أعلى يوم إنفاقًا',
          '${money.format(s.highestDayAmount)} ⃁'
              ' • ${dayName(s.highestDay!)} ${s.highestDay!.day}',
        ),
      (
        Icons.savings_outlined,
        'أيام بلا إنفاق',
        '${s.noSpendDays} من ${s.daysElapsed}',
      ),
      if (s.topWeekday != null)
        (
          Icons.event_repeat,
          'أكثر أيام الأسبوع إنفاقًا',
          '${dayNameForWeekday(s.topWeekday!)}'
              ' • ${money.format(s.topWeekdayAvg)} ⃁ وسطيًا',
        ),
    ];

    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, 'لمحات سريعة'),
          const SizedBox(height: AppSpacing.sm),
          for (final f in facts) ...[
            const Divider(height: AppSpacing.lg),
            Row(
              children: [
                Icon(f.$1, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(f.$2,
                      style: TextStyle(
                          fontSize: AppTextSizes.label,
                          color: scheme.onSurfaceVariant)),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    f.$3,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                        fontSize: AppTextSizes.label,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _topCategoriesCard(
      BuildContext context,
      List<CategoryStat> breakdown,
      double monthTotal,
      NumberFormat money,
      Map<int, Category> byId,
      Map<int, CategoryTrend> trends,
      double periodWeeks,
      {required String periodLabel}) {
    final scheme = Theme.of(context).colorScheme;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, 'أكثر الفئات إنفاقًا (هذا الشهر)'),
          const SizedBox(height: AppSpacing.xs),
          Text('اضغط فئة لعرض عملياتها',
              style: TextStyle(
                  fontSize: AppTextSizes.label,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.md),
          if (breakdown.isEmpty)
            Text('لا يوجد إنفاق هذا الشهر',
                style: TextStyle(color: scheme.onSurfaceVariant))
          else
            for (final stat in breakdown.take(5)) ...[
              categoryStatRow(context, stat, monthTotal, money, byId,
                  periodLabel: periodLabel,
                  periodWeeks: periodWeeks,
                  trend: trends[stat.categoryId]),
              const SizedBox(height: AppSpacing.sm),
            ],
        ],
      ),
    );
  }

  /// "أين تقلّل؟" — the categories most worth trimming (discretionary, rising,
  /// or a big share), each with a short reason and a tap into its transactions.
  Widget _whereToCutCard(
      BuildContext context,
      List<CutSuggestion> cuts,
      List<CategoryStat> breakdown,
      Map<int, Category> byId,
      Map<int, CategoryTrend> trends,
      NumberFormat money,
      double periodWeeks) {
    final scheme = Theme.of(context).colorScheme;
    final statById = {for (final st in breakdown) st.categoryId: st};
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.content_cut, size: 18, color: _luxuryColor),
              const SizedBox(width: AppSpacing.xs),
              _label(context, 'أين تقلّل؟'),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('فئات يُنصح بتقليل الإنفاق فيها',
              style: TextStyle(
                  fontSize: AppTextSizes.label,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.md),
          for (final cut in cuts) ...[
            _cutRow(context, cut, statById[cut.categoryId], byId, money,
                periodWeeks),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }

  Widget _cutRow(BuildContext context, CutSuggestion cut, CategoryStat? stat,
      Map<int, Category> byId, NumberFormat money, double periodWeeks) {
    final scheme = Theme.of(context).colorScheme;
    final cat = byId[cut.categoryId];
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.tile),
      onTap: (cat == null || stat == null)
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CategoryDetailScreen(
                  category: cat,
                  transactions: stat.transactions,
                  periodLabel: 'هذا الشهر',
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
                    Expanded(
                        child: Text(cat?.name ?? '—',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600))),
                    if (stat != null)
                      Text('${money.format(stat.total)} ⃁',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(cut.reason,
                    style: TextStyle(
                        fontSize: AppTextSizes.label,
                        color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Icon(Icons.chevron_left, size: 18, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }

  Widget _trendCard(
      BuildContext context, StatisticsSummary s, NumberFormat money) {
    final scheme = Theme.of(context).colorScheme;
    final maxVal =
        s.monthlyTrend.fold<double>(1, (m, e) => e.value > m ? e.value : m);
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, 'الإنفاق خلال آخر ٦ أشهر'),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final e in s.monthlyTrend)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(money.format(e.value),
                              style: const TextStyle(fontSize: 9), maxLines: 1),
                          const SizedBox(height: 2),
                          Container(
                            height: (e.value / maxVal * 80).clamp(2, 80),
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(_shortMonth(e.key),
                              style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(
      BuildContext context, String label, String value, Color color) {
    return Expanded(
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: AppTextSizes.label)),
                Text(value,
                    style: const TextStyle(
                        fontSize: AppTextSizes.label,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _arMonthsShort = [
    'ينا',
    'فبر',
    'مار',
    'أبر',
    'ماي',
    'يون',
    'يول',
    'أغس',
    'سبت',
    'أكت',
    'نوف',
    'ديس',
  ];
  String _shortMonth(MonthKey k) => _arMonthsShort[k.month - 1];
}
