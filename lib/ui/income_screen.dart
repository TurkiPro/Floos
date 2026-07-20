import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_settings.dart';
import '../data/database.dart';
import '../data/enums.dart';
import '../domain/balance_transfers.dart';
import '../domain/date_grouping.dart';
import '../domain/recurrence_engine.dart';
import '../domain/recurrence_math.dart';
import '../services/alerts_coordinator.dart';
import 'add_income_sheet.dart';
import 'add_recurrence_sheet.dart';
import 'recurring_screen.dart' show frequencyLabelAr;
import 'theme/tokens.dart';
import 'widgets/day_group_card.dart';

/// Dedicated income page: recent one-off income entries, plus a list of
/// recurring incomes (each independently named and dated) that can be
/// edited, paused, or deleted.
class IncomeScreen extends StatelessWidget {
  const IncomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final money = NumberFormat('#,##0.00');
    final dateFmt = DateFormat('yyyy-MM-dd');

    return Scaffold(
      appBar: AppBar(title: const Text('الدخل')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (_) => AddIncomeSheet(db: db),
        ),
        icon: const Icon(Icons.add),
        label: const Text('إضافة دخل'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(
            'الدخل المتكرر',
            style: TextStyle(
              fontSize: AppTextSizes.label,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          StreamBuilder<List<RecurrenceRule>>(
            stream: db.recurrenceDao.watchByType(TxnType.income),
            builder: (context, snapshot) {
              final rules = snapshot.data ?? const <RecurrenceRule>[];
              if (rules.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text('لا يوجد دخل متكرر بعد'),
                );
              }
              return Column(
                children: [
                  for (final r in rules)
                    Card(
                      margin: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                        isThreeLine: true,
                        onTap: () => showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          showDragHandle: true,
                          builder: (_) =>
                              AddRecurrenceSheet(db: db, existingRule: r),
                        ),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.income.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadii.tile),
                          ),
                          child: const Icon(Icons.south_west,
                              color: AppColors.income),
                        ),
                        title: Text(
                          r.title,
                          style: const TextStyle(
                              fontSize: AppTextSizes.row,
                              fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(_subtitleFor(r, money, dateFmt)),
                        trailing: Switch(
                          value: r.active,
                          onChanged: (v) async {
                            if (v) {
                              await db.recurrenceDao.reactivate(r.id);
                              await RecurrenceEngine(db).catchUp();
                            } else {
                              await db.recurrenceDao.pause(r.id);
                            }
                            if (context.mounted) {
                              refreshAlerts(db, context.read<AppSettings>());
                            }
                          },
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'آخر الدخل',
            style: TextStyle(
              fontSize: AppTextSizes.label,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          StreamBuilder<List<TxnRow>>(
            stream: db.transactionDao.watchRecent(),
            builder: (context, snapshot) {
              final rows = (snapshot.data ?? const <TxnRow>[])
                  .where((r) => r.txn.type == TxnType.income)
                  .toList();
              if (rows.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                  child: Center(child: Text('لا توجد عمليات دخل بعد')),
                );
              }
              final groups = groupByDay(rows, (r) => r.txn.date);
              final now = DateTime.now();
              return Column(
                children: [
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
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'التحويلات (الادخار والاستثمار)',
            style: TextStyle(
              fontSize: AppTextSizes.label,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Money moved between the balance and savings/investments, so the
          // balance page explains what left it (or came back) beyond income.
          StreamBuilder<List<SavingsGoal>>(
            stream: db.savingsDao.watchGoals(),
            builder: (context, goalsSnap) {
              final goalNames = {
                for (final g in (goalsSnap.data ?? const <SavingsGoal>[]))
                  g.id: g.name
              };
              return StreamBuilder<List<SavingsContribution>>(
                stream: db.savingsDao.watchAllContributions(),
                builder: (context, contribSnap) {
                  return StreamBuilder<List<Investment>>(
                    stream: db.investmentDao.watchAll(),
                    builder: (context, invSnap) {
                      final transfers = balanceTransfers(
                        contributions:
                            contribSnap.data ?? const <SavingsContribution>[],
                        investments: invSnap.data ?? const <Investment>[],
                        goalNames: goalNames,
                      );
                      if (transfers.isEmpty) {
                        return const Padding(
                          padding:
                              EdgeInsets.symmetric(vertical: AppSpacing.md),
                          child: Text('لا توجد تحويلات بعد'),
                        );
                      }
                      return Column(
                        children: [
                          for (final t in transfers.take(40))
                            _TransferRow(transfer: t, money: money),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  String _subtitleFor(
      RecurrenceRule r, NumberFormat money, DateFormat dateFmt) {
    // A pending next-payday override replaces the computed next occurrence, so
    // "التالي" here matches the home countdown and the salary alert.
    final next = !r.active
        ? null
        : (r.nextOverrideDate ??
            nextOccurrence(
              startDate: r.startDate,
              frequency: r.frequency,
              interval: r.interval,
              endDate: r.endDate,
              afterExclusive: r.lastMaterialized ??
                  dateOnly(r.startDate).subtract(const Duration(days: 1)),
            ));
    final subtitle = StringBuffer()
      ..write(
          '${money.format(r.amount)} ⃁  •  ${frequencyLabelAr(r.frequency)}');
    if (r.interval > 1) subtitle.write(' (كل ${r.interval})');
    if (r.active && next != null) {
      subtitle.write('\nالتالي: ${dateFmt.format(next)}');
    } else if (!r.active) {
      subtitle.write('\nمتوقفة');
    }
    return subtitle.toString();
  }
}

/// One balance transfer to/from savings or investments, from the balance's
/// point of view: an outflow (money into savings/investing) shows red and
/// negative; an inflow (a withdrawal/sell coming back) shows green and positive.
class _TransferRow extends StatelessWidget {
  final BalanceTransfer transfer;
  final NumberFormat money;
  const _TransferRow({required this.transfer, required this.money});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inflow = transfer.amount >= 0; // + = came back to the balance
    final tint = inflow ? AppColors.income : Colors.red.shade400;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.tile),
            ),
            child: Icon(
                transfer.savings ? Icons.savings_outlined : Icons.trending_up,
                color: tint),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(transfer.label,
                    style: const TextStyle(
                        fontSize: AppTextSizes.row,
                        fontWeight: FontWeight.w500)),
                Text(DateFormat('yyyy-MM-dd').format(transfer.date),
                    style: TextStyle(
                        fontSize: AppTextSizes.label,
                        color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Text(
            '${inflow ? '+' : '−'}${money.format(transfer.amount.abs())} ⃁',
            style: TextStyle(
                color: tint,
                fontWeight: FontWeight.w600,
                fontSize: AppTextSizes.row),
          ),
        ],
      ),
    );
  }
}
