import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../domain/date_grouping.dart';
import '../domain/savings_math.dart';
import 'add_contribution_sheet.dart';
import 'add_goal_sheet.dart';
import 'goal_detail_screen.dart';
import 'theme/tokens.dart';
import 'widgets/day_section.dart';
import 'widgets/swipe_to_delete.dart';

class SavingsScreen extends StatelessWidget {
  const SavingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();

    final money = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(
        title: const Text('الادخار'),
        actions: [
          IconButton(
            tooltip: 'إيداع',
            icon: const Icon(Icons.add_card_outlined),
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              showDragHandle: true,
              builder: (_) => AddContributionSheet(db: db),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (_) => AddGoalSheet(db: db),
        ),
        icon: const Icon(Icons.add),
        label: const Text('هدف جديد'),
      ),
      body: StreamBuilder<List<SavingsGoal>>(
        stream: db.savingsDao.watchGoals(),
        builder: (context, goalsSnapshot) {
          final goals = goalsSnapshot.data ?? const <SavingsGoal>[];
          if (goals.isEmpty) {
            return const Center(child: Text('لا توجد أهداف ادخار بعد'));
          }
          final byId = {for (final g in goals) g.id: g};
          return StreamBuilder<List<SavingsContribution>>(
            stream: db.savingsDao.watchAllContributions(),
            builder: (context, contribSnapshot) {
              final contributions =
                  contribSnapshot.data ?? const <SavingsContribution>[];
              final scheme = Theme.of(context).colorScheme;
              // A goal's balance is always the sum of its contributions. We
              // already hold every contribution here, so fold the per-goal
              // totals once rather than opening a SUM stream per goal.
              final totalByGoal = <int, double>{};
              for (final c in contributions) {
                totalByGoal[c.goalId] = (totalByGoal[c.goalId] ?? 0) + c.amount;
              }
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  for (final g in goals)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _GoalCard(
                          db: db, goal: g, total: totalByGoal[g.id] ?? 0),
                    ),
                  if (contributions.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'آخر الإيداعات',
                      style: TextStyle(
                        fontSize: AppTextSizes.label,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    // Same day-card layout as every other dated list.
                    for (final day in groupByDay(
                        contributions.take(60).toList(), (c) => c.date)) ...[
                      DaySection(
                        day: day.key,
                        today: DateTime.now(),
                        totalText:
                            '+${money.format(day.value.fold<double>(0, (s, c) => s + c.amount))} ر.س',
                        totalColor: AppColors.income,
                        children: [
                          for (final c in day.value)
                            _DepositRow(
                              contribution: c,
                              goalName: byId[c.goalId]?.name ?? '—',
                              money: money,
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// One entry in the savings ledger: which goal it went to, its source note,
/// and the amount. The date lives in the day header above it.
class _DepositRow extends StatelessWidget {
  final SavingsContribution contribution;
  final String goalName;
  final NumberFormat money;
  const _DepositRow({
    required this.contribution,
    required this.goalName,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final scheme = Theme.of(context).colorScheme;
    final note = contribution.note ?? '';
    // Swipe-to-delete with undo, same as the transaction list and the goal
    // detail screen — a deposit is removable wherever it's shown.
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: SwipeToDelete(
        onDelete: () {
          final messenger = ScaffoldMessenger.of(context);
          final deleted = contribution;
          db.savingsDao.deleteContribution(deleted.id);
          messenger.showSnackBar(SnackBar(
            content: const Text('تم حذف الإيداع'),
            action: SnackBarAction(
              label: 'تراجع',
              onPressed: () => db.savingsDao.restoreContribution(deleted),
            ),
          ));
        },
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadii.tile),
              ),
              child: Icon(Icons.savings_outlined, color: scheme.primary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(goalName,
                      style: const TextStyle(
                          fontSize: AppTextSizes.row,
                          fontWeight: FontWeight.w500)),
                  if (note.isNotEmpty)
                    Text(
                      note,
                      style: TextStyle(
                          fontSize: AppTextSizes.label,
                          color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            Text(
              '+${money.format(contribution.amount)} ر.س',
              style: const TextStyle(
                  color: AppColors.income,
                  fontWeight: FontWeight.w600,
                  fontSize: AppTextSizes.row),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final AppDatabase db;
  final SavingsGoal goal;

  /// Summed once by the parent from the shared contributions stream — a goal's
  /// balance is always SUM(contributions), never a stored field.
  final double total;
  const _GoalCard({required this.db, required this.goal, required this.total});

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.00');
    final scheme = Theme.of(context).colorScheme;
    final ratio = goal.targetAmount > 0
        ? (total / goal.targetAmount).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: const [AppShadows.card],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => GoalDetailScreen(goal: goal)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          goal.name,
                          style: const TextStyle(
                              fontSize: AppTextSizes.row,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        tooltip: 'إضافة إيداع',
                        icon: Icon(Icons.add_circle_outline,
                            color: scheme.primary),
                        onPressed: () => showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          showDragHandle: true,
                          builder: (_) =>
                              AddContributionSheet(db: db, goalId: goal.id),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    // RTL note: a bare "X / Y" with two adjacent LTR
                    // number runs gets visually reordered by the bidi
                    // algorithm inside RTL text (confirmed by manual
                    // testing). Explicit RTL label words anchor each
                    // number to its own context and keep the reading
                    // order unambiguous.
                    'الحالي ${money.format(total)} ر.س  •  الهدف ${money.format(goal.targetAmount)} ر.س',
                    style: TextStyle(
                        fontSize: AppTextSizes.label,
                        color: scheme.onSurfaceVariant),
                  ),
                  if (goal.targetDate != null)
                    Text(
                      'بحلول: ${DateFormat('yyyy-MM-dd').format(goal.targetDate!)}',
                      style: TextStyle(
                          fontSize: AppTextSizes.label,
                          color: scheme.onSurfaceVariant),
                    ),
                  if (_monthlyLabel(goal, total, money) != null)
                    Text(
                      _monthlyLabel(goal, total, money)!,
                      style: TextStyle(
                        fontSize: AppTextSizes.label,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.chip),
                    child: LinearProgressIndicator(
                      value: ratio.toDouble(),
                      minHeight: 6,
                      backgroundColor:
                          scheme.onSurfaceVariant.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation(Theme.of(context)
                          .extension<AccentPalette>()!
                          .progress),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "الإيداع الشهري المقترح: X ر.س" -- the amount to deposit each month to
  /// hit the target by its deadline, recomputed from the live saved total.
  /// Null when the goal has no deadline or is already met.
  String? _monthlyLabel(SavingsGoal goal, double saved, NumberFormat money) {
    final monthly = suggestedMonthlyDeposit(
      target: goal.targetAmount,
      saved: saved,
      deadline: goal.targetDate,
      now: DateTime.now(),
    );
    if (monthly == null || monthly <= 0) return null;
    return 'الإيداع الشهري المقترح: ${money.format(monthly)} ر.س';
  }
}
