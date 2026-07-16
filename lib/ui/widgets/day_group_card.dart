import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/database.dart';
import '../../data/enums.dart';
import '../theme/tokens.dart';
import 'day_section.dart';
import 'transaction_row.dart';

/// A [DaySection] filled with one day's transactions. The total adapts to the
/// day's contents: spend-only days show the amount spent, income-only days show
/// a green "+", and mixed days show the net.
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
      totalText = '${money.format(expense)} ⃁';
      totalColor = scheme.onSurface;
    } else if (expense == 0) {
      totalText = '+${money.format(income)} ⃁';
      totalColor = AppColors.income;
    } else {
      final net = income - expense;
      totalText = '${net >= 0 ? '+' : '-'}${money.format(net.abs())} ⃁';
      totalColor = net >= 0 ? AppColors.income : scheme.onSurface;
    }

    return DaySection(
      day: group.key,
      today: today,
      totalText: totalText,
      totalColor: totalColor,
      children: [
        // Key each row by its transaction id so deleting one removes *its*
        // widget instead of leaving a neighbour holding the finished
        // swipe-to-delete state (a stuck red panel until the app restarts).
        ...group.value.map((r) =>
            TransactionRow(key: ValueKey(r.txn.id), row: r, money: money)),
      ],
    );
  }
}
