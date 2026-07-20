import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../domain/date_grouping.dart';
import 'add_investment_sheet.dart';
import 'theme/tokens.dart';
import 'widgets/day_section.dart';
import 'widgets/swipe_to_delete.dart';

/// A manual portfolio: money put into stocks, funds, etc., tracked apart from
/// expenses (it's not spending). Only the amount put in is recorded — no live
/// prices, no networking. Non-standalone entries come out of the balance like a
/// savings deposit; a standalone entry is money already invested elsewhere.
class InvestmentsScreen extends StatelessWidget {
  const InvestmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final money = NumberFormat('#,##0.00');
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('الاستثمارات')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (_) => AddInvestmentSheet(db: db),
        ),
        icon: const Icon(Icons.add),
        label: const Text('استثمار جديد'),
      ),
      body: StreamBuilder<List<Investment>>(
        stream: db.investmentDao.watchAll(),
        builder: (context, snap) {
          final items = snap.data ?? const <Investment>[];
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'لا توجد استثمارات بعد.\nأضف أسهمك أو صناديقك لتتبّعها بعيدًا عن المصاريف.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final total = items.fold<double>(0, (s, i) => s + i.amount);
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                      scheme.primary.withValues(alpha: 0.08), scheme.surface),
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  boxShadow: const [AppShadows.card],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.trending_up,
                            color: scheme.primary, size: 18),
                        const SizedBox(width: AppSpacing.xs),
                        Text('إجمالي المستثمَر',
                            style: TextStyle(
                                fontSize: AppTextSizes.label,
                                color: scheme.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text('${money.format(total)} ⃁',
                        style: TextStyle(
                            fontSize: AppTextSizes.heroMin,
                            fontWeight: FontWeight.w700,
                            color: scheme.primary)),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              for (final day in groupByDay(items, (i) => i.date)) ...[
                DaySection(
                  day: day.key,
                  today: DateTime.now(),
                  totalText:
                      '${money.format(day.value.fold<double>(0, (s, i) => s + i.amount))} ⃁',
                  totalColor: scheme.primary,
                  children: [
                    for (final inv in day.value)
                      _InvestmentRow(
                          key: ValueKey(inv.id), investment: inv, money: money),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _InvestmentRow extends StatelessWidget {
  final Investment investment;
  final NumberFormat money;
  const _InvestmentRow(
      {super.key, required this.investment, required this.money});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final scheme = Theme.of(context).colorScheme;
    final note = investment.note ?? '';
    final sub = [
      if (investment.external) 'مستقل',
      if (note.isNotEmpty) note,
    ].join('  •  ');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: SwipeToDelete(
        onDelete: () {
          final messenger = ScaffoldMessenger.of(context);
          final deleted = investment;
          db.investmentDao.deleteInvestment(deleted.id);
          messenger.showSnackBar(SnackBar(
            content: const Text('تم حذف الاستثمار'),
            action: SnackBarAction(
              label: 'تراجع',
              onPressed: () => db.investmentDao.restore(deleted),
            ),
          ));
        },
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.tile),
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            builder: (_) => AddInvestmentSheet(db: db, existing: investment),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.tile),
                ),
                child: Icon(Icons.trending_up, color: scheme.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(investment.name,
                        style: const TextStyle(
                            fontSize: AppTextSizes.row,
                            fontWeight: FontWeight.w500)),
                    if (sub.isNotEmpty)
                      Text(sub,
                          style: TextStyle(
                              fontSize: AppTextSizes.label,
                              color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Text('${money.format(investment.amount)} ⃁',
                  style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: AppTextSizes.row)),
            ],
          ),
        ),
      ),
    );
  }
}
