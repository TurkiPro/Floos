import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../data/enums.dart';
import '../domain/date_grouping.dart';
import '../domain/financial_period.dart';
import 'theme/tokens.dart';
import 'widgets/day_group_card.dart';
import 'widgets/net_summary_card.dart';

/// Income/expense/net summary + day-grouped transaction list for one salary
/// cycle — the same shape as HomeScreen's body, generalized to any [cycle]
/// instead of always "this cycle". [label] is the cycle's title (a month name,
/// or a date range when it straddles two).
class MonthDetailScreen extends StatelessWidget {
  final FinancialPeriod cycle;
  final String label;
  const MonthDetailScreen(
      {super.key, required this.cycle, required this.label});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final money = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(title: Text(label)),
      body: StreamBuilder<List<TxnRow>>(
        stream: db.transactionDao.watchForRange(cycle.start, cycle.end),
        builder: (context, snapshot) {
          final rows = snapshot.data ?? const <TxnRow>[];
          double income = 0, expense = 0;
          for (final r in rows) {
            if (r.txn.type == TxnType.income) {
              income += r.txn.amount;
            } else {
              expense += r.txn.amount;
            }
          }
          final groups = groupByDay(rows, (r) => r.txn.date);
          final now = DateTime.now();

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              NetSummaryCard(
                  title: 'صافي الدورة',
                  income: income,
                  expense: expense,
                  money: money),
              const SizedBox(height: AppSpacing.lg),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                  child: Center(child: Text('لا توجد عمليات في هذه الدورة')),
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
        },
      ),
    );
  }
}
