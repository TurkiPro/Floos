import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_settings.dart';
import '../data/database.dart';
import '../data/enums.dart';
import '../domain/bank_sms.dart';
import '../domain/calendar_format.dart';
import '../domain/financial_period.dart';
import '../domain/import_review.dart';
import '../domain/party_key.dart';
import '../services/alerts_coordinator.dart';
import 'theme/tokens.dart';
import 'widgets/amount_input.dart';
import 'widgets/party_decision_sheet.dart';

/// Step two of the bank-message import: look at what was parsed, decide what
/// each unknown party means, and confirm.
///
/// Nothing reaches the database until the user taps save. Rows that look like
/// duplicates are shown dimmed and unchecked rather than hidden — a silently
/// dropped row is the failure mode that would make the feature untrustworthy.
class ImportReviewScreen extends StatefulWidget {
  final AppDatabase db;
  final List<BankMessage> drafts;
  const ImportReviewScreen({
    super.key,
    required this.db,
    required this.drafts,
  });

  @override
  State<ImportReviewScreen> createState() => _ImportReviewScreenState();
}

/// The user's decision about one row, held in memory until save.
class _RowState {
  final ReviewedDraft reviewed;
  bool checked;
  PartyDisposition? disposition;
  int? categoryId;
  int? goalId;
  String? displayName;

  /// True when the party already had a rule before this import, so the batch
  /// does not take ownership of it.
  final bool ruleAlreadyExisted;

  /// Money that came back. It is written as a negative expense — never as a
  /// purchase, which is what the party's rule alone would have made of it.
  final bool refund;

  /// The purchase this refund refunds, when one was found.
  final Txn? refundTarget;

  _RowState(this.reviewed, {this.refundTarget})
      : refund = reviewed.message.kind == BankTxnKind.refund,
        checked = reviewed.suggestedForImport &&
            // A refund only arrives ready when the party's rule already says
            // which expense category it goes back to (or to ignore it).
            (reviewed.message.kind != BankTxnKind.refund ||
                _refundReady(reviewed.rule)),
        disposition = reviewed.message.kind == BankTxnKind.refund
            ? (_refundReady(reviewed.rule) ? reviewed.rule!.disposition : null)
            : reviewed.rule?.disposition,
        // Only an expense category can take a refund back.
        categoryId = reviewed.message.kind == BankTxnKind.refund &&
                reviewed.rule?.disposition != PartyDisposition.expense
            ? null
            : reviewed.rule?.categoryId,
        goalId = reviewed.message.kind == BankTxnKind.refund
            ? null
            : reviewed.rule?.goalId,
        displayName = reviewed.rule?.displayName,
        ruleAlreadyExisted = reviewed.rule != null;

  /// A rule that can carry a refund: an expense category, or ignore. A rule
  /// that files the party as income or savings says nothing about where its
  /// refunds go, so the user is asked.
  static bool _refundReady(PartyRule? rule) =>
      rule != null &&
      (rule.disposition == PartyDisposition.expense ||
          rule.disposition == PartyDisposition.ignore);

  /// What this row does to spending: a refund takes its amount back off.
  double get signedAmount => refund ? -message.amount! : message.amount!;

  BankMessage get message => reviewed.message;

  /// A row can only be saved once it has both a usable parse and a decision.
  bool get isResolved {
    if (!message.isUsable) return false;
    return switch (disposition) {
      null => false,
      PartyDisposition.expense || PartyDisposition.income => categoryId != null,
      PartyDisposition.savings => goalId != null,
      PartyDisposition.ignore => true,
    };
  }
}

