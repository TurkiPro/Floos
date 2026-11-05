import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app_settings.dart';
import '../../data/database.dart';
import '../../data/enums.dart';
import '../../services/alerts_coordinator.dart';
import '../add_transaction_sheet.dart';
import '../refund_sheet.dart';
import '../split_sheet.dart';
import '../theme/tokens.dart';
import 'category_icon_tile.dart';
import 'swipe_to_delete.dart';

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
    // A refund is stored as a negative expense: money coming back, shown as
    // such — never as "-(-50)".
    final isRefund = row.isRefund;
    final sign = isIncome || isRefund ? '+' : '-';
    final amountColor = isIncome || isRefund
        ? AppColors.income
        : Theme.of(context).colorScheme.onSurface;
    final refunded = row.refunded;
    final fullyRefunded = refunded > 0 && row.txn.amount - refunded < 0.005;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: SwipeToDelete(
        borderRadius: BorderRadius.circular(AppRadii.tile),
        onDelete: () {
          // Capture before the async gap — the row unmounts on delete.
          final settings = context.read<AppSettings>();
          final messenger = ScaffoldMessenger.of(context);
          final deleted = row.txn;
          db.transactionDao.deleteById(deleted.id).then((_) {
            // The badge/alert texts derive from spending; keep them in step.
            refreshAlerts(db, settings);
          });
          messenger.showSnackBar(SnackBar(
            content: const Text('تم حذف العملية'),
            action: SnackBarAction(
              label: 'تراجع',
              onPressed: () {
                db.transactionDao
                    .restore(deleted)
                    .then((_) => refreshAlerts(db, settings));
              },
            ),
          ));
        },
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.tile),
          // Tap to edit the entry in place — the way a salary's date is
          // corrected for the current or any past month.
          //
          // A part of a split purchase opens the split editor instead: the
          // parts share one date and note, so editing a part on its own would
          // pull the purchase apart.
          onTap: () async {
            Future<void> openSplit() => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  showDragHandle: true,
                  builder: (_) => SplitSheet(db: db, txnId: row.txn.id),
                );
            if (row.txn.splitGroupId != null) return openSplit();
            final result = await showModalBottomSheet<String>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              showDragHandle: true,
              builder: (_) => AddTransactionSheet(db: db, existing: row.txn),
            );
            if (result == AddTransactionSheet.split && context.mounted) {
              await openSplit();
            }
            if (result == AddTransactionSheet.refund && context.mounted) {
              await showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                showDragHandle: true,
                builder: (_) => RefundSheet(db: db, purchase: row.txn),
              );
            }
          },
          child: Row(
            children: [
              CategoryIconTile(
                  iconKey: row.category.iconKey,
                  colorValue: row.category.colorValue,
                  // A touch smaller than the default so the tile always sits
                  // comfortably inside the row's height — it never pokes past
                  // the red delete panel's rounded corners on a full swipe.
                  size: 36),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.category.name,
                      style: const TextStyle(
                          fontSize: AppTextSizes.row,
                          fontWeight: FontWeight.w500),
                    ),
                    if ((row.txn.note ?? '').isNotEmpty ||
                        row.txn.recurrenceId != null ||
                        row.txn.splitGroupId != null ||
                        isRefund ||
                        refunded > 0)
                      Text(
                        [
                          if (isRefund) 'استرداد',
                          if ((row.txn.note ?? '').isNotEmpty) row.txn.note!,
                          if (row.txn.recurrenceId != null) 'متكرر',
                          if (row.txn.splitGroupId != null)
                            'جزء من عملية مقسّمة',
                          if (fullyRefunded)
                            'مسترد بالكامل'
                          else if (refunded > 0)
                            'مسترد جزئيًا ${money.format(refunded)}',
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
                '$sign${money.format(row.txn.amount.abs())} ⃁',
                style: TextStyle(
                    color: amountColor,
                    fontWeight: FontWeight.w600,
                    fontSize: AppTextSizes.row),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
