import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_settings.dart';
import '../../domain/calendar_format.dart';
import '../theme/tokens.dart';

/// One day's entries on their own surface, so consecutive days read as
/// separate blocks. Header shows the weekday + date (in the user's chosen
/// calendar) and that day's total.
///
/// The shared shell behind every dated list in the app — transactions on the
/// home/month/income screens and deposits on the savings screen — so they all
/// look identical.
class DaySection extends StatelessWidget {
  final DateTime day;
  final DateTime today;
  final String totalText;
  final Color totalColor;
  final List<Widget> children;

  const DaySection({
    super.key,
    required this.day,
    required this.today,
    required this.totalText,
    required this.totalColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hijri = context.watch<AppSettings>().useHijri;

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
                  dayFullLabelFor(day, today: today, hijri: hijri),
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
          ...children,
        ],
      ),
    );
  }
}