class _ImportReviewScreenState extends State<ImportReviewScreen> {
  List<_RowState>? _rows;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  /// Gathers everything the review needs from the database once, then hands it
  /// to the pure [reviewDrafts].
  Future<void> _prepare() async {
    final db = widget.db;
    final txns = await db.select(db.transactions).get();
    final rules = await db.partyRuleDao.getAll();

    final fingerprints = ledgerFingerprints(txns);

    // Charges the recurrence engine owns: ones it has already materialized,
    // plus the next occurrence of each active income/expense rule. Importing
    // one of these would book it a second time.
    final charges = <RecurringCharge>[
      for (final t in txns)
        if (t.recurrenceId != null)
          RecurringCharge(amount: t.amount, date: t.date),
    ];
    final activeRules = await db.recurrenceDao.activeRules();
    final now = DateTime.now();
    for (final rule in activeRules) {
      final next = rule.lastPaidDate ?? rule.lastMaterialized;
      if (next != null) {
        charges.add(RecurringCharge(amount: rule.amount, date: next));
      }
      charges.add(RecurringCharge(amount: rule.amount, date: now));
    }

    // The same exact-then-prefix order PartyRuleDao.lookup uses, done in
    // memory because reviewDrafts is synchronous.
    final byParty = {for (final r in rules) r.partyKey: r};
    final reviewed = reviewDrafts(
      drafts: widget.drafts,
      ledgerFingerprints: fingerprints,
      recurringCharges: charges,
      lookupRule: (party) {
        final key = partyKey(party);
        final direct = byParty[key];
        if (direct != null) return direct;
        for (final rule in rules) {
          if (partyMatches(rule.partyKey, key)) return rule;
        }
        return null;
      },
    );

    // Each refund message, matched to the purchase it most likely refunds.
    final ruleByParty = {
      for (final d in reviewed)
        if (d.message.party != null) d.message.party!: d.rule,
    };
    _RowState toRow(ReviewedDraft d) {
      final m = d.message;
      if (m.kind != BankTxnKind.refund || m.amount == null || m.at == null) {
        return _RowState(d);
      }
      final name = ruleByParty[m.party]?.displayName?.trim();
      return _RowState(d,
          refundTarget: findRefundTarget(
            txns,
            amount: m.amount!,
            date: m.at!,
            label: name != null && name.isNotEmpty ? name : m.party,
          ));
    }

    if (!mounted) return;
    setState(() => _rows = reviewed.map(toRow).toList());
  }

  List<_RowState> get _selected =>
      (_rows ?? []).where((r) => r.checked && r.isResolved).toList();

  double get _selectedTotal => _selected
      .where((r) => r.disposition != PartyDisposition.ignore)
      .fold(0.0, (acc, r) => acc + r.signedAmount);

