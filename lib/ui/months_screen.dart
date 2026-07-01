import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../domain/date_grouping.dart';
import 'month_detail_screen.dart';
import 'theme/tokens.dart';

/// Every month that has at least one transaction, newest first. Tapping a
/// month opens [MonthDetailScreen] for that month's totals and transactions.
class MonthsScreen extends StatelessWidget {
  const MonthsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    return Scaffold(
      appBar: AppBar(title: const Text('الأشهر')),
      body: StreamBuilder<List<MonthKey>>(
        stream: db.transactionDao.watchActiveMonths(),
        builder: (context, snapshot) {
          final months = snapshot.data ?? const <MonthKey>[];
          if (months.isEmpty) {
            return const Center(child: Text('لا توجد حركات بعد'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: months.length,
            itemBuilder: (context, i) {
              final month = months[i];
              return Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                child: ListTile(
                  title: Text(
                    monthLabel(month),
                    style: const TextStyle(
                        fontSize: AppTextSizes.row, fontWeight: FontWeight.w500),
                  ),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => MonthDetailScreen(month: month)),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
