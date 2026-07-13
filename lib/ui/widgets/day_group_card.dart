import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/database.dart';
import '../../data/enums.dart';
import '../../domain/date_grouping.dart';
import '../theme/tokens.dart';
import 'transaction_row.dart';

/// One day's transactions on their own surface, so consecutive days read as
/// separate blocks. The header shows the weekday + date and that day's total.
///
/// Shared by every screen that lists transactions (home, month detail, income)
/// so they all share one layout. The total adapts to the day's contents:
/// spend-only days show the amount spent, income-only days show a green "+",
/// and mixed days show the net.
class DayGroupCard extends StatelessWidget {
  final MapEntry<DateTime, List<TxnRow>> group;
  final NumberFormat money;
  final DateTime today;
  const DayGroupCard({
    super.key,
    required this.group,
    required this.money,
    required this.today,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    double income = 0, expense = 0;
    for (final r in group.value) {
      if (r.txn.type == TxnType.income) {
        income += r.txn.amount;
      } else {
        expense += r.txn.amount;
      }
    }

    final String totalText;
    final Color totalColor;
    if (income == 0) {
      totalText = '${money.format(expense)} ر.س';
      totalColor = scheme.onSurface;
    } else if (expense == 0) {
      totalText = '+${money.format(income)} ر.س';
      totalColor = AppColors.income;
    } else {
      final net = income - expense;
      totalText = '${net >= 0 ? '+' : '-'}${money.format(net.abs())} ر.س';
      totalColor = net >= 0 ? AppColors.income : scheme.onSurface;
    }

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: const [AppShadows.card],
      ),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  dayFullLabel(group.key, today: today),
                  style: TextStyle(
                    fontSize: AppTextSizes.label,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                totalText,
                style: TextStyle(
                  fontSize: AppTextSizes.label,
                  fontWeight: FontWeight.w700,
                  color: totalColor,
                ),
              ),
            ],
          ),
          const Divider(height: AppSpacing.lg),
          ...group.value.map((r) => TransactionRow(row: r, money: money)),
        ],
      ),
    );
  }
}
