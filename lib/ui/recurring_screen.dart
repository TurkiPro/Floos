import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_settings.dart';
import '../data/database.dart';
import '../data/enums.dart';
import '../domain/recurrence_engine.dart';
import '../domain/recurrence_math.dart';
import '../services/alerts_coordinator.dart';
import 'add_recurrence_sheet.dart';
import 'theme/tokens.dart';

String frequencyLabelAr(Frequency f) {
  switch (f) {
    case Frequency.daily:
      return 'يومي';
    case Frequency.weekly:
      return 'أسبوعي';
    case Frequency.monthly:
      return 'شهري';
    case Frequency.yearly:
      return 'سنوي';
  }
}

/// Monthly obligations = recurring EXPENSE rules (rent, subscriptions, bills…).
/// Recurring income lives on the income page instead; this screen is reached
/// from Settings.
class ObligationsScreen extends StatelessWidget {
  const ObligationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final dateFmt = DateFormat('yyyy-MM-dd');
    final money = NumberFormat('#,##0.00');
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('الالتزامات الشهرية')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) =>
              AddRecurrenceSheet(db: db, lockedType: TxnType.expense),
        ),
        icon: const Icon(Icons.add),
        label: const Text('التزام جديد'),
      ),
      body: StreamBuilder<List<RecurrenceRule>>(
        stream: db.recurrenceDao.watchByType(TxnType.expense),
        builder: (context, snapshot) {
          final rules = snapshot.data ?? const <RecurrenceRule>[];
          if (rules.isEmpty) {
            return const Center(child: Text('لا توجد التزامات شهرية'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: rules.length,
            itemBuilder: (context, i) {
              final r = rules[i];
              final next = r.active
                  ? nextOccurrence(
                      startDate: r.startDate,
                      frequency: r.frequency,
                      interval: r.interval,
                      endDate: r.endDate,
                      afterExclusive: r.lastMaterialized ??
                          dateOnly(r.startDate)
                              .subtract(const Duration(days: 1)),
                    )
                  : null;

              final subtitle = StringBuffer()
                ..write(
                    '${money.format(r.amount)} ر.س  •  ${frequencyLabelAr(r.frequency)}');
              if (r.interval > 1) subtitle.write(' (كل ${r.interval})');
              if (r.active && next != null) {
                subtitle.write('\nالتالي: ${dateFmt.format(next)}');
              } else if (!r.active) {
                subtitle.write('\nمتوقفة');
              }

              return Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                  isThreeLine: true,
                  onTap: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => AddRecurrenceSheet(db: db, existingRule: r),
                  ),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadii.tile),
                    ),
                    child: Icon(Icons.north_east, color: scheme.primary),
                  ),
                  title: Text(
                    r.title,
                    style: const TextStyle(
                        fontSize: AppTextSizes.row,
                        fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(subtitle.toString()),
                  trailing: Switch(
                    value: r.active,
                    onChanged: (v) async {
                      if (v) {
                        await db.recurrenceDao.reactivate(r.id);
                        await RecurrenceEngine(db).catchUp();
                      } else {
                        await db.recurrenceDao.pause(r.id);
                      }
                      if (context.mounted) {
                        refreshAlerts(db, context.read<AppSettings>());
                      }
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
