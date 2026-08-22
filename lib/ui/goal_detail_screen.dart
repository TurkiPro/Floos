import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../domain/savings_math.dart';
import 'add_contribution_sheet.dart';
import 'add_goal_sheet.dart';
import 'theme/tokens.dart';
import 'widgets/swipe_to_delete.dart';

class GoalDetailScreen extends StatelessWidget {
  final SavingsGoal goal;
  const GoalDetailScreen({super.key, required this.goal});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final money = NumberFormat('#,##0.00');
    final dateFmt = DateFormat('yyyy-MM-dd');

    // The goal is watched live (not the passed snapshot) so an edit shows here
    // in place, and a delete from the edit sheet drops us back to the list.
    return StreamBuilder<SavingsGoal?>(
      stream: db.savingsDao.watchGoal(goal.id),
      initialData: goal,
      builder: (context, goalSnap) {
        final g = goalSnap.data;
        if (g == null) {
          // Deleted — leave this screen.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final nav = Navigator.of(context);
            if (nav.canPop()) nav.pop();
          });
          return const Scaffold(body: SizedBox.shrink());
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(g.name),
            actions: [
              IconButton(
                tooltip: 'تعديل الهدف',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  showDragHandle: true,
                  builder: (_) => AddGoalSheet(db: db, existing: g),
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
              builder: (_) => AddContributionSheet(db: db, goalId: g.id),
            ),
            icon: const Icon(Icons.add),
            label: const Text('إيداع'),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                // The only source for this goal's balance -- always
                // SUM(contributions), never a stored field.
                child: StreamBuilder<List<SavingsContribution>>(
                  stream: db.savingsDao.watchContributions(g.id),
                  builder: (context, snapshot) {
                    final contributions =
                        snapshot.data ?? const <SavingsContribution>[];
                    final total =
                        contributions.fold<double>(0, (a, c) => a + c.amount);
                    final ratio = g.targetAmount > 0
                        ? (total / g.targetAmount).clamp(0.0, 1.0)
                        : 0.0;
                    // "At your recent pace, ≈ <date>." Only while the goal is
                    // still open and there's a real saving pace to project from.
                    final eta = ratio < 1
                        ? goalEta(
                            contributions: contributions,
                            target: g.targetAmount,
                            now: DateTime.now(),
                          )
                        : null;
                    final scheme = Theme.of(context).colorScheme;
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
                          Text(
                            '${money.format(total)} ⃁',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: AppTextSizes.heroMax,
                                fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'من ${money.format(g.targetAmount)} ⃁'
                            '${g.targetDate != null ? '  •  بحلول ${dateFmt.format(g.targetDate!)}' : ''}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: AppTextSizes.label,
                                color: scheme.onSurfaceVariant),
                          ),
                          if (eta != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'بهذه الوتيرة، تقريبًا ${dateFmt.format(eta)}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: AppTextSizes.label,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.primary),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.md),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadii.chip),
                            child: LinearProgressIndicator(
                              value: ratio.toDouble(),
                              minHeight: 8,
                              backgroundColor: scheme.onSurfaceVariant
                                  .withValues(alpha: 0.15),
                              valueColor: AlwaysStoppedAnimation(
                                  Theme.of(context)
                                      .extension<AccentPalette>()!
                                      .progress),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: StreamBuilder<List<SavingsContribution>>(
                  stream: db.savingsDao.watchContributions(g.id),
                  builder: (context, snapshot) {
                    final contributions =
                        snapshot.data ?? const <SavingsContribution>[];
                    if (contributions.isEmpty) {
                      return const Center(child: Text('لا توجد إيداعات بعد'));
                    }
                    return ListView.separated(
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      itemCount: contributions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final c = contributions[i];
                        // Swipe-to-delete with undo, matching how transactions
                        // are removed elsewhere. Deleting the row is all that's
                        // needed — the goal total and the home balance are SUMs
                        // over this ledger, so they correct themselves at once.
                        return SwipeToDelete(
                          // Keyed by contribution id so a delete removes this
                          // row, not a neighbour left holding the swipe state.
                          key: ValueKey(c.id),
                          borderRadius: BorderRadius.zero,
                          onDelete: () {
                            final messenger = ScaffoldMessenger.of(context);
                            final deleted = c;
                            db.savingsDao.deleteContribution(deleted.id);
                            messenger.showSnackBar(SnackBar(
                              content: const Text('تم حذف الإيداع'),
                              action: SnackBarAction(
                                label: 'تراجع',
                                onPressed: () =>
                                    db.savingsDao.restoreContribution(deleted),
                              ),
                            ));
                          },
                          child: ListTile(
                            // Tap to edit the deposit in place (amount, date,
                            // note, goal); the sheet also carries a delete.
                            onTap: () => showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              useSafeArea: true,
                              showDragHandle: true,
                              builder: (_) =>
                                  AddContributionSheet(db: db, existing: c),
                            ),
                            title: Text(
                              '${c.amount < 0 ? '−' : '+'}${money.format(c.amount.abs())} ⃁',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: c.amount < 0
                                    ? Colors.red.shade400
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            subtitle: Text([
                              dateFmt.format(c.date),
                              if ((c.note ?? '').isNotEmpty) c.note!,
                            ].join('  •  ')),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
