import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../data/enums.dart';
import '../domain/recurrence_engine.dart';
import '../domain/recurrence_math.dart';
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

class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final dateFmt = DateFormat('yyyy-MM-dd');
    final money = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(title: const Text('الحركات المتكررة')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => AddRecurrenceSheet(db: db),
        ),
        icon: const Icon(Icons.add),
        label: const Text('قاعدة جديدة'),
      ),
      body: StreamBuilder<List<RecurrenceRule>>(
        stream: db.recurrenceDao.watchAll(),
        builder: (context, snapshot) {
          final rules = snapshot.data ?? const <RecurrenceRule>[];
          if (rules.isEmpty) {
            return const Center(child: Text('لا توجد قواعد متكررة'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: rules.length,
            itemBuilder: (context, i) {
              final r = rules[i];
              final isIncome = r.type == TxnType.income;
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
                    builder: (_) => AddRecurrenceSheet(db: db, existingRule: r),
                  ),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: (isIncome
                              ? AppColors.income
                              : Theme.of(context).colorScheme.primary)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadii.tile),
                    ),
                    child: Icon(
                      isIncome ? Icons.south_west : Icons.north_east,
                      color: isIncome
                          ? AppColors.income
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  title: Text(
                    r.title,
                    style: const TextStyle(
                        fontSize: AppTextSizes.row, fontWeight: FontWeight.w500),
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
