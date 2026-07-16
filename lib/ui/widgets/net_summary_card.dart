import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/tokens.dart';

/// Income/expense/net summary card for a period (a month, typically). [title]
/// names the period ("صافي هذا الشهر", "صافي الشهر", ...) so this one widget
/// serves both the home screen (current month) and month-detail browsing (an
/// arbitrary past month).
class NetSummaryCard extends StatelessWidget {
  final String title;
  final double income;
  final double expense;
  final NumberFormat money;
  const NetSummaryCard({
    super.key,
    required this.title,
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
            title,
            style: TextStyle(
                fontSize: AppTextSizes.label, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${money.format(net)} ⃁',
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
              valueColor: AlwaysStoppedAnimation(
                  Theme.of(context).extension<AccentPalette>()!.progress),
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
                  fontSize: AppTextSizes.label,
                  color: scheme.onSurfaceVariant)),
          Text('${money.format(value)} ⃁',
              style: TextStyle(
                  fontSize: AppTextSizes.row,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}
