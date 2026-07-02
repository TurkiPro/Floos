import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../domain/savings_math.dart';
import 'add_contribution_sheet.dart';
import 'add_goal_sheet.dart';
import 'goal_detail_screen.dart';
import 'theme/tokens.dart';

class SavingsScreen extends StatelessWidget {
  const SavingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();

    return Scaffold(
      appBar: AppBar(title: const Text('الادخار')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => AddGoalSheet(db: db),
        ),
        icon: const Icon(Icons.add),
        label: const Text('هدف جديد'),
      ),
      body: StreamBuilder<List<SavingsGoal>>(
        stream: db.savingsDao.watchGoals(),
        builder: (context, snapshot) {
          final goals = snapshot.data ?? const <SavingsGoal>[];
          if (goals.isEmpty) {
            return const Center(child: Text('لا توجد أهداف ادخار بعد'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: goals.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _GoalCard(db: db, goal: goals[i]),
            ),
          );
        },
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final AppDatabase db;
  final SavingsGoal goal;
  const _GoalCard({required this.db, required this.goal});

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.00');
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<double>(
      // The only source for a goal's balance -- always SUM(contributions),
      // never a stored field.
      stream: db.savingsDao.watchTotal(goal.id),
      builder: (context, snapshot) {
        final total = snapshot.data ?? 0.0;
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
                  MaterialPageRoute(
                      builder: (_) => GoalDetailScreen(goal: goal)),
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
                              builder: (_) => AddContributionSheet(
                                  db: db, goalId: goal.id),
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
                          valueColor: AlwaysStoppedAnimation(
                              Theme.of(context)
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
      },
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
