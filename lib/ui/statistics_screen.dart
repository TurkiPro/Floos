import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../data/enums.dart';
import '../domain/date_grouping.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('الإحصائيات')),
      // Categories resolve each transaction to its top-level parent + kind;
      // transactions carry the amounts.
      body: StreamBuilder<List<Category>>(
        stream: db.categoryDao.watchAll(),
        builder: (context, catSnap) {
          final cats = catSnap.data ?? const <Category>[];
          final byId = {for (final c in cats) c.id: c};
          return StreamBuilder<List<TxnRow>>(
            stream: db.transactionDao.watchAllWithCategory(),
            builder: (context, txnSnap) {
              final rows = txnSnap.data ?? const <TxnRow>[];
              final stats = _Stats.from(rows, byId, DateTime.now());
              if (stats.allExpenseCount == 0) {
                return const Center(child: Text('لا توجد بيانات كافية بعد'));
              }
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  _thisMonthCard(context, stats, money),
                  const SizedBox(height: AppSpacing.md),
                  _weeklyBudgetCard(context, stats, money),
                  const SizedBox(height: AppSpacing.md),
                  _essentialsCard(context, stats, money),
                  const SizedBox(height: AppSpacing.md),
                  _topCategoriesCard(context, stats, money, byId),
                  const SizedBox(height: AppSpacing.md),
                  _trendCard(context, stats, money),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _card(BuildContext context, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: const [AppShadows.card],
      ),
      child: child,
    );
  }

  Widget _label(BuildContext context, String text) => Text(
        text,
        style: TextStyle(
          fontSize: AppTextSizes.label,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );

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
          _splitBar(essentialPct),
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

  Widget _splitBar(double essentialPct) {
    return ClipRRect(
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
    final maxVal = s.monthlyTrend
        .fold<double>(1, (m, e) => e.value > m ? e.value : m);
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
                          Text(
                            money.format(e.value),
                            style: const TextStyle(fontSize: 9),
                            maxLines: 1,
                          ),
                          const SizedBox(height: 2),
                          Container(
                            height: (e.value / maxVal * 80).clamp(2, 80),
                            decoration: BoxDecoration(
                              color: scheme.primary
                                  .withValues(alpha: 0.85),
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

// (top-level id resolution uses category.parentId ?? category.id inline)

/// All statistics, computed once in a single pass.
class _Stats {
  final int allExpenseCount;
  final double spentThisMonth;
  final double dailyAvgThisMonth;
  final double projectedThisMonth;
  final double recommendedWeekly;
  final double currentWeeklyPace;
  final double essentialThisMonth;
  final double luxuryThisMonth;
  final List<MapEntry<int, double>> topCategories; // topLevelId -> amount
  final List<MapEntry<MonthKey, double>> monthlyTrend;

  const _Stats({
    required this.allExpenseCount,
    required this.spentThisMonth,
    required this.dailyAvgThisMonth,
    required this.projectedThisMonth,
    required this.recommendedWeekly,
    required this.currentWeeklyPace,
    required this.essentialThisMonth,
    required this.luxuryThisMonth,
    required this.topCategories,
    required this.monthlyTrend,
  });

  static _Stats from(
      List<TxnRow> rows, Map<int, Category> byId, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final dayOfMonth = now.day;
    final windowStart = today.subtract(const Duration(days: 84)); // 12 weeks

    var allExpenseCount = 0;
    var spentThisMonth = 0.0;
    var essentialThisMonth = 0.0, luxuryThisMonth = 0.0;
    var essentialWindow = 0.0, luxuryWindow = 0.0;
    DateTime? earliestInWindow;
    final byTop = <int, double>{};
    final byMonth = <MonthKey, double>{};

    bool inThisMonth(DateTime d) =>
        d.year == now.year && d.month == now.month;

    for (final r in rows) {
      if (r.txn.type != TxnType.expense) continue;
      allExpenseCount++;
      final amount = r.txn.amount;
      final date = r.txn.date;
      final kind = r.category.kind;

      // Monthly trend (last 6 calendar months).
      final mk = MonthKey(year: date.year, month: date.month);
      byMonth[mk] = (byMonth[mk] ?? 0) + amount;

      if (inThisMonth(date)) {
        spentThisMonth += amount;
        if (kind == CategoryKind.luxury) {
          luxuryThisMonth += amount;
        } else {
          essentialThisMonth += amount;
        }
        final topId = r.category.parentId ?? r.category.id;
        byTop[topId] = (byTop[topId] ?? 0) + amount;
      }

      if (!date.isBefore(windowStart) && !date.isAfter(today)) {
        if (kind == CategoryKind.luxury) {
          luxuryWindow += amount;
        } else {
          essentialWindow += amount;
        }
        if (earliestInWindow == null || date.isBefore(earliestInWindow)) {
          earliestInWindow = date;
        }
      }
    }

    final dailyAvg = dayOfMonth > 0 ? spentThisMonth / dayOfMonth : 0.0;
    final projected = dailyAvg * daysInMonth;

    // Weeks of history actually present in the window (so a new user with a
    // few days of data isn't averaged across a full 12 weeks).
    final windowDays = earliestInWindow == null
        ? 1
        : today.difference(earliestInWindow).inDays + 1;
    final weeks = (windowDays / 7).clamp(1.0, 12.0);
    final essentialWeekly = essentialWindow / weeks;
    final luxuryWeekly = luxuryWindow / weeks;
    final recommendedWeekly = essentialWeekly + luxuryWeekly * 0.85;
    final currentWeeklyPace = (essentialWindow + luxuryWindow) / weeks;

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
      recommendedWeekly: recommendedWeekly,
      currentWeeklyPace: currentWeeklyPace,
      essentialThisMonth: essentialThisMonth,
      luxuryThisMonth: luxuryThisMonth,
      topCategories: topCategories.take(5).toList(),
      monthlyTrend: trend,
    );
  }
}
