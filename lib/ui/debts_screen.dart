import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_settings.dart';
import '../data/database.dart';
import '../data/enums.dart';
import '../domain/ledger_balance.dart';
import '../domain/parse_amount.dart';
import '../services/alerts_coordinator.dart';
import 'theme/tokens.dart';
import 'widgets/amount_input.dart';
import 'widgets/swipe_to_delete.dart';

/// What is still owed on a debt, within a halala of zero, counts as settled.
bool _settled(double outstanding) => outstanding.abs() < 0.005;

String _directionTitle(DebtDirection d) =>
    d == DebtDirection.lent ? 'لي عند الآخرين' : 'عليّ';

/// Money lent and borrowed, by person.
///
/// Neither is spending nor income: lending moves money out of the balance and
/// a repayment brings it back; borrowed money shows in the balance but never
/// counts as yours to spend (see `ledger_balance.dart`).
class DebtsScreen extends StatelessWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final money = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(title: const Text('الديون والسلف')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (_) => AddDebtSheet(db: db),
        ),
        icon: const Icon(Icons.add),
        label: const Text('دين جديد'),
      ),
      body: StreamBuilder<List<Debt>>(
        stream: db.debtDao.watchDebts(),
        builder: (context, debtSnap) {
          return StreamBuilder<List<DebtMovementRow>>(
            stream: db.debtDao.watchAllMovements(),
            builder: (context, moveSnap) {
              final debts = debtSnap.data ?? const <Debt>[];
              if (debtSnap.hasData && debts.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Text(
                      'لا توجد ديون. سجّل ما أقرضته لغيرك أو اقترضته، '
                      'وتابِع ما سُدّد منه.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              final outstanding =
                  debtOutstanding(moveSnap.data ?? const <DebtMovementRow>[]);
              double owed(Debt d) => outstanding[d.id] ?? 0;
              final open = debts.where((d) => !_settled(owed(d))).toList();
              final settled = debts.where((d) => _settled(owed(d))).toList();

              return ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 96),
                children: [
                  for (final direction in DebtDirection.values) ...[
                    _Section(
                      title: _directionTitle(direction),
                      total: open
                          .where((d) => d.direction == direction)
                          .fold<double>(0, (s, d) => s + owed(d)),
                      money: money,
                    ),
                    for (final d in open.where((d) => d.direction == direction))
                      _DebtTile(debt: d, outstanding: owed(d), money: money),
                    if (!open.any((d) => d.direction == direction))
                      const Padding(
                        padding: EdgeInsets.only(bottom: AppSpacing.md),
                        child: Text('لا شيء', textAlign: TextAlign.center),
                      ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (settled.isNotEmpty)
                    ExpansionTile(
                      title: Text('مسدّدة (${settled.length})'),
                      children: [
                        for (final d in settled)
                          _DebtTile(debt: d, outstanding: 0, money: money),
                      ],
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final double total;
  final NumberFormat money;
  const _Section(
      {required this.title, required this.total, required this.money});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: scheme.primary)),
          Text('${money.format(total)} ⃁',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _DebtTile extends StatelessWidget {
  final Debt debt;
  final double outstanding;
  final NumberFormat money;
  const _DebtTile(
      {required this.debt, required this.outstanding, required this.money});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: Icon(debt.direction == DebtDirection.lent
            ? Icons.call_made
            : Icons.call_received),
        title: Text(debt.person),
        subtitle: debt.note == null ? null : Text(debt.note!),
        trailing: Text(
          _settled(outstanding) ? 'مسدّد' : '${money.format(outstanding)} ⃁',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DebtDetailScreen(debtId: debt.id),
        )),
      ),
    );
  }
}

/// One person's debt: what is still owed, and every movement on it.
class DebtDetailScreen extends StatelessWidget {
  final int debtId;
  const DebtDetailScreen({super.key, required this.debtId});

  Future<void> _addMovement(
      BuildContext context, AppDatabase db, Debt debt, bool repayment) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) =>
          DebtMovementSheet(db: db, debt: debt, repayment: repayment),
    );
  }

  Future<void> _delete(BuildContext context, AppDatabase db, Debt debt) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الدين'),
        content: Text('سيُحذف دين «${debt.person}» وكل ما سُجّل عليه.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final settings = context.read<AppSettings>();
    Navigator.of(context).pop();
    await db.debtDao.deleteDebt(debt.id);
    // The balance and weekly budget move with it.
    await refreshAlerts(db, settings);
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final money = NumberFormat('#,##0.00');
    final dateFmt = DateFormat('yyyy-MM-dd');

    return StreamBuilder<Debt?>(
      stream: db.debtDao.watchDebt(debtId),
      builder: (context, debtSnap) {
        final debt = debtSnap.data;
        if (debt == null) {
          return const Scaffold(body: SizedBox.shrink());
        }
        final lent = debt.direction == DebtDirection.lent;
        return Scaffold(
          appBar: AppBar(
            title: Text(debt.person),
            actions: [
              IconButton(
                tooltip: 'حذف الدين',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(context, db, debt),
              ),
            ],
          ),
          body: StreamBuilder<List<DebtMovement>>(
            stream: db.debtDao.watchMovements(debtId),
            builder: (context, snap) {
              final moves = snap.data ?? const <DebtMovement>[];
              final outstanding = moves.fold<double>(0, (s, m) => s + m.amount);
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Text(
                    _settled(outstanding)
                        ? 'مسدّد بالكامل'
                        : lent
                            ? 'متبقٍ لك: ${money.format(outstanding)} ⃁'
                            : 'متبقٍ عليك: ${money.format(outstanding)} ⃁',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: AppTextSizes.row,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () =>
                              _addMovement(context, db, debt, true),
                          icon: const Icon(Icons.check),
                          label: const Text('تسجيل سداد'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _addMovement(context, db, debt, false),
                          icon: const Icon(Icons.add),
                          label: const Text('إضافة مبلغ'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  for (final m in moves)
                    _MovementTile(
                      key: ValueKey(m.id),
                      db: db,
                      movement: m,
                      lent: lent,
                      money: money,
                      dateFmt: dateFmt,
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _MovementTile extends StatelessWidget {
  final AppDatabase db;
  final DebtMovement movement;
  final bool lent;
  final NumberFormat money;
  final DateFormat dateFmt;
  const _MovementTile({
    super.key,
    required this.db,
    required this.movement,
    required this.lent,
    required this.money,
    required this.dateFmt,
  });

  @override
  Widget build(BuildContext context) {
    final repayment = movement.amount < 0;
    final label =
        repayment ? (lent ? 'سدّد لك' : 'سدّدت') : (lent ? 'أقرضت' : 'اقترضت');
    final details = [
      dateFmt.format(movement.date),
      if (movement.external) 'خارج الرصيد',
      if ((movement.note ?? '').isNotEmpty) movement.note!,
    ].join('  •  ');

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: SwipeToDelete(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onDelete: () {
          final settings = context.read<AppSettings>();
          final messenger = ScaffoldMessenger.of(context);
          final deleted = movement;
          db.debtDao
              .deleteMovement(deleted.id)
              .then((_) => refreshAlerts(db, settings));
          messenger.showSnackBar(SnackBar(
            content: const Text('تم الحذف'),
            action: SnackBarAction(
              label: 'تراجع',
              onPressed: () => db.debtDao
                  .restoreMovement(deleted)
                  .then((_) => refreshAlerts(db, settings)),
            ),
          ));
        },
        child: Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            title: Text(label),
            subtitle: Text(details),
            trailing: Text(
              '${money.format(movement.amount.abs())} ⃁',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: repayment ? AppColors.income : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A new debt: who, which way, how much, and whether the money went through
/// the tracked balance.
class AddDebtSheet extends StatefulWidget {
  final AppDatabase db;
  const AddDebtSheet({super.key, required this.db});

  @override
  State<AddDebtSheet> createState() => _AddDebtSheetState();
}

class _AddDebtSheetState extends State<AddDebtSheet> {
  DebtDirection _direction = DebtDirection.lent;
  final _person = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  bool _external = false;

  @override
  void dispose() {
    _person.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseAmount(_amount.text);
    final person = _person.text.trim();
    if (amount == null || amount <= 0 || person.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل الاسم ومبلغًا صحيحًا')),
      );
      return;
    }
    await widget.db.debtDao.addDebt(
      person: person,
      direction: _direction,
      amount: amount,
      date: _date,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      external: _external,
    );
    if (!mounted) return;
    refreshAlerts(widget.db, context.read<AppSettings>());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final lent = _direction == DebtDirection.lent;
    return _SheetFrame(
      onSave: _save,
      children: [
        SegmentedButton<DebtDirection>(
          segments: const [
            ButtonSegment(value: DebtDirection.lent, label: Text('أقرضت')),
            ButtonSegment(value: DebtDirection.borrowed, label: Text('اقترضت')),
          ],
          selected: {_direction},
          onSelectionChanged: (s) => setState(() => _direction = s.first),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _person,
          decoration: InputDecoration(
            labelText: lent ? 'لمن؟' : 'من مَن؟',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _AmountField(controller: _amount),
        const SizedBox(height: AppSpacing.md),
        _DateAndNote(
          date: _date,
          onDate: (d) => setState(() => _date = d),
          note: _note,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _external,
          onChanged: (v) => setState(() => _external = v),
          title: Text(lent
              ? 'لم يخرج من رصيدي (قبل استخدام التطبيق أو نقدًا)'
              : 'لم يدخل رصيدي (قبل استخدام التطبيق أو نقدًا)'),
        ),
        Text(
          lent
              ? 'لا يُحسب مصروفًا. يخرج من رصيدك ويعود إليه عند السداد.'
              : 'لا يُحسب دخلًا. يظهر في رصيدك، لكن لا يُحسب مما يمكنك صرفه.',
          style: TextStyle(
            fontSize: AppTextSizes.label,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// A repayment, or more money lent/borrowed, on an existing debt.
class DebtMovementSheet extends StatefulWidget {
  final AppDatabase db;
  final Debt debt;

  /// True records a repayment (stored negative); false adds to what is owed.
  final bool repayment;
  const DebtMovementSheet({
    super.key,
    required this.db,
    required this.debt,
    required this.repayment,
  });

  @override
  State<DebtMovementSheet> createState() => _DebtMovementSheetState();
}

class _DebtMovementSheetState extends State<DebtMovementSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  bool _external = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseAmount(_amount.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل مبلغًا صحيحًا')),
      );
      return;
    }
    await widget.db.debtDao.addMovement(
      debtId: widget.debt.id,
      amount: widget.repayment ? -amount : amount,
      date: _date,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      external: _external,
    );
    if (!mounted) return;
    refreshAlerts(widget.db, context.read<AppSettings>());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final lent = widget.debt.direction == DebtDirection.lent;
    final title = widget.repayment
        ? (lent
            ? 'سدّد لك ${widget.debt.person}'
            : 'سدّدت لـ${widget.debt.person}')
        : (lent
            ? 'أقرضت ${widget.debt.person} مبلغًا آخر'
            : 'اقترضت مبلغًا آخر');
    // Whether this movement brought money in or took it out of the balance.
    final moneyIn = widget.repayment == lent;
    return _SheetFrame(
      onSave: _save,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        _AmountField(controller: _amount),
        const SizedBox(height: AppSpacing.md),
        _DateAndNote(
          date: _date,
          onDate: (d) => setState(() => _date = d),
          note: _note,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _external,
          onChanged: (v) => setState(() => _external = v),
          title: Text(
              moneyIn ? 'لم يدخل رصيدي (نقدًا)' : 'لم يخرج من رصيدي (نقدًا)'),
        ),
      ],
    );
  }
}

class _SheetFrame extends StatelessWidget {
  final List<Widget> children;
  final VoidCallback onSave;
  const _SheetFrame({required this.children, required this.onSave});

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...children,
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: onSave, child: const Text('حفظ')),
          ],
        ),
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  final TextEditingController controller;
  const _AmountField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: const [ThousandsInputFormatter()],
      decoration: const InputDecoration(
        labelText: 'المبلغ',
        suffixText: '⃁',
        border: OutlineInputBorder(),
      ),
    );
  }
}

class _DateAndNote extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onDate;
  final TextEditingController note;
  const _DateAndNote(
      {required this.date, required this.onDate, required this.note});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime(2015),
              lastDate: DateTime(2100),
            );
            if (picked != null) onDate(picked);
          },
          icon: const Icon(Icons.calendar_today_outlined, size: 16),
          label: Text(DateFormat('yyyy-MM-dd').format(date)),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: TextField(
            controller: note,
            decoration: const InputDecoration(
              labelText: 'ملاحظة',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }
}
