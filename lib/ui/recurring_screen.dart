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
          showDragHandle: true,
          builder: (_) =>
              AddRecurrenceSheet(db: db, lockedType: TxnType.expense),
        ),
        icon: const Icon(Icons.add),
        label: const Text('التزام جديد'),
      ),
      body: StreamBuilder<List<RecurrenceRule>>(
        stream: db.recurrenceDao.watchByType(TxnType.expense),
        builder: (context, snapshot) {
          final rules = [...(snapshot.data ?? const <RecurrenceRule>[])];
          if (rules.isEmpty) {
            return const Center(child: Text('لا توجد التزامات شهرية'));
          }
          // Next occurrence per rule (override-aware), for sorting and display.
          final nextById = <int, DateTime?>{
            for (final r in rules)
              r.id: !r.active
                  ? null
                  : (r.nextOverrideDate ??
                      nextOccurrence(
                        startDate: r.startDate,
                        frequency: r.frequency,
                        interval: r.interval,
                        endDate: r.endDate,
                        afterExclusive: r.lastMaterialized ??
                            dateOnly(r.startDate)
                                .subtract(const Duration(days: 1)),
                      )),
          };
          // Sort by soonest due date (active first); paused ones sink to the
          // bottom, alphabetically — not the old title-only order.
          rules.sort((a, b) {
            if (a.active != b.active) return a.active ? -1 : 1;
            final da = nextById[a.id];
            final dbb = nextById[b.id];
            if (da == null && dbb == null) return a.title.compareTo(b.title);
            if (da == null) return 1;
            if (dbb == null) return -1;
            return da.compareTo(dbb);
          });
          final total = rules
              .where((r) => r.active)
              .fold<double>(0, (s, r) => s + r.amount);

          return ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 96),
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadii.card),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('إجمالي الالتزامات النشطة',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    Text('${money.format(total)} ر.س',
                        style: TextStyle(
                            fontSize: AppTextSizes.row,
                            fontWeight: FontWeight.w700,
                            color: scheme.primary)),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final r in rules)
                _obligationTile(
                    context, db, r, nextById[r.id], money, dateFmt, scheme),
            ],
          );
        },
      ),
    );
  }

  /// One compact obligation row: name, amount, next due date, an active switch,
  /// tap to edit, swipe to delete.
  Widget _obligationTile(
    BuildContext context,
    AppDatabase db,
    RecurrenceRule r,
    DateTime? next,
    NumberFormat money,
    DateFormat dateFmt,
    ColorScheme scheme,
  ) {
    final subtitle = StringBuffer('${money.format(r.amount)} ر.س');
    if (r.active && next != null) {
      subtitle.write('  •  التالي ${dateFmt.format(next)}');
    } else if (!r.active) {
      subtitle.write('  •  متوقفة');
    }
    return Dismissible(
      key: ValueKey(r.id),
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
      confirmDismiss: (_) => _confirmDelete(context, r.title),
      onDismissed: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        final settings = context.read<AppSettings>();
        await db.recurrenceDao.deleteById(r.id);
        await refreshAlerts(db, settings);
        messenger.showSnackBar(
          const SnackBar(content: Text('تم حذف الالتزام')),
        );
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            builder: (_) => AddRecurrenceSheet(db: db, existingRule: r),
          ),
          leading: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.tile),
            ),
            child: Icon(Icons.north_east, size: 18, color: scheme.primary),
          ),
          title: Text(r.title,
              style: const TextStyle(
                  fontSize: AppTextSizes.label, fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle.toString(),
              style: const TextStyle(fontSize: AppTextSizes.label)),
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
      ),
    );
  }

  /// A soft, in-context confirmation for a destructive swipe — a rounded sheet
  /// that slides up from the bottom rather than a modal dialog thrown in the
  /// user's face. Returns true only if they tap حذف.
  Future<bool> _confirmDelete(BuildContext context, String name) async {
    final scheme = Theme.of(context).colorScheme;
    final result = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.delete_outline, size: 40, color: Colors.red),
            const SizedBox(height: AppSpacing.md),
            Text(
              'حذف «$name»؟',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: AppTextSizes.row, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'لن يتم توليد عمليات جديدة من هذا الالتزام. العمليات السابقة تبقى كما هي.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: AppTextSizes.label, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('حذف'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }
}
