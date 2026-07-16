import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_settings.dart';
import '../data/database.dart';
import '../data/enums.dart';
import '../domain/calendar_format.dart';
import '../domain/dashboard_summary.dart';
import '../domain/date_grouping.dart';
import '../domain/financial_period.dart';
import '../domain/parse_amount.dart';
import '../domain/recurrence_engine.dart';
import '../domain/recurrence_math.dart';
import '../domain/savings_math.dart';
import '../services/alerts_coordinator.dart';
import 'add_transaction_sheet.dart';
import 'income_screen.dart';
import 'savings_screen.dart';
import 'settings_screen.dart';
import 'statistics_screen.dart';
import 'theme/tokens.dart';
import 'widgets/day_group_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-run catch-up whenever the app returns to the foreground, so a
      // recurrence that came due while we were backgrounded shows up with no
      // manual refresh. The reactive list below updates itself on insert.
      final db = context.read<AppDatabase>();
      RecurrenceEngine(db).catchUp();
      // Re-arm the alert schedule and the icon badge against the fresh data.
      refreshAlerts(db, context.read<AppSettings>());
      // catchUp() above only triggers a rebuild via the stream if it actually
      // inserted a row, which isn't guaranteed on the exact day the month
      // rolls over. Force one so "current month" (re-read from
      // DateTime.now() at build time) reflects a possible rollover too.
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final money = NumberFormat('#,##0.00');
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      // A full-width bottom bar instead of a floating button, so it never
      // overlaps the transaction list or the dashboard figures.
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
            child: SizedBox(
              height: 50,
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  showDragHandle: true,
                  builder: (_) => AddTransactionSheet(db: db),
                ),
                icon: const Icon(Icons.add),
                label: const Text('إضافة عملية'),
              ),
            ),
          ),
        ),
      ),
      // One income-rules stream feeds both the header's salary countdown and
      // the salary-cycle financial period the dashboard figures are based on,
      // so they stay live as rules are added/paused/edited.
      body: StreamBuilder<List<RecurrenceRule>>(
        stream: db.recurrenceDao.watchByType(TxnType.income),
        builder: (context, rulesSnapshot) {
          final incomeRules = rulesSnapshot.data ?? const <RecurrenceRule>[];
          final now = DateTime.now();
          final period = financialPeriod(incomeRules, now);
          return Column(
            children: [
              _HomeHeader(
                onSettings: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
                onStats: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StatisticsScreen()),
                ),
                salaryHint: _salaryHint(incomeRules, now),
              ),
              // Three live streams feed the dashboard: all transactions (balance
              // + the period's income/spend + the expense list), all savings
              // contributions (total + the period's saved), and the goals (the
              // income-day deposit prompt).
              Expanded(
                child: StreamBuilder<List<TxnRow>>(
                  stream: db.transactionDao.watchAllWithCategory(),
                  builder: (context, txnSnapshot) {
                    final rows = txnSnapshot.data ?? const <TxnRow>[];
                    return StreamBuilder<List<SavingsContribution>>(
                      stream: db.savingsDao.watchAllContributions(),
                      builder: (context, savingsSnapshot) {
                        final contributions = savingsSnapshot.data ??
                            const <SavingsContribution>[];
                        return StreamBuilder<List<SavingsGoal>>(
                          stream: db.savingsDao.watchGoals(),
                          builder: (context, goalsSnapshot) {
                            final goals =
                                goalsSnapshot.data ?? const <SavingsGoal>[];
                            final data = DashboardSummary.from(
                                rows, contributions, period);
                            return _DashboardBody(
                              data: data,
                              money: money,
                              goals: goals,
                              contributions: contributions,
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// How long until the next salary lands, from the soonest upcoming occurrence
/// of any active recurring income rule. Null when no income recurs.
String? _salaryHint(List<RecurrenceRule> incomeRules, DateTime now) {
  final today = dateOnly(now);
  DateTime? soonest;
  for (final r in incomeRules) {
    if (!r.active) continue;
    // A pending next-payday override replaces this rule's upcoming occurrence,
    // so the countdown reflects the adjusted (early/late) date.
    final next = r.nextOverrideDate != null
        ? dateOnly(r.nextOverrideDate!)
        : nextOccurrence(
            startDate: r.startDate,
            frequency: r.frequency,
            interval: r.interval,
            endDate: r.endDate,
            // Exclusive of yesterday => an occurrence dated today still counts.
            afterExclusive: today.subtract(const Duration(days: 1)),
          );
    if (next == null) continue;
    if (soonest == null || next.isBefore(soonest)) soonest = next;
  }
  if (soonest == null) return null;

  final days = soonest.difference(today).inDays;
  // A little personality: the emoji and tone warm up as payday approaches.
  // Arabic plural grammar preserved (3–10 → أيام, 11+ → يومًا).
  if (days <= 0) return '🎉 نزل الراتب اليوم!';
  if (days == 1) return '🤑 الراتب غدًا!';
  if (days == 2) return '⏳ الراتب بعد يومين';
  if (days <= 6) return '🔥 باقي $days أيام على الراتب';
  if (days <= 10) return '🗓️ الراتب بعد $days أيام';
  return '⏳ الراتب بعد $days يومًا';
}

/// Stylised gradient header: accent gradient, the فلوس wordmark with a wallet
/// glyph, the current month + salary countdown, and a circular settings button.
class _HomeHeader extends StatelessWidget {
  final VoidCallback onSettings;
  final VoidCallback onStats;
  final String? salaryHint;
  const _HomeHeader({
    required this.onSettings,
    required this.onStats,
    this.salaryHint,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onAccent = scheme.onPrimary;
    final progress = Theme.of(context).extension<AccentPalette>()!.progress;
    final hijri = context.watch<AppSettings>().useHijri;
    final now = DateTime.now();
    final month = monthLabelFor(
      MonthKey(year: now.year, month: now.month),
      hijri: hijri,
    );

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(28),
        bottomRight: Radius.circular(28),
      ),
      child: Stack(
        children: [
          // Base diagonal gradient.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.primary,
                    Color.lerp(scheme.primary, progress, 0.5)!,
                    progress,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          // Reeded/fluted-glass texture: thin vertical ribs that modulate the
          // accent gradient with soft accent-tinted shadows and white
          // highlights. Kept very translucent so it reads as a subtle sheen,
          // and it re-tints itself whenever the accent changes.
          Positioned.fill(
            child: CustomPaint(
              painter: _FlutedGlassPainter(
                highlight: Colors.white.withValues(alpha: 0.025),
                groove: scheme.primary.withValues(alpha: 0.025),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
              child: Row(
                children: [
                  // Wordmark first => right side in RTL.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.account_balance_wallet_rounded,
                              color: onAccent, size: 28),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            'فلوس',
                            style: TextStyle(
                              color: onAccent,
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        salaryHint == null ? month : '$month  •  $salaryHint',
                        style: TextStyle(
                          color: onAccent.withValues(alpha: 0.85),
                          fontSize: AppTextSizes.label,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Stats then settings => both sit on the left in RTL.
                  _CircleButton(
                    icon: Icons.insights_outlined,
                    color: onAccent,
                    onTap: onStats,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _CircleButton(
                    icon: Icons.settings_outlined,
                    color: onAccent,
                    onTap: onSettings,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints the fluted-glass ribs: a repeating vertical gradient (shadow →
/// highlight → shadow) tiled every [fluteWidth] pixels, so each flute reads as
/// a soft ridge of light. Colors come from the caller (accent-derived), so the
/// texture recolors with the app's accent.
class _FlutedGlassPainter extends CustomPainter {
  final Color highlight;
  final Color groove;
  static const double fluteWidth = 7;
  const _FlutedGlassPainter({
    required this.highlight,
    required this.groove,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Isolate the ribs so the horizontal fade mask below only affects them,
    // not the gradient underneath.
    canvas.saveLayer(rect, Paint());
    final ribs = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      tileMode: TileMode.repeated,
      colors: [groove, highlight, groove],
      stops: const [0.0, 0.5, 1.0],
    ).createShader(
        Rect.fromLTWH(0, 0, _FlutedGlassPainter.fluteWidth, size.height));
    canvas.drawRect(rect, Paint()..shader = ribs);
    // Dissolve the ribs into the solid gradient toward the left: opaque on the
    // right (under the wordmark), transparent on the left.
    final fade = const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Colors.transparent, Colors.white],
      stops: [0.0, 0.6],
    ).createShader(rect);
    canvas.drawRect(
        rect,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = fade);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FlutedGlassPainter old) =>
      old.highlight != highlight || old.groove != groove;
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _CircleButton(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.16),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}

/// A goal that still needs this month's deposit, with the recomputed amount.
class _PendingDeposit {
  final SavingsGoal goal;
  final double monthly;
  const _PendingDeposit(this.goal, this.monthly);
}

class _DashboardBody extends StatelessWidget {
  final DashboardSummary data;
  final NumberFormat money;
  final List<SavingsGoal> goals;
  final List<SavingsContribution> contributions;
  const _DashboardBody({
    required this.data,
    required this.money,
    required this.goals,
    required this.contributions,
  });

  /// Goals still owed this month's deposit: income has landed, the goal has a
  /// deadline and isn't met, and the user hasn't already deposited or skipped
  /// it this month. Amounts are recomputed live from the saved total.
  List<_PendingDeposit> _pendingDeposits(BuildContext context, DateTime now) {
    if (!data.incomeReceivedThisMonth) return const [];
    final settings = context.watch<AppSettings>();
    bool inMonth(DateTime d) => d.year == now.year && d.month == now.month;

    final savedByGoal = <int, double>{};
    final contributedThisMonth = <int>{};
    for (final c in contributions) {
      savedByGoal[c.goalId] = (savedByGoal[c.goalId] ?? 0) + c.amount;
      if (inMonth(c.date)) contributedThisMonth.add(c.goalId);
    }

    final pending = <_PendingDeposit>[];
    for (final goal in goals) {
      if (goal.targetDate == null) continue;
      if (contributedThisMonth.contains(goal.id)) continue;
      if (settings.isDepositSkipped(goal.id, now)) continue;
      final monthly = suggestedMonthlyDeposit(
        target: goal.targetAmount,
        saved: savedByGoal[goal.id] ?? 0,
        deadline: goal.targetDate,
        now: now,
      );
      if (monthly != null && monthly > 0) {
        pending.add(_PendingDeposit(goal, monthly));
      }
    }
    return pending;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final groups = groupByDay(data.monthExpenses, (r) => r.txn.date);
    final pending = _pendingDeposits(context, now);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // No IntrinsicHeight/stretch: the hero value uses a FittedBox, whose
        // *intrinsic* height is the unscaled number — measuring it would reserve
        // that full height while it renders scaled-down, leaving a dead band
        // under each card. Content-sizing keeps the two cards tight and equal
        // (identical layout) on every screen size.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _TopCard(
                label: 'الرصيد',
                value: data.balance,
                money: money,
                icon: Icons.account_balance_wallet_outlined,
                valueColor: scheme.primary,
                emphasized: true,
                hint: 'الدخل',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const IncomeScreen()),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _TopCard(
                label: 'المدخرات',
                value: data.savingsTotal,
                money: money,
                icon: Icons.savings_outlined,
                valueColor: scheme.onSurface,
                emphasized: false,
                hint: 'الأهداف',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SavingsScreen()),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _MonthStatsCard(data: data, money: money),
        if (pending.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _SavingsPromptCard(pending: pending, money: money),
        ],
        const SizedBox(height: AppSpacing.lg),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs, 0, AppSpacing.xs, AppSpacing.sm),
          child: Text(
            'مصاريف هذا الشهر',
            style: TextStyle(
              fontSize: AppTextSizes.label,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        if (data.monthExpenses.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: Center(child: Text('لا توجد مصاريف هذا الشهر')),
          )
        else
          for (final group in groups) ...[
            DayGroupCard(
                key: ValueKey(group.key),
                group: group,
                money: money,
                today: now),
            const SizedBox(height: AppSpacing.md),
          ],
      ],
    );
  }
}

/// One of the two hero cards at the top. The budget card is [emphasized] with
/// a tinted accent background to read as the primary, tappable surface.
class _TopCard extends StatelessWidget {
  final String label;
  final double value;
  final NumberFormat money;
  final IconData icon;
  final Color valueColor;
  final bool emphasized;
  final String hint;
  final VoidCallback onTap;

  const _TopCard({
    required this.label,
    required this.value,
    required this.money,
    required this.icon,
    required this.valueColor,
    required this.emphasized,
    required this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = emphasized
        ? Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.08), scheme.surface)
        : scheme.surface;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: const [AppShadows.card],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 18, color: scheme.onSurfaceVariant),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        label,
                        style: TextStyle(
                            fontSize: AppTextSizes.label,
                            color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      '${money.format(value)} ⃁',
                      style: TextStyle(
                        fontSize: AppTextSizes.heroMin,
                        fontWeight: FontWeight.w700,
                        color: valueColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Text(
                        hint,
                        style: TextStyle(
                            fontSize: AppTextSizes.label,
                            color: scheme.primary,
                            fontWeight: FontWeight.w600),
                      ),
                      Icon(Icons.chevron_left, size: 16, color: scheme.primary),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// This month's split of income: what's left, what was spent, what was saved.
class _MonthStatsCard extends StatelessWidget {
  final DashboardSummary data;
  final NumberFormat money;
  const _MonthStatsCard({required this.data, required this.money});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remainingColor =
        data.monthRemaining >= 0 ? AppColors.income : Colors.red.shade400;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: const [AppShadows.card],
      ),
      child: Row(
        children: [
          _stat(context, 'المتبقي', data.monthRemaining, remainingColor),
          _divider(scheme),
          _stat(context, 'المصروف', data.monthSpent, scheme.onSurface),
          _divider(scheme),
          _stat(context, 'المدخّر', data.monthSaved, scheme.primary),
        ],
      ),
    );
  }

  Widget _divider(ColorScheme scheme) => Container(
        width: 1,
        height: 34,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.15),
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      );

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
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              money.format(value),
              style: TextStyle(
                  fontSize: AppTextSizes.row,
                  fontWeight: FontWeight.w700,
                  color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown once income has landed this month: for each goal still owed a
/// deposit, offer to transfer the full month's installment, a custom amount,
/// or skip (which recomputes next month's larger installment automatically).
class _SavingsPromptCard extends StatelessWidget {
  final List<_PendingDeposit> pending;
  final NumberFormat money;
  const _SavingsPromptCard({required this.pending, required this.money});

  Future<void> _deposit(
      BuildContext context, SavingsGoal goal, double amount) async {
    await context.read<AppDatabase>().savingsDao.addContribution(
          goalId: goal.id,
          amount: amount,
          date: DateTime.now(),
          note: 'إيداع شهري',
        );
  }

  Future<void> _depositCustom(BuildContext context, _PendingDeposit p) async {
    final ctrl = TextEditingController(text: p.monthly.toStringAsFixed(0));
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('إيداع في ${p.goal.name}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'المبلغ',
            suffixText: '⃁',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(parseAmount(ctrl.text)),
            child: const Text('إيداع'),
          ),
        ],
      ),
    );
    if (amount != null && amount > 0 && context.mounted) {
      await _deposit(context, p.goal, amount);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.08), scheme.surface),
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: const [AppShadows.card],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.savings_rounded, color: scheme.primary, size: 20),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'استلمت دخلك — خصّص لأهدافك',
                style: TextStyle(
                    fontSize: AppTextSizes.row,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final p in pending) ...[
            const Divider(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.goal.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        'الإيداع الشهري: ${money.format(p.monthly)} ⃁',
                        style: TextStyle(
                            fontSize: AppTextSizes.label,
                            color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                FilledButton(
                  onPressed: () => _deposit(context, p.goal, p.monthly),
                  child: const Text('إيداع كامل'),
                ),
                OutlinedButton(
                  onPressed: () => _depositCustom(context, p),
                  child: const Text('مبلغ آخر'),
                ),
                TextButton(
                  onPressed: () => context
                      .read<AppSettings>()
                      .skipDeposit(p.goal.id, DateTime.now()),
                  child: const Text('تخطّي هذا الشهر'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
