import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/enums.dart';
import '../theme/tokens.dart';
import 'category_picker.dart';

/// What a bank party means: the user's answer from [PartyDecisionSheet].
class PartyDecision {
  final PartyDisposition? disposition;
  final int? categoryId;
  final int? goalId;
  final String? displayName;

  /// Set when the user chose to forget the party altogether (only offered
  /// when the sheet is opened with [PartyDecisionSheet.onDeleteLabel]).
  final bool delete;
  const PartyDecision({
    this.disposition,
    this.categoryId,
    this.goalId,
    this.displayName,
    this.delete = false,
  });
}

/// Asks what a party means, once. The display-name field is here because the
/// bank's own strings are often unreadable — "KR-133" is a POS terminal code,
/// "**7772" an account number — and naming one should fix it forever.
class PartyDecisionSheet extends StatefulWidget {
  final AppDatabase db;
  final String? party;
  final PartyDecision initial;

  /// Shown under the decision, e.g. what an edit does and does not change.
  final String? footnote;

  /// When set, the sheet offers a destructive button with this label, which
  /// pops a [PartyDecision] with `delete: true`.
  final String? onDeleteLabel;
  const PartyDecisionSheet({
    super.key,
    required this.db,
    required this.party,
    required this.initial,
    this.footnote,
    this.onDeleteLabel,
  });

  @override
  State<PartyDecisionSheet> createState() => _PartyDecisionSheetState();
}

class _PartyDecisionSheetState extends State<PartyDecisionSheet> {
  late PartyDisposition? _disposition = widget.initial.disposition;
  late int? _categoryId = widget.initial.categoryId;
  late int? _goalId = widget.initial.goalId;
  late final _nameCtrl =
      TextEditingController(text: widget.initial.displayName ?? '');

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _isValid => switch (_disposition) {
        null => false,
        PartyDisposition.expense ||
        PartyDisposition.income =>
          _categoryId != null,
        PartyDisposition.savings => _goalId != null,
        PartyDisposition.ignore => true,
      };

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.party != null)
                    Text(
                      widget.party!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: AppTextSizes.row,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: AppSpacing.sm,
                    children: [
                      for (final d in PartyDisposition.values)
                        ChoiceChip(
                          label: Text(_label(d)),
                          selected: _disposition == d,
                          onSelected: (_) => setState(() {
                            _disposition = d;
                            // Clear the field that no longer applies, so an
                            // invalid pairing can never be submitted.
                            if (d != PartyDisposition.savings) _goalId = null;
                            if (d == PartyDisposition.savings ||
                                d == PartyDisposition.ignore) {
                              _categoryId = null;
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_disposition == PartyDisposition.expense ||
                      _disposition == PartyDisposition.income)
                    CategoryPicker(
                      db: widget.db,
                      type: _disposition == PartyDisposition.income
                          ? TxnType.income
                          : TxnType.expense,
                      selectedId: _categoryId,
                      onChanged: (id) => setState(() => _categoryId = id),
                    ),
                  if (_disposition == PartyDisposition.savings)
                    GoalPicker(
                      db: widget.db,
                      selectedId: _goalId,
                      onChanged: (id) => setState(() => _goalId = id),
                    ),
                  if (_disposition == PartyDisposition.ignore)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: Text(
                        'لن تُسجَّل هذه العمليات — شحن البطاقة أو التحويل بين '
                        'حساباتك ليس مصروفًا، وتسجيله يحتسب المبلغ مرتين.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم مختصر (اختياري)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  if (widget.footnote != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      widget.footnote!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AppTextSizes.label,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
            child: FilledButton(
              onPressed: _isValid
                  ? () => Navigator.of(context).pop(PartyDecision(
                        disposition: _disposition,
                        categoryId: _categoryId,
                        goalId: _goalId,
                        displayName: _nameCtrl.text.trim().isEmpty
                            ? null
                            : _nameCtrl.text.trim(),
                      ))
                  : null,
              child: const Text('تأكيد'),
            ),
          ),
          if (widget.onDeleteLabel != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
              child: TextButton(
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error),
                onPressed: () => Navigator.of(context)
                    .pop(const PartyDecision(delete: true)),
                child: Text(widget.onDeleteLabel!),
              ),
            ),
        ],
      ),
    );
  }

  String _label(PartyDisposition d) => switch (d) {
        PartyDisposition.expense => 'مصروف',
        PartyDisposition.income => 'دخل',
        PartyDisposition.savings => 'ادخار',
        PartyDisposition.ignore => 'تجاهل',
      };
}

class GoalPicker extends StatelessWidget {
  final AppDatabase db;
  final int? selectedId;
  final ValueChanged<int> onChanged;
  const GoalPicker({
    super.key,
    required this.db,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SavingsGoal>>(
      stream: db.savingsDao.watchGoals(),
      builder: (context, snap) {
        final goals = snap.data ?? const <SavingsGoal>[];
        if (goals.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text('لا توجد أهداف ادخار بعد', textAlign: TextAlign.center),
          );
        }
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.sm,
          children: [
            for (final g in goals)
              ChoiceChip(
                label: Text(g.name),
                selected: selectedId == g.id,
                onSelected: (_) => onChanged(g.id),
              ),
          ],
        );
      },
    );
  }
}
