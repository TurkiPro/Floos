import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../data/enums.dart';
import '../domain/date_grouping.dart';
import 'theme/tokens.dart';
import 'widgets/day_group_card.dart';
import 'widgets/net_summary_card.dart';

/// Income/expense/net summary + day-grouped transaction list for one
/// arbitrary month -- the same shape as HomeScreen's body, generalized to any
/// [month] instead of always "this month".
class MonthDetailScreen extends StatelessWidget {
  final MonthKey month;
  const MonthDetailScreen({super.key, required this.month});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final money = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(title: Text(monthLabel(month))),
      body: StreamBuilder<List<TxnRow>>(
        stream: db.transactionDao.watchForMonth(month),
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
                  title: 'صافي الشهر',
                  income: income,
                  expense: expense,
                  money: money),
              const SizedBox(height: AppSpacing.lg),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                  child: Center(child: Text('لا توجد حركات في هذا الشهر')),
                )
              else
                for (final group in groups) ...[
                  DayGroupCard(group: group, money: money, today: now),
                  const SizedBox(height: AppSpacing.md),
                ],
            ],
          );
        },
      ),
    );
  }
}
