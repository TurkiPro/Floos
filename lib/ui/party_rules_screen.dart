import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/enums.dart';
import 'theme/tokens.dart';
import 'widgets/party_decision_sheet.dart';

/// Every party the bank-message import has learned, with what it means.
///
/// Until this screen existed a rule was only visible on an import row that
/// happened to match it, so a wrong decision learned once was re-applied to
/// every later import with no way to see it, fix it, or forget it.
class PartyRulesScreen extends StatefulWidget {
  final AppDatabase db;
  const PartyRulesScreen({super.key, required this.db});

  @override
  State<PartyRulesScreen> createState() => _PartyRulesScreenState();
}

class _PartyRulesScreenState extends State<PartyRulesScreen> {
  /// Past this many rules a filter field earns its space.
  static const _searchThreshold = 10;

  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  AppDatabase get db => widget.db;

  Future<void> _edit(PartyRule rule) async {
    final result = await showModalBottomSheet<PartyDecision>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PartyDecisionSheet(
        db: db,
        party: rule.rawParty,
        initial: PartyDecision(
          disposition: rule.disposition,
          categoryId: rule.categoryId,
          goalId: rule.goalId,
          displayName: rule.displayName,
        ),
        footnote: 'التعديل يُطبَّق على الاستيرادات القادمة فقط، '
            'ولا يغيّر العمليات المسجّلة سابقًا.',
        onDeleteLabel: 'نسيان هذه الجهة',
      ),
    );
    if (result == null || !mounted) return;

    if (result.delete) {
      await _confirmDelete(rule);
      return;
    }
    await db.partyRuleDao.updateRule(
      rule.id,
      disposition: result.disposition!,
      categoryId: result.categoryId,
      goalId: result.goalId,
      displayName: result.displayName,
    );
  }

  Future<void> _confirmDelete(PartyRule rule) async {
    final name = rule.displayName ?? rule.rawParty;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('نسيان الجهة'),
        content: Text(
          'سينسى التطبيق ما تعنيه «$name»، وسيسألك عنها من جديد في '
          'الاستيراد القادم. العمليات المسجّلة لا تتأثر.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('نسيان'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await db.partyRuleDao.deleteById(rule.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('نُسيت «$name»')),
    );
  }

  bool _matches(PartyRule r, String q) {
    if (q.isEmpty) return true;
    final needle = q.toLowerCase();
    return r.rawParty.toLowerCase().contains(needle) ||
        (r.displayName?.toLowerCase().contains(needle) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الجهات المحفوظة')),
      body: StreamBuilder<List<PartyRule>>(
        stream: db.partyRuleDao.watchAll(),
        builder: (context, rulesSnap) {
          final rules = rulesSnap.data ?? const <PartyRule>[];
          if (rulesSnap.hasData && rules.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'لم تُحفظ أي جهة بعد. تُحفظ الجهات عند الاستيراد.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return StreamBuilder<List<Category>>(
            stream: db.categoryDao.watchAll(),
            builder: (context, catSnap) {
              final categories = {
                for (final c in catSnap.data ?? const <Category>[]) c.id: c
              };
              return StreamBuilder<List<SavingsGoal>>(
                stream: db.savingsDao.watchGoals(),
                builder: (context, goalSnap) {
                  final goals = {
                    for (final g in goalSnap.data ?? const <SavingsGoal>[])
                      g.id: g
                  };
                  final q = _search.text.trim();
                  final shown = rules.where((r) => _matches(r, q)).toList();
                  return ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      if (rules.length > _searchThreshold) ...[
                        TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: 'بحث',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      for (final r in shown)
                        _RuleTile(
                          rule: r,
                          destination: _destination(r, categories, goals),
                          onTap: () => _edit(r),
                        ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  /// What the rule files money under, or null for ignore.
  String? _destination(PartyRule r, Map<int, Category> categories,
          Map<int, SavingsGoal> goals) =>
      switch (r.disposition) {
        PartyDisposition.expense ||
        PartyDisposition.income =>
          categories[r.categoryId]?.name,
        PartyDisposition.savings => goals[r.goalId]?.name,
        PartyDisposition.ignore => null,
      };
}

class _RuleTile extends StatelessWidget {
  final PartyRule rule;
  final String? destination;
  final VoidCallback onTap;
  const _RuleTile({
    required this.rule,
    required this.destination,
    required this.onTap,
  });

  String get _dispositionLabel => switch (rule.disposition) {
        PartyDisposition.expense => 'مصروف',
        PartyDisposition.income => 'دخل',
        PartyDisposition.savings => 'ادخار',
        PartyDisposition.ignore => 'تجاهل',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final named = rule.displayName != null;
    final chip = destination == null
        ? _dispositionLabel
        : '$_dispositionLabel · $destination';
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        onTap: onTap,
        title: Text(rule.displayName ?? rule.rawParty),
        // The bank's own string stays visible under a name the user gave it,
        // so a renamed "KR-133" can still be recognised in a message.
        subtitle: named ? Text(rule.rawParty) : null,
        trailing: Container(
          // A long category name must shorten, not push the party off-screen.
          constraints: const BoxConstraints(maxWidth: 150),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: rule.disposition == PartyDisposition.ignore
                ? scheme.surfaceContainerHighest
                : scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(AppRadii.chip),
          ),
          child: Text(
            chip,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppTextSizes.label,
              color: rule.disposition == PartyDisposition.ignore
                  ? scheme.onSurfaceVariant
                  : scheme.onSecondaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}
