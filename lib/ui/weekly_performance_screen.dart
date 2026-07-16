import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../data/enums.dart';
import '../domain/financial_period.dart';
import '../domain/statistics_summary.dart';
import '../domain/weekly_performance.dart';
import 'theme/tokens.dart';

/// Week-by-week retrospective for the current salary cycle: each Saturday week
/// marked on/over budget with a bit of encouragement (or a nudge), and a spot
/// to jot down *why* — a reflection note saved per week.
class WeeklyPerformanceScreen extends StatelessWidget {
  const WeeklyPerformanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final money = NumberFormat('#,##0');
    // Numeric d/M — the app never loads locale month-name data.
    final dfmt = DateFormat('d/M');

    return Scaffold(
      appBar: AppBar(title: const Text('أدائي الأسبوعي')),
      body: StreamBuilder<List<RecurrenceRule>>(
        stream: db.recurrenceDao.watchByType(TxnType.income),
        builder: (context, rulesSnap) {
          final incomeRules = rulesSnap.data ?? const <RecurrenceRule>[];
          final now = DateTime.now();
          final period = financialPeriod(incomeRules, now);
          return StreamBuilder<List<TxnRow>>(
            stream: db.transactionDao.watchAllWithCategory(),
            builder: (context, txnSnap) {
              final rows = txnSnap.data ?? const <TxnRow>[];
              return StreamBuilder<List<SavingsContribution>>(
                stream: db.savingsDao.watchAllContributions(),
                builder: (context, contribSnap) {
                  final contributions =
                      contribSnap.data ?? const <SavingsContribution>[];
                  return StreamBuilder<List<WeeklyReflection>>(
                    stream: db.weeklyReflectionDao.watchAll(),
                    builder: (context, reflSnap) {
                      final notes = {
                        for (final r in (reflSnap.data ?? const []))
                          r.weekStart.millisecondsSinceEpoch: r.note,
                      };
                      return StreamBuilder<List<Category>>(
                        stream: db.categoryDao.watchAll(),
                        builder: (context, catSnap) {
                          final byId = {
                            for (final c
                                in (catSnap.data ?? const <Category>[]))
                              c.id: c
                          };
                          final s = StatisticsSummary.from(
                              rows, contributions, now, period);
                          final weeks = weeklyPerformance(
                            rows: rows,
                            byId: byId,
                            weeklyBudget: s.weeklyBaseline,
                            now: now,
                            periodStart: period.start,
                            periodEnd: period.end,
                          ).reversed.toList(); // newest week first

                          if (weeks.isEmpty || s.weeklyBaseline <= 0) {
                            return const Center(
                                child: Padding(
                              padding: EdgeInsets.all(AppSpacing.xl),
                              child: Text(
                                'لا تتوفر ميزانية أسبوعية بعد — تحتاج بضعة أسابيع من '
                                'الإنفاق حتى نحسب معدلك.',
                                textAlign: TextAlign.center,
                              ),
                            ));
                          }
                          return ListView(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            children: [
                              Text(
                                'كل أسبوع من دورتك الحالية مقابل ميزانيتك الأسبوعية '
                                '(${money.format(s.weeklyBaseline)} ⃁). اكتب ملاحظة '
                                'عن سبب التزامك أو تجاوزك.',
                                style: TextStyle(
                                    fontSize: AppTextSizes.label,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              for (final w in weeks) ...[
                                _WeekCard(
                                  week: w,
                                  note:
                                      notes[w.weekStart.millisecondsSinceEpoch],
                                  money: money,
                                  dfmt: dfmt,
                                  onEditNote: () => _editNote(
                                      context,
                                      db,
                                      w,
                                      notes[
                                          w.weekStart.millisecondsSinceEpoch]),
                                ),
                                const SizedBox(height: AppSpacing.md),
                              ],
                            ],
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

  Future<void> _editNote(BuildContext context, AppDatabase db,
      WeekPerformance week, String? current) async {
    final ctrl = TextEditingController(text: current ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ملاحظة الأسبوع ${week.index}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'لماذا التزمت أو تجاوزت هذا الأسبوع؟',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await db.weeklyReflectionDao.setNote(week.weekStart, result);
  }
}

class _WeekCard extends StatelessWidget {
  final WeekPerformance week;
  final String? note;
  final NumberFormat money;
  final DateFormat dfmt;
  final VoidCallback onEditNote;
  const _WeekCard({
    required this.week,
    required this.note,
    required this.money,
    required this.dfmt,
    required this.onEditNote,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final over = week.over;
    final color = over ? Colors.red.shade400 : AppColors.income;
    // Encouragement, softened for the still-running week.
    final badge = week.current
        ? (over ? '⚠️ تتجاوز حتى الآن' : '🎉 على المسار')
        : (over ? '⚠️ تجاوزت' : '🎉 أحسنت');
    final ratio = week.budget > 0 ? (week.spent / week.budget) : 0.0;

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الأسبوع ${week.index}${week.current ? ' • الحالي' : ''}',
                      style: const TextStyle(
                          fontSize: AppTextSizes.row,
                          fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${dfmt.format(week.weekStart)} – '
                      '${dfmt.format(week.windowEnd.subtract(const Duration(days: 1)))}',
                      style: TextStyle(
                          fontSize: AppTextSizes.label,
                          color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadii.chip),
                ),
                child: Text(badge,
                    style: TextStyle(
                        fontSize: AppTextSizes.label,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  'أنفقت ${money.format(week.spent)} من '
                  '${money.format(week.budget)} ⃁',
                  style: TextStyle(
                      fontSize: AppTextSizes.label,
                      color: over ? Colors.red.shade400 : scheme.onSurface,
                      fontWeight: over ? FontWeight.w700 : FontWeight.normal),
                ),
              ),
              Text(
                '${week.delta >= 0 ? '+' : '−'}${money.format(week.delta.abs())} ⃁',
                style: TextStyle(
                    fontSize: AppTextSizes.label,
                    fontWeight: FontWeight.w700,
                    color: color),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.chip),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0).toDouble(),
              minHeight: 6,
              backgroundColor: scheme.onSurfaceVariant.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          if (week.days.any((d) => d.total > 0)) ...[
            const SizedBox(height: AppSpacing.md),
            _DailyBars(days: week.days, money: money),
          ],
          const Divider(height: AppSpacing.xl),
          InkWell(
            borderRadius: BorderRadius.circular(AppRadii.tile),
            onTap: onEditNote,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Icon(note == null ? Icons.add_comment_outlined : Icons.notes,
                      size: 18, color: scheme.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      note ?? 'أضف ملاحظة — لماذا؟',
                      style: TextStyle(
                          fontSize: AppTextSizes.label,
                          color:
                              note == null ? scheme.primary : scheme.onSurface),
                    ),
                  ),
                  if (note != null)
                    Icon(Icons.edit_outlined,
                        size: 16, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A little bar per day of the week: bar height is that day's discretionary
/// total (relative to the week's busiest day), and each bar is a stack coloured
/// by category — the share of each category's spending that day. Empty days show
/// a faint stub. The date sits under each bar.
class _DailyBars extends StatelessWidget {
  final List<DaySpend> days;
  final NumberFormat money;
  const _DailyBars({required this.days, required this.money});

  static const _maxBarPx = 56.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxTotal = days.fold<double>(0, (m, d) => d.total > m ? d.total : m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('الإنفاق اليومي',
            style: TextStyle(
                fontSize: AppTextSizes.label, color: scheme.onSurfaceVariant)),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final d in days)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: _maxBarPx,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [_bar(context, d, maxTotal)],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text('${d.date.day}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 8, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        // Legend: which colour is which category (so the crammed bars are
        // readable). Categories that appear in the week, biggest first.
        if (_legend().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: 6,
            children: [
              for (final item in _legend())
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: Color(item.colorValue),
                          shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(item.name,
                        style: TextStyle(
                            fontSize: AppTextSizes.label,
                            color: scheme.onSurfaceVariant)),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// Distinct top categories spent in this week, summed and biggest first, for
  /// the colour legend.
  List<DaySlice> _legend() {
    final totals = <int, double>{};
    final byId = <int, DaySlice>{};
    for (final d in days) {
      for (final s in d.slices) {
        totals[s.categoryId] = (totals[s.categoryId] ?? 0) + s.amount;
        byId[s.categoryId] = s;
      }
    }
    final ids = totals.keys.toList()
      ..sort((a, b) => totals[b]!.compareTo(totals[a]!));
    return [for (final id in ids) byId[id]!];
  }

  Widget _bar(BuildContext context, DaySpend d, double maxTotal) {
    final scheme = Theme.of(context).colorScheme;
    if (maxTotal <= 0 || d.total <= 0) {
      return Container(
        height: 3,
        decoration: BoxDecoration(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }
    final h = (d.total / maxTotal * _maxBarPx).clamp(4.0, _maxBarPx);
    return SizedBox(
      height: h,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final s in d.slices)
              Expanded(
                flex: (s.amount / d.total * 1000).round().clamp(1, 1000),
                child: ColoredBox(color: Color(s.colorValue)),
              ),
          ],
        ),
      ),
    );
  }
}
