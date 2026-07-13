import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../data/enums.dart';
import '../domain/date_grouping.dart';
import '../domain/recurrence_engine.dart';
import '../domain/recurrence_math.dart';
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
                  child: Center(child: Text('لا توجد حركات دخل بعد')),
                );
              }
              final groups = groupByDay(rows, (r) => r.txn.date);
              final now = DateTime.now();
              return Column(
                children: [
                  for (final group in groups) ...[
                    DayGroupCard(group: group, money: money, today: now),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _subtitleFor(
      RecurrenceRule r, NumberFormat money, DateFormat dateFmt) {
    final next = r.active
        ? nextOccurrence(
            startDate: r.startDate,
            frequency: r.frequency,
            interval: r.interval,
            endDate: r.endDate,
            afterExclusive: r.lastMaterialized ??
                dateOnly(r.startDate).subtract(const Duration(days: 1)),
          )
        : null;
    final subtitle = StringBuffer()
      ..write(
          '${money.format(r.amount)} ر.س  •  ${frequencyLabelAr(r.frequency)}');
    if (r.interval > 1) subtitle.write(' (كل ${r.interval})');
    if (r.active && next != null) {
      subtitle.write('\nالتالي: ${dateFmt.format(next)}');
    } else if (!r.active) {
      subtitle.write('\nمتوقفة');
    }
    return subtitle.toString();
  }
}