  Future<void> _save() async {
    final rows = _selected;
    if (rows.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.db.importBatchDao.commitImport([
        for (final r in rows)
          ResolvedImportRow(
            amount: r.message.amount!,
            date: r.message.at!,
            party: r.message.party,
            displayName: r.displayName,
            disposition: r.disposition!,
            categoryId: r.categoryId,
            goalId: r.goalId,
            ruleAlreadyExisted: r.ruleAlreadyExisted,
            refund: r.refund,
            refundOf: r.refundTarget?.id,
          ),
      ]);
      if (!mounted) return;
      // One refresh for the whole batch, not one per row.
      refreshAlerts(widget.db, context.read<AppSettings>());
      Navigator.of(context).pop(rows.length);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر الحفظ: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(title: const Text('مراجعة العمليات')),
      body: rows == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(child: _buildList(rows)),
                _buildFooter(rows),
              ],
            ),
    );
  }

  /// Grouped by salary cycle — the app's only period unit. A single paste
  /// routinely straddles a payday, so the group header is the cycle label (a
  /// date range when the cycle doesn't line up with a calendar month).
  Widget _buildList(List<_RowState> rows) {
    if (rows.isEmpty) {
      return const Center(child: Text('لم يتم العثور على عمليات'));
    }
    final hijri = context.watch<AppSettings>().useHijri;

    return FutureBuilder<List<RecurrenceRule>>(
      future: widget.db.recurrenceDao.activeRules(),
      builder: (context, snap) {
        final incomeRules = (snap.data ?? const <RecurrenceRule>[])
            .where((r) => r.type == TxnType.income)
            .toList();

        // Bucket each row into the cycle that contains its date.
        final groups = <DateTime, List<_RowState>>{};
        final labels = <DateTime, String>{};
        for (final row in rows) {
          final at = row.message.at;
          if (at == null) {
            groups.putIfAbsent(DateTime(0), () => []).add(row);
            labels[DateTime(0)] = 'بدون تاريخ';
            continue;
          }
          final cycle = financialPeriod(incomeRules, at);
          groups.putIfAbsent(cycle.start, () => []).add(row);
          labels[cycle.start] = cycleLabelFor(cycle, hijri: hijri);
        }
        final keys = groups.keys.toList()..sort();

        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: keys.length,
          itemBuilder: (context, i) {
            final key = keys[i];
            final group = groups[key]!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                      top: AppSpacing.sm, bottom: AppSpacing.sm),
                  child: Text(
                    labels[key]!,
                    style: TextStyle(
                      fontSize: AppTextSizes.label,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                for (final row in group) _buildRow(row),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildRow(_RowState row) {
    final message = row.message;
    final blocked = row.reviewed.status != DraftStatus.fresh;
    final scheme = Theme.of(context).colorScheme;

    final title = row.displayName?.trim().isNotEmpty == true
        ? row.displayName!.trim()
        : (message.party ?? 'بدون جهة');

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Opacity(
        opacity: blocked && !row.checked ? 0.55 : 1,
        child: Column(
          children: [
            CheckboxListTile(
              value: row.checked,
              // An unresolved or unusable row can be ticked only after it has
              // been given a meaning.
              onChanged: (v) {
                if (v == true && !row.isResolved) {
                  _resolve(row);
                  return;
                }
                setState(() => row.checked = v ?? false);
              },
              title: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_subtitleFor(message)),
                  if (row.refund)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        row.refundTarget == null
                            ? 'استرداد'
                            : 'استرداد لشراء '
                                '${DateFormat('yyyy-MM-dd').format(row.refundTarget!.date)}',
                        style: const TextStyle(
                          fontSize: AppTextSizes.label,
                          color: AppColors.income,
                        ),
                      ),
                    ),
                  if (blocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        _reasonFor(row.reviewed.status),
                        style: TextStyle(
                          fontSize: AppTextSizes.label,
                          color: scheme.error,
                        ),
                      ),
                    ),
                  if (!message.isUsable)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'تعذّر قراءة الرسالة بالكامل',
                        style: TextStyle(
                          fontSize: AppTextSizes.label,
                          color: scheme.error,
                        ),
                      ),
                    ),
                ],
              ),
              secondary: Text(
                message.amount == null
                    ? '—'
                    : '${row.refund ? '+' : ''}'
                        '${groupedAmount(message.amount!)} ⃁',
                style: TextStyle(
                  fontSize: AppTextSizes.row,
                  fontWeight: FontWeight.w700,
                  color: row.refund ? AppColors.income : null,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _resolve(row),
                      child: Text(
                        _dispositionLabel(row),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // A message that failed to parse keeps its original text visible,
            // so nothing is lost even when the app could not read it.
            if (!message.isUsable)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    message.raw,
                    style: TextStyle(
                      fontSize: AppTextSizes.label,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _subtitleFor(BankMessage m) {
    final at = m.at;
    if (at == null) return 'بدون تاريخ';
    return DateFormat('yyyy-MM-dd  HH:mm').format(at);
  }

  String _reasonFor(DraftStatus status) => switch (status) {
        DraftStatus.duplicateOfLedger => 'مسجّلة من قبل',
        DraftStatus.duplicateInPaste => 'مكرّرة في هذه اللصقة',
        DraftStatus.recurrenceCollision => 'مسجّلة تلقائيًا كالتزام متكرر',
        DraftStatus.fresh => '',
      };

  String _dispositionLabel(_RowState row) => switch (row.disposition) {
        null => 'اختر التصنيف',
        PartyDisposition.expense when row.refund => 'استرداد',
        PartyDisposition.expense => 'مصروف',
        PartyDisposition.income => 'دخل',
        PartyDisposition.savings => 'ادخار',
        PartyDisposition.ignore => 'تجاهل (تحويل بين حساباتي)',
      };

  /// Asks what this party means. The answer is remembered on save, so each
  /// merchant costs one tap once and none thereafter.
  Future<void> _resolve(_RowState row) async {
    final result = await showModalBottomSheet<PartyDecision>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PartyDecisionSheet(
        db: widget.db,
        party: row.message.party,
        initial: PartyDecision(
          disposition: row.disposition,
          categoryId: row.categoryId,
          goalId: row.goalId,
          displayName: row.displayName,
        ),
        allowed: row.refund
            ? const [PartyDisposition.expense, PartyDisposition.ignore]
            : PartyDisposition.values,
        labels: row.refund
            ? const {PartyDisposition.expense: 'استرداد إلى فئة'}
            : const {},
        footnote: row.refund
            ? 'مبلغ عاد إليك: يُخصم من مصروف الفئة، ولا يُحسب دخلًا.'
            : null,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      row.disposition = result.disposition;
      row.categoryId = result.categoryId;
      row.goalId = result.goalId;
      row.displayName = result.displayName;
      if (row.isResolved && row.reviewed.status == DraftStatus.fresh) {
        row.checked = true;
      }
    });
  }

  Widget _buildFooter(List<_RowState> rows) {
    final count = _selected.length;
    final total = _selectedTotal;
    final ignored =
        _selected.where((r) => r.disposition == PartyDisposition.ignore).length;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ignored == 0
                  ? 'المحدد: $count — ${groupedAmount(total)} ⃁'
                  : 'المحدد: $count — ${groupedAmount(total)} ⃁ '
                      '(و $ignored متجاهلة)',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              onPressed: count == 0 || _saving ? null : _save,
              child: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ $count عملية'),
            ),
          ],
        ),
      ),
    );
  }
}
