import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../data/enums.dart';
import '../domain/date_grouping.dart';
import '../domain/recurrence_engine.dart';
import 'add_transaction_sheet.dart';
import 'income_screen.dart';
import 'savings_screen.dart';
import 'settings_screen.dart';
import 'theme/tokens.dart';
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
            tooltip: 'الإعدادات',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
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
      // Two live streams feed the dashboard: all transactions (running balance
      // + this month's income/spend + the expense list) and all savings
      // contributions (running total saved + this month's saved).
      body: StreamBuilder<List<TxnRow>>(
        stream: db.transactionDao.watchAllWithCategory(),
        builder: (context, txnSnapshot) {
          final rows = txnSnapshot.data ?? const <TxnRow>[];
          return StreamBuilder<List<SavingsContribution>>(
            stream: db.savingsDao.watchAllContributions(),
            builder: (context, savingsSnapshot) {
              final contributions =
                  savingsSnapshot.data ?? const <SavingsContribution>[];
              final data = _Dashboard.from(rows, contributions);
              return _DashboardBody(data: data, money: money);
            },
          );
        },
      ),
    );
  }
}

/// Everything the home dashboard shows, computed once from the two streams.
/// [balance] is money neither spent nor set aside: all income − all expenses
/// − all savings. The monthly figures split this month's income into what's
/// left, what was spent, and what was saved.
class _Dashboard {
  final double balance;
  final double savingsTotal;
  final double monthRemaining;
  final double monthSpent;
  final double monthSaved;
  final List<TxnRow> monthExpenses;

  const _Dashboard({
    required this.balance,
    required this.savingsTotal,
    required this.monthRemaining,
    required this.monthSpent,
    required this.monthSaved,
    required this.monthExpenses,
  });

  static _Dashboard from(
    List<TxnRow> rows,
    List<SavingsContribution> contributions,
  ) {
    final now = DateTime.now();
    bool inMonth(DateTime d) => d.year == now.year && d.month == now.month;

    double allIncome = 0, allExpense = 0, monthIncome = 0, monthSpent = 0;
    final monthExpenses = <TxnRow>[];
    for (final r in rows) {
      final amount = r.txn.amount;
      if (r.txn.type == TxnType.income) {
        allIncome += amount;
        if (inMonth(r.txn.date)) monthIncome += amount;
      } else {
        allExpense += amount;
        if (inMonth(r.txn.date)) {
          monthSpent += amount;
          monthExpenses.add(r);
        }
      }
    }

    double allSaved = 0, monthSaved = 0;
    for (final c in contributions) {
      allSaved += c.amount;
      if (inMonth(c.date)) monthSaved += c.amount;
    }

    return _Dashboard(
      balance: allIncome - allExpense - allSaved,
      savingsTotal: allSaved,
      monthRemaining: monthIncome - monthSpent - monthSaved,
      monthSpent: monthSpent,
      monthSaved: monthSaved,
      monthExpenses: monthExpenses,
    );
  }
}

class _DashboardBody extends StatelessWidget {
  final _Dashboard data;
  final NumberFormat money;
  const _DashboardBody({required this.data, required this.money});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final groups = groupByDay(data.monthExpenses, (r) => r.txn.date);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _TopCard(
                  label: 'الرصيد',
                  value: data.balance,
                  money: money,
                  icon: Icons.account_balance_wallet_outlined,
                  valueColor: scheme.primary,
                  emphasized: true,
                  hint: 'الدخل',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const IncomeScreen()),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _TopCard(
                  label: 'المدخرات',
                  value: data.savingsTotal,
                  money: money,
                  icon: Icons.savings_outlined,
                  valueColor: scheme.onSurface,
                  emphasized: false,
                  hint: 'الأهداف',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SavingsScreen()),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _MonthStatsCard(data: data, money: money),
        const SizedBox(height: AppSpacing.lg),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs, 0, AppSpacing.xs, AppSpacing.sm),
          child: Text(
            'مصاريف هذا الشهر',
            style: TextStyle(
              fontSize: AppTextSizes.label,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        if (data.monthExpenses.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: Center(child: Text('لا توجد مصاريف هذا الشهر')),
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
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            ...group.value.map((r) => TransactionRow(row: r, money: money)),
          ],
      ],
    );
  }
}

/// One of the two hero cards at the top. The budget card is [emphasized] with
/// a tinted accent background to read as the primary, tappable surface.
class _TopCard extends StatelessWidget {
  final String label;
  final double value;
  final NumberFormat money;
  final IconData icon;
  final Color valueColor;
  final bool emphasized;
  final String hint;
  final VoidCallback onTap;

  const _TopCard({
    required this.label,
    required this.value,
    required this.money,
    required this.icon,
    required this.valueColor,
    required this.emphasized,
    required this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = emphasized
        ? Color.alphaBlend(scheme.primary.withValues(alpha: 0.08), scheme.surface)
        : scheme.surface;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: const [AppShadows.card],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 18, color: scheme.onSurfaceVariant),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        label,
                        style: TextStyle(
                            fontSize: AppTextSizes.label,
                            color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      '${money.format(value)} ر.س',
                      style: TextStyle(
                        fontSize: AppTextSizes.heroMin,
                        fontWeight: FontWeight.w700,
                        color: valueColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Text(
                        hint,
                        style: TextStyle(
                            fontSize: AppTextSizes.label,
                            color: scheme.primary,
                            fontWeight: FontWeight.w600),
                      ),
                      Icon(Icons.chevron_left, size: 16, color: scheme.primary),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// This month's split of income: what's left, what was spent, what was saved.
class _MonthStatsCard extends StatelessWidget {
  final _Dashboard data;
  final NumberFormat money;
  const _MonthStatsCard({required this.data, required this.money});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remainingColor =
        data.monthRemaining >= 0 ? AppColors.income : Colors.red.shade400;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: const [AppShadows.card],
      ),
      child: Row(
        children: [
          _stat(context, 'المتبقي', data.monthRemaining, remainingColor),
          _divider(scheme),
          _stat(context, 'المصروف', data.monthSpent, scheme.onSurface),
          _divider(scheme),
          _stat(context, 'المدخّر', data.monthSaved, scheme.primary),
        ],
      ),
    );
  }

  Widget _divider(ColorScheme scheme) => Container(
        width: 1,
        height: 34,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.15),
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      );

  Widget _stat(
      BuildContext context, String label, double value, Color color) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: AppTextSizes.label,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              money.format(value),
              style: TextStyle(
                  fontSize: AppTextSizes.row,
                  fontWeight: FontWeight.w700,
                  color: color),
            ),
          ),
        ],
      ),
    );
  }
}
