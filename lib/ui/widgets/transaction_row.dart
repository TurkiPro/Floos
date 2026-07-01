import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/enums.dart';
import '../theme/tokens.dart';
import 'category_icon_tile.dart';

/// A single transaction row with swipe-to-delete. Shared by the home screen's
/// day-grouped list, the income screen, and month-detail browsing.
class TransactionRow extends StatelessWidget {
  final TxnRow row;
  final NumberFormat money;
  const TransactionRow({super.key, required this.row, required this.money});

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
