import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../data/enums.dart';
import '../data/export.dart';
import '../domain/date_grouping.dart';
import '../domain/recurrence_engine.dart';
import 'add_transaction_sheet.dart';
import 'category_editor_screen.dart';
import 'income_screen.dart';
import 'months_screen.dart';
import 'recurring_screen.dart';
import 'savings_screen.dart';
import 'theme/tokens.dart';
import 'widgets/net_summary_card.dart';
import 'widgets/transaction_row.dart';

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
      RecurrenceEngine(context.read<AppDatabase>()).catchUp();
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('فلوس'),
        actions: [
          IconButton(
            tooltip: 'الدخل',
            icon: const Icon(Icons.payments_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const IncomeScreen()),
            ),
          ),
          IconButton(
            tooltip: 'الادخار',
            icon: const Icon(Icons.savings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SavingsScreen()),
            ),
          ),
          PopupMenuButton<_HomeMenuAction>(
            tooltip: 'المزيد',
            onSelected: (action) async {
              switch (action) {
                case _HomeMenuAction.recurring:
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RecurringScreen()),
                  );
                  break;
                case _HomeMenuAction.months:
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MonthsScreen()),
                  );
                  break;
                case _HomeMenuAction.exportCsv:
                  final path = await exportTransactionsCsvToFile(db);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تم التصدير: $path')),
                    );
                  }
                  break;
                case _HomeMenuAction.categories:
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const CategoryEditorScreen()),
                  );
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                  value: _HomeMenuAction.recurring, child: Text('متكررة')),
              PopupMenuItem(
                  value: _HomeMenuAction.months, child: Text('الأشهر')),
              PopupMenuItem(
                  value: _HomeMenuAction.exportCsv, child: Text('تصدير CSV')),
              PopupMenuItem(
                  value: _HomeMenuAction.categories, child: Text('الفئات')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => AddTransactionSheet(db: db),
        ),
        icon: const Icon(Icons.add),
        label: const Text('إضافة'),
      ),
      body: StreamBuilder<List<TxnRow>>(
        stream: db.transactionDao.watchRecent(),
        builder: (context, snapshot) {
          final rows = snapshot.data ?? const <TxnRow>[];
          final now = DateTime.now();
          double income = 0, expense = 0;
          for (final r in rows) {
            if (r.txn.date.year == now.year && r.txn.date.month == now.month) {
              if (r.txn.type == TxnType.income) {
                income += r.txn.amount;
              } else {
                expense += r.txn.amount;
              }
            }
          }
          final groups = groupByDay(rows, (r) => r.txn.date);

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              NetSummaryCard(
                  title: 'صافي هذا الشهر',
                  income: income,
                  expense: expense,
                  money: money),
              const SizedBox(height: AppSpacing.lg),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                  child: Center(child: Text('لا توجد حركات بعد')),
                )
              else
                for (final group in groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xs, AppSpacing.md, AppSpacing.xs, AppSpacing.sm),
                    child: Text(
                      dayLabel(group.key, today: now),
                      style: TextStyle(
                        fontSize: AppTextSizes.label,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  ...group.value.map((r) => TransactionRow(row: r, money: money)),
                ],
            ],
          );
        },
      ),
    );
  }
}

enum _HomeMenuAction { recurring, months, exportCsv, categories }
