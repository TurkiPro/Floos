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
import 'recurring_screen.dart';
import 'savings_screen.dart';
import 'theme/tokens.dart';
import 'widgets/category_icon_tile.dart';

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
              _NetThisMonthCard(income: income, expense: expense, money: money),
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
                  ...group.value.map((r) => _TransactionRow(row: r, money: money)),
                ],
            ],
          );
        },
      ),
    );
  }
}

enum _HomeMenuAction { recurring, exportCsv, categories }

class _NetThisMonthCard extends StatelessWidget {
  final double income;
  final double expense;
  final NumberFormat money;
  const _NetThisMonthCard({
    required this.income,
    required this.expense,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    final net = income - expense;
    final spentRatio = income > 0
        ? (expense / income).clamp(0.0, 1.0)
        : (expense > 0 ? 1.0 : 0.0);
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
            'صافي هذا الشهر',
            style: TextStyle(
                fontSize: AppTextSizes.label, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${money.format(net)} ر.س',
            style: TextStyle(
              fontSize: AppTextSizes.heroMax,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.chip),
            child: LinearProgressIndicator(
              value: spentRatio.toDouble(),
              minHeight: 6,
              backgroundColor: scheme.onSurfaceVariant.withValues(alpha: 0.15),
              valueColor:
                  const AlwaysStoppedAnimation(AppColors.brandProgress),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _stat(context, 'الدخل', income, AppColors.income),
              const SizedBox(width: AppSpacing.lg),
              _stat(context, 'المصروف', expense, scheme.onSurface),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, double value, Color color) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: AppTextSizes.label, color: scheme.onSurfaceVariant)),
          Text('${money.format(value)} ر.س',
              style: TextStyle(
                  fontSize: AppTextSizes.row,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final TxnRow row;
  final NumberFormat money;
  const _TransactionRow({required this.row, required this.money});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final isIncome = row.txn.type == TxnType.income;
    final sign = isIncome ? '+' : '-';
    final amountColor =
        isIncome ? AppColors.income : Theme.of(context).colorScheme.onSurface;

    return Dismissible(
      key: ValueKey(row.txn.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        alignment: AlignmentDirectional.centerStart,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => db.transactionDao.deleteById(row.txn.id),
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(
          children: [
            CategoryIconTile(iconKey: row.category.iconKey),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.category.name,
                    style: const TextStyle(
                        fontSize: AppTextSizes.row, fontWeight: FontWeight.w500),
                  ),
                  if ((row.txn.note ?? '').isNotEmpty ||
                      row.txn.recurrenceId != null)
                    Text(
                      [
                        if ((row.txn.note ?? '').isNotEmpty) row.txn.note!,
                        if (row.txn.recurrenceId != null) 'متكرر',
                      ].join('  •  '),
                      style: TextStyle(
                        fontSize: AppTextSizes.label,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              '$sign${money.format(row.txn.amount)} ر.س',
              style: TextStyle(
                  color: amountColor,
                  fontWeight: FontWeight.w600,
                  fontSize: AppTextSizes.row),
            ),
          ],
        ),
      ),
    );
  }
}
