import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../data/enums.dart';
import '../data/export.dart';
import '../domain/date_grouping.dart';
import 'behavior_screen.dart';
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
                  final s =
                      _Stats.from(rows, contributions, DateTime.now());
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
                      _topCategoriesCard(context, s, money, byId),
                      const SizedBox(height: AppSpacing.md),
                      _trendCard(context, s, money),
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

  // ---------------------------------------------------------------- chrome

  /// Entry points to the per-month and per-year behaviour breakdowns.
  Widget _behaviorLinks(BuildContext context) {
    Widget tile(IconData icon, String label, BehaviorScope scope) => Expanded(
          child: Card(
            margin: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadii.card),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => BehaviorScreen(scope: scope)),
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

  Widget _thisMonthCard(BuildContext context, _Stats s, NumberFormat money) {
    final scheme = Theme.of(context).colorScheme;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, 'إنفاق هذا الشهر'),
          const SizedBox(height: AppSpacing.xs),
          Text('${money.format(s.spentThisMonth)} ر.س',
              style: const TextStyle(
                  fontSize: AppTextSizes.heroMin,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _miniStat(context, 'المعدل اليومي',
                  '${money.format(s.dailyAvgThisMonth)} ر.س', scheme.onSurface),
              const SizedBox(width: AppSpacing.lg),
              _miniStat(context, 'المتوقع للشهر',
                  '${money.format(s.projectedThisMonth)} ر.س', scheme.primary),
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
                    'الشهر الماضي ${money.format(s.lastMonthSpent)} ر.س — '
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

  Widget _paceCard(BuildContext context, _Stats s, NumberFormat money) {
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
            allowance == null
                ? '—'
                : '${money.format(allowance.abs())} ر.س',
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
      BuildContext context, _Stats s, NumberFormat money) {
    final scheme = Theme.of(context).colorScheme;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, 'الميزانية الأسبوعية المقترحة'),
          const SizedBox(height: AppSpacing.xs),
          Text('${money.format(s.recommendedWeekly)} ر.س',
              style: TextStyle(
                  fontSize: AppTextSizes.heroMin,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'محسوبة من متوسط إنفاقك: أساسياتك بالكامل + ٨٥٪ من كمالياتك، '
            'لتوفير جزء من الإنفاق الاختياري.',
            style: TextStyle(
                fontSize: AppTextSizes.label, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'وتيرتك الحالية: ${money.format(s.currentWeeklyPace)} ر.س أسبوعيًا',
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

  Widget _savingsRateCard(BuildContext context, _Stats s, NumberFormat money) {
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
                    '${money.format(s.monthIncome)} ر.س. '
                    '${rate >= 0.2 ? 'ممتاز — أنت فوق هدف ٢٠٪.' : 'الهدف الشائع هو ٢٠٪.'}',
            style: TextStyle(
                fontSize: AppTextSizes.label, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _essentialsCard(BuildContext context, _Stats s, NumberFormat money) {
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
                  '${money.format(s.essentialThisMonth)} ر.س', AppColors.income),
              const SizedBox(width: AppSpacing.lg),
              _legend(context, 'كماليات',
                  '${money.format(s.luxuryThisMonth)} ر.س', _luxuryColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickFactsCard(BuildContext context, _Stats s, NumberFormat money) {
    final scheme = Theme.of(context).colorScheme;
    final facts = <(IconData, String, String)>[
      (
        Icons.receipt_long,
        'عدد الحركات',
        '${s.txnCountThisMonth}',
      ),
      (
        Icons.straighten,
        'متوسط الحركة',
        '${money.format(s.avgTxnThisMonth)} ر.س',
      ),
      if (s.biggestExpense != null)
        (
          Icons.arrow_upward,
          'أكبر مصروف',
          '${money.format(s.biggestExpense!.txn.amount)} ر.س'
              ' • ${s.biggestExpense!.category.name}',
        ),
      if (s.highestDayAmount > 0)
        (
          Icons.calendar_today,
          'أعلى يوم إنفاقًا',
          '${money.format(s.highestDayAmount)} ر.س'
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
              ' • ${money.format(s.topWeekdayAvg)} ر.س وسطيًا',
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

  Widget _topCategoriesCard(BuildContext context, _Stats s, NumberFormat money,
      Map<int, Category> byId) {
    final scheme = Theme.of(context).colorScheme;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, 'أكثر الفئات إنفاقًا (هذا الشهر)'),
          const SizedBox(height: AppSpacing.md),
          if (s.topCategories.isEmpty)
            Text('لا يوجد إنفاق هذا الشهر',
                style: TextStyle(color: scheme.onSurfaceVariant))
          else
            for (final entry in s.topCategories) ...[
              _categoryRow(context, entry, s.spentThisMonth, money, byId),
              const SizedBox(height: AppSpacing.sm),
            ],
        ],
      ),
    );
  }

  Widget _categoryRow(BuildContext context, MapEntry<int, double> entry,
      double monthTotal, NumberFormat money, Map<int, Category> byId) {
    final scheme = Theme.of(context).colorScheme;
    final cat = byId[entry.key];
    final share = monthTotal > 0 ? entry.value / monthTotal : 0.0;
    return Row(
      children: [
        CategoryIconTile(iconKey: cat?.iconKey ?? 'other', size: 34),
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
                  Text('${money.format(entry.value)} ر.س',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
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
      ],
    );
  }

  Widget _trendCard(BuildContext context, _Stats s, NumberFormat money) {
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
                              style: const TextStyle(fontSize: 9),
                              maxLines: 1),
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
    'ينا', 'فبر', 'مار', 'أبر', 'ماي', 'يون',
    'يول', 'أغس', 'سبت', 'أكت', 'نوف', 'ديس',
  ];
  String _shortMonth(MonthKey k) => _arMonthsShort[k.month - 1];
}

/// All statistics, computed once in a single pass over the transactions.
class _Stats {
  final int allExpenseCount;
  final double spentThisMonth;
  final double dailyAvgThisMonth;
  final double projectedThisMonth;
  final double lastMonthSpent;
  /// Percent change of the projected month total vs last month's total.
  final double projectedVsLastMonth;
  final double recommendedWeekly;
  final double currentWeeklyPace;
  final double essentialThisMonth;
  final double luxuryThisMonth;
  final double monthIncome;
  final double monthSaved;
  final double? savingsRate;
  final double? dailyAllowanceRemaining;
  final int daysLeftInMonth;
  final int daysElapsed;
  final int txnCountThisMonth;
  final double avgTxnThisMonth;
  final TxnRow? biggestExpense;
  final DateTime? highestDay;
  final double highestDayAmount;
  final int noSpendDays;
  final int? topWeekday;
  final double topWeekdayAvg;
  final List<MapEntry<int, double>> topCategories; // topLevelId -> amount
  final List<MapEntry<MonthKey, double>> monthlyTrend;

  const _Stats({
    required this.allExpenseCount,
    required this.spentThisMonth,
    required this.dailyAvgThisMonth,
    required this.projectedThisMonth,
    required this.lastMonthSpent,
    required this.projectedVsLastMonth,
    required this.recommendedWeekly,
    required this.currentWeeklyPace,
    required this.essentialThisMonth,
    required this.luxuryThisMonth,
    required this.monthIncome,
    required this.monthSaved,
    required this.savingsRate,
    required this.dailyAllowanceRemaining,
    required this.daysLeftInMonth,
    required this.daysElapsed,
    required this.txnCountThisMonth,
    required this.avgTxnThisMonth,
    required this.biggestExpense,
    required this.highestDay,
    required this.highestDayAmount,
    required this.noSpendDays,
    required this.topWeekday,
    required this.topWeekdayAvg,
    required this.topCategories,
    required this.monthlyTrend,
  });

  static _Stats from(
    List<TxnRow> rows,
    List<SavingsContribution> contributions,
    DateTime now,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final dayOfMonth = now.day;
    final windowStart = today.subtract(const Duration(days: 84)); // 12 weeks
    final lastMonth = DateTime(now.year, now.month - 1, 1);

    var allExpenseCount = 0;
    var spentThisMonth = 0.0, lastMonthSpent = 0.0, monthIncome = 0.0;
    var essentialThisMonth = 0.0, luxuryThisMonth = 0.0;
    var essentialWindow = 0.0, luxuryWindow = 0.0;
    var txnCountThisMonth = 0;
    DateTime? earliestInWindow;
    TxnRow? biggestExpense;
    final byTop = <int, double>{};
    final byMonth = <MonthKey, double>{};
    final byDayThisMonth = <int, double>{};
    final weekdayTotals = <int, double>{};

    bool inThisMonth(DateTime d) => d.year == now.year && d.month == now.month;

    for (final r in rows) {
      final date = r.txn.date;
      final amount = r.txn.amount;

      if (r.txn.type == TxnType.income) {
        if (inThisMonth(date)) monthIncome += amount;
        continue;
      }

      allExpenseCount++;
      final kind = r.category.kind;

      final mk = MonthKey(year: date.year, month: date.month);
      byMonth[mk] = (byMonth[mk] ?? 0) + amount;

      if (date.year == lastMonth.year && date.month == lastMonth.month) {
        lastMonthSpent += amount;
      }

      if (inThisMonth(date)) {
        spentThisMonth += amount;
        txnCountThisMonth++;
        byDayThisMonth[date.day] = (byDayThisMonth[date.day] ?? 0) + amount;
        if (kind == CategoryKind.luxury) {
          luxuryThisMonth += amount;
        } else {
          essentialThisMonth += amount;
        }
        final topId = r.category.parentId ?? r.category.id;
        byTop[topId] = (byTop[topId] ?? 0) + amount;
        if (biggestExpense == null || amount > biggestExpense.txn.amount) {
          biggestExpense = r;
        }
      }

      if (!date.isBefore(windowStart) && !date.isAfter(today)) {
        if (kind == CategoryKind.luxury) {
          luxuryWindow += amount;
        } else {
          essentialWindow += amount;
        }
        weekdayTotals[date.weekday] =
            (weekdayTotals[date.weekday] ?? 0) + amount;
        if (earliestInWindow == null || date.isBefore(earliestInWindow)) {
          earliestInWindow = date;
        }
      }
    }

    var monthSaved = 0.0;
    for (final c in contributions) {
      if (inThisMonth(c.date)) monthSaved += c.amount;
    }

    final dailyAvg = dayOfMonth > 0 ? spentThisMonth / dayOfMonth : 0.0;
    final projected = dailyAvg * daysInMonth;
    final projectedVsLast = lastMonthSpent > 0
        ? (projected - lastMonthSpent) / lastMonthSpent * 100
        : 0.0;

    // Weeks of history actually present in the window, so a new user with a
    // few days of data isn't averaged across a full 12 weeks.
    final windowDays = earliestInWindow == null
        ? 1
        : today.difference(earliestInWindow).inDays + 1;
    final weeks = (windowDays / 7).clamp(1.0, 12.0);
    final essentialWeekly = essentialWindow / weeks;
    final luxuryWeekly = luxuryWindow / weeks;

    // Average spend per weekday over the window: divide each weekday's total
    // by how many times that weekday actually occurred in the window.
    final effectiveStart = earliestInWindow ?? today;
    int? topWeekday;
    var topWeekdayAvg = 0.0;
    for (final wd in weekdayTotals.keys) {
      final occurrences = _countWeekday(effectiveStart, today, wd);
      if (occurrences == 0) continue;
      final avg = weekdayTotals[wd]! / occurrences;
      if (avg > topWeekdayAvg) {
        topWeekdayAvg = avg;
        topWeekday = wd;
      }
    }

    // Highest-spend day and no-spend days, within the elapsed part of the month.
    DateTime? highestDay;
    var highestDayAmount = 0.0;
    byDayThisMonth.forEach((day, amount) {
      if (amount > highestDayAmount) {
        highestDayAmount = amount;
        highestDay = DateTime(now.year, now.month, day);
      }
    });
    final noSpendDays = dayOfMonth - byDayThisMonth.length;

    final daysLeft = (daysInMonth - dayOfMonth + 1).clamp(1, daysInMonth);
    final unspentIncome = monthIncome - spentThisMonth - monthSaved;
    final allowance = monthIncome > 0 ? unspentIncome / daysLeft : null;
    final savingsRate = monthIncome > 0 ? monthSaved / monthIncome : null;

    final topCategories = byTop.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Last 6 months including this one, oldest -> newest for the bar row.
    final trend = <MapEntry<MonthKey, double>>[];
    for (var i = 5; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      final mk = MonthKey(year: d.year, month: d.month);
      trend.add(MapEntry(mk, byMonth[mk] ?? 0));
    }

    return _Stats(
      allExpenseCount: allExpenseCount,
      spentThisMonth: spentThisMonth,
      dailyAvgThisMonth: dailyAvg,
      projectedThisMonth: projected,
      lastMonthSpent: lastMonthSpent,
      projectedVsLastMonth: projectedVsLast,
      recommendedWeekly: essentialWeekly + luxuryWeekly * 0.85,
      currentWeeklyPace: (essentialWindow + luxuryWindow) / weeks,
      essentialThisMonth: essentialThisMonth,
      luxuryThisMonth: luxuryThisMonth,
      monthIncome: monthIncome,
      monthSaved: monthSaved,
      savingsRate: savingsRate,
      dailyAllowanceRemaining: allowance,
      daysLeftInMonth: daysLeft,
      daysElapsed: dayOfMonth,
      txnCountThisMonth: txnCountThisMonth,
      avgTxnThisMonth:
          txnCountThisMonth > 0 ? spentThisMonth / txnCountThisMonth : 0,
      biggestExpense: biggestExpense,
      highestDay: highestDay,
      highestDayAmount: highestDayAmount,
      noSpendDays: noSpendDays < 0 ? 0 : noSpendDays,
      topWeekday: topWeekday,
      topWeekdayAvg: topWeekdayAvg,
      topCategories: topCategories.take(5).toList(),
      monthlyTrend: trend,
    );
  }

  /// How many times [weekday] falls between [from] and [to], inclusive.
  static int _countWeekday(DateTime from, DateTime to, int weekday) {
    var count = 0;
    var d = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    while (!d.isAfter(end)) {
      if (d.weekday == weekday) count++;
      d = d.add(const Duration(days: 1));
    }
    return count;
  }
}
