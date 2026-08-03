import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../data/enums.dart';
import '../domain/savings_behavior.dart';
import 'theme/tokens.dart';

/// "سلوك الادخار" — how the user saves, all salary-cycle aligned: this cycle's
/// rate vs their norm, their streak and consistency, their best cycle and any
/// withdrawals, and a per-cycle trend. All derived from the contribution ledger.
class SavingsBehaviorScreen extends StatelessWidget {
  const SavingsBehaviorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final money = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(title: const Text('سلوك الادخار')),
      body: StreamBuilder<List<SavingsContribution>>(
        stream: db.savingsDao.watchAllContributions(),
        builder: (context, contribSnap) {
          final contributions =
              contribSnap.data ?? const <SavingsContribution>[];
          return StreamBuilder<List<TxnRow>>(
            stream: db.transactionDao.watchAllWithCategory(),
            builder: (context, txnSnap) {
              final rows = txnSnap.data ?? const <TxnRow>[];
              return StreamBuilder<List<RecurrenceRule>>(
                stream: db.recurrenceDao.watchByType(TxnType.income),
                builder: (context, rulesSnap) {
                  final incomeRules =
                      rulesSnap.data ?? const <RecurrenceRule>[];
                  if (contributions.every((c) => c.external)) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.xl),
                        child: Text(
                          'ابدأ بالإيداع في أهدافك وستظهر هنا عاداتك في الادخار.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  final b = savingsBehavior(
                    contributions: contributions,
                    rows: rows,
                    incomeRules: incomeRules,
                    now: DateTime.now(),
                  );
                  return ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      _rateCard(context, b, money),
                      const SizedBox(height: AppSpacing.md),
                      _streakCard(context, b),
                      const SizedBox(height: AppSpacing.md),
                      _bestAndWithdrawalsCard(context, b, money),
                      const SizedBox(height: AppSpacing.md),
                      _trendCard(context, b, money),
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

  // ---------------------------------------------------------------- helpers

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

  String _pct(double v) => '${(v * 100).toStringAsFixed(0)}٪';

  String _monthLabel(DateTime d) => DateFormat('yyyy-MM').format(d);

  // ---------------------------------------------------------------- cards

  Widget _rateCard(
      BuildContext context, SavingsBehavior b, NumberFormat money) {
    final scheme = Theme.of(context).colorScheme;
    final rate = b.rateThisCycle;
    final usual = b.usualRate;
    final up = rate != null && usual != null && rate > usual;
    final down = rate != null && usual != null && rate < usual;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, 'معدل الادخار هذه الدورة'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            rate == null ? '—' : _pct(rate),
            style: TextStyle(
                fontSize: AppTextSizes.heroMin,
                fontWeight: FontWeight.w700,
                color: scheme.primary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'ادّخرت ${money.format(b.savedThisCycle)} ⃁ من دخل هذه الدورة.',
            style: TextStyle(
                fontSize: AppTextSizes.label, color: scheme.onSurfaceVariant),
          ),
          if (usual != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(
                  up
                      ? Icons.trending_up
                      : (down ? Icons.trending_down : Icons.trending_flat),
                  size: 18,
                  color: up
                      ? AppColors.income
                      : (down ? Colors.red.shade400 : scheme.onSurfaceVariant),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    up
                        ? 'أعلى من معدلك المعتاد (${_pct(usual)})'
                        : (down
                            ? 'أقل من معدلك المعتاد (${_pct(usual)})'
                            : 'مطابق لمعدلك المعتاد (${_pct(usual)})'),
                    style: TextStyle(
                        fontSize: AppTextSizes.label,
                        color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
          const Divider(height: AppSpacing.xl),
          Row(
            children: [
              Icon(Icons.savings_outlined,
                  size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('متوسط ادخارك للدورة',
                    style: TextStyle(
                        fontSize: AppTextSizes.label,
                        color: scheme.onSurfaceVariant)),
              ),
              Text('${money.format(b.medianPerCycle)} ⃁',
                  style: const TextStyle(
                      fontSize: AppTextSizes.row, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _streakCard(BuildContext context, SavingsBehavior b) {
    final scheme = Theme.of(context).colorScheme;
    return _card(
      context,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label(context, 'سلسلة الادخار'),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  b.streak == 0
                      ? 'لا سلسلة حاليًا'
                      : '🔥 ${b.streak} ${_cyclesWord(b.streak)} متتالية',
                  style: const TextStyle(
                      fontSize: AppTextSizes.row, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  b.consistencyTotal == 0
                      ? 'لا دورات سابقة بعد'
                      : 'ادّخرت في ${b.consistencySaved} من آخر '
                          '${b.consistencyTotal} ${_cyclesWord(b.consistencyTotal)}',
                  style: TextStyle(
                      fontSize: AppTextSizes.label,
                      color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bestAndWithdrawalsCard(
      BuildContext context, SavingsBehavior b, NumberFormat money) {
    final scheme = Theme.of(context).colorScheme;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_outlined,
                  size: 18, color: AppColors.income),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('أفضل دورة',
                    style: TextStyle(
                        fontSize: AppTextSizes.label,
                        color: scheme.onSurfaceVariant)),
              ),
              Text(
                b.bestCycleStart == null
                    ? '—'
                    : '${money.format(b.bestCycleAmount)} ⃁'
                        ' • ${_monthLabel(b.bestCycleStart!)}',
                style: const TextStyle(
                    fontSize: AppTextSizes.label, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const Divider(height: AppSpacing.xl),
          Row(
            children: [
              Icon(Icons.north_east,
                  size: 18,
                  color: b.withdrawnRecently > 0
                      ? Colors.red.shade400
                      : scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('السحوبات من المدخرات',
                    style: TextStyle(
                        fontSize: AppTextSizes.label,
                        color: scheme.onSurfaceVariant)),
              ),
              Text(
                b.withdrawnRecently <= 0
                    ? 'لا شيء 👍'
                    : '${money.format(b.withdrawnRecently)} ⃁'
                        ' • ${b.withdrawalCycles} ${_cyclesWord(b.withdrawalCycles)}',
                style: TextStyle(
                    fontSize: AppTextSizes.label,
                    fontWeight: FontWeight.w700,
                    color:
                        b.withdrawnRecently > 0 ? Colors.red.shade400 : null),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _trendCard(
      BuildContext context, SavingsBehavior b, NumberFormat money) {
    final scheme = Theme.of(context).colorScheme;
    final maxAbs = b.trend
        .fold<double>(1, (m, p) => p.saved.abs() > m ? p.saved.abs() : m);
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, 'ادخارك عبر الدورات'),
          const SizedBox(height: AppSpacing.xs),
          Text('صافي ما ادّخرته كل دورة راتب',
              style: TextStyle(
                  fontSize: AppTextSizes.label,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final p in b.trend)
                  Expanded(
                    child: _bar(context, p, maxAbs, money),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(BuildContext context, SavingsCyclePoint p, double maxAbs,
      NumberFormat money) {
    final scheme = Theme.of(context).colorScheme;
    const half = 46.0; // max bar height on each side of the baseline
    final pos = p.saved > 0 ? (p.saved / maxAbs) * half : 0.0;
    final neg = p.saved < 0 ? (-p.saved / maxAbs) * half : 0.0;
    final color = p.saved < 0 ? Colors.red.shade400 : AppColors.income;
    final barColor = p.current ? scheme.primary : color;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        children: [
          // The value, tiny, above the bar.
          SizedBox(
            height: 16,
            child: FittedBox(
              child: Text(
                money.format(p.saved),
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          // Positive side.
          SizedBox(
            height: half,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: pos,
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ),
            ),
          ),
          Container(
              height: 1.5,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.35)),
          // Negative side.
          SizedBox(
            height: half,
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                height: neg,
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(4)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('M/yy').format(p.cycleStart),
            style: TextStyle(
              fontSize: 10,
              fontWeight: p.current ? FontWeight.w800 : FontWeight.w500,
              color: p.current ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _cyclesWord(int n) {
    if (n == 1) return 'دورة';
    if (n == 2) return 'دورتين';
    if (n >= 3 && n <= 10) return 'دورات';
    return 'دورة';
  }
}
