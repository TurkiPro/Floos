import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_settings.dart';
import '../data/database.dart';
import '../data/enums.dart';
import '../domain/calendar_format.dart';
import '../domain/period_summary.dart';
import 'month_detail_screen.dart';
import 'theme/tokens.dart';

/// Every salary cycle that has at least one transaction, newest first. Tapping a
/// cycle opens [MonthDetailScreen] for that cycle's totals and transactions. A
/// cycle that lines up with a calendar month reads as the month name; one that
/// straddles two shows its date range.
class MonthsScreen extends StatelessWidget {
  const MonthsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final hijri = context.watch<AppSettings>().useHijri;
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('الدورات')),
      body: StreamBuilder<List<TxnRow>>(
        stream: db.transactionDao.watchAllWithCategory(),
        builder: (context, txnSnap) {
          final rows = txnSnap.data ?? const <TxnRow>[];
          return StreamBuilder<List<RecurrenceRule>>(
            stream: db.recurrenceDao.watchByType(TxnType.income),
            builder: (context, rulesSnap) {
              final incomeRules = rulesSnap.data ?? const <RecurrenceRule>[];
              // Cycles that actually hold transactions (a contribution alone
              // doesn't make a "cycle to browse"), newest first.
              final cycles = cycleSummaries(rows, const [], incomeRules, now);
              if (cycles.isEmpty) {
                return const Center(child: Text('لا توجد عمليات بعد'));
              }
              return ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: cycles.length,
                itemBuilder: (context, i) {
                  final cycle = cycles[i].period;
                  final label = cycleLabelFor(cycle, hijri: hijri);
                  return Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: ListTile(
                      title: Text(
                        label,
                        style: const TextStyle(
                            fontSize: AppTextSizes.row,
                            fontWeight: FontWeight.w500),
                      ),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              MonthDetailScreen(cycle: cycle, label: label),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
