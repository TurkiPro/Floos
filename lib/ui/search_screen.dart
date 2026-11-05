import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../data/enums.dart';
import '../domain/date_grouping.dart';
import '../domain/txn_search.dart';
import 'theme/tokens.dart';
import 'widgets/category_picker.dart';
import 'widgets/day_group_card.dart';

/// Find any transaction by merchant, note, category or amount.
///
/// Results use the same [DayGroupCard] rows as the cycle screens, so tapping
/// to edit and swiping to delete (with undo) behave exactly as they do there.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _text = TextEditingController();
  Timer? _debounce;
  TxnQuery _query = const TxnQuery();

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onTextChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _query = _query.copyWith(text: value));
    });
  }

  void _setType(TxnType? type) {
    setState(() {
      // A category belongs to one type; keeping an expense category while
      // switching to income would silently match nothing.
      final keepCategory = type == null || type == _categoryType;
      _query = _query.copyWith(
        type: () => type,
        categoryId: keepCategory ? null : () => null,
      );
    });
  }

  TxnType? _categoryType;

  Future<void> _pickCategory(AppDatabase db) async {
    final type = _query.type ?? TxnType.expense;
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: CategoryPicker(
            db: db,
            type: type,
            selectedId: _query.categoryId,
            onChanged: (id) => Navigator.of(sheetContext).pop(id),
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _categoryType = type;
      _query = _query.copyWith(categoryId: () => picked);
    });
  }

  String _rangeLabel(SearchRange r) => switch (r) {
        SearchRange.thisCycle => 'هذه الدورة',
        SearchRange.last3Cycles => 'آخر ٣ دورات',
        SearchRange.last12Cycles => 'آخر ١٢ دورة',
        SearchRange.all => 'الكل',
      };

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final money = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _text,
          autofocus: true,
          onChanged: _onTextChanged,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'ابحث عن تاجر، ملاحظة، فئة أو مبلغ',
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_text.text.isNotEmpty)
            IconButton(
              tooltip: 'مسح',
              icon: const Icon(Icons.close),
              onPressed: () {
                _text.clear();
                _debounce?.cancel();
                setState(() => _query = _query.copyWith(text: ''));
              },
            ),
        ],
      ),
      body: StreamBuilder<List<TxnRow>>(
        stream: db.transactionDao.watchAllWithCategory(),
        builder: (context, txnSnap) {
          return StreamBuilder<List<RecurrenceRule>>(
            stream: db.recurrenceDao.watchByType(TxnType.income),
            builder: (context, rulesSnap) {
              return StreamBuilder<List<Category>>(
                stream: db.categoryDao.watchAll(),
                builder: (context, catSnap) {
                  final categories = {
                    for (final c in catSnap.data ?? const <Category>[]) c.id: c
                  };
                  final rows = txnSnap.data ?? const <TxnRow>[];
                  final results = searchTransactions(
                    rows,
                    _query,
                    categoriesById: categories,
                    incomeRules: rulesSnap.data ?? const <RecurrenceRule>[],
                    now: DateTime.now(),
                  );
                  return _body(context, db, results, categories, money,
                      loaded: txnSnap.hasData);
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AppDatabase db,
    List<TxnRow> results,
    Map<int, Category> categories,
    NumberFormat money, {
    required bool loaded,
  }) {
    final totals = searchTotals(results);
    final groups = groupByDay(results, (r) => r.txn.date);
    final now = DateTime.now();
    final selectedCategory =
        _query.categoryId == null ? null : categories[_query.categoryId];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            for (final t in <TxnType?>[null, TxnType.expense, TxnType.income])
              ChoiceChip(
                label: Text(switch (t) {
                  null => 'الكل',
                  TxnType.expense => 'مصروفات',
                  TxnType.income => 'دخل',
                }),
                selected: _query.type == t,
                onSelected: (_) => _setType(t),
              ),
            InputChip(
              avatar: const Icon(Icons.category_outlined, size: 18),
              label: Text(selectedCategory?.name ?? 'الفئة'),
              selected: selectedCategory != null,
              onPressed: () => _pickCategory(db),
              onDeleted: selectedCategory == null
                  ? null
                  : () => setState(() =>
                      _query = _query.copyWith(categoryId: () => null)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            for (final r in SearchRange.values)
              ChoiceChip(
                label: Text(_rangeLabel(r)),
                selected: _query.range == r,
                onSelected: (_) =>
                    setState(() => _query = _query.copyWith(range: r)),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (loaded) _Summary(totals: totals, money: money),
        const SizedBox(height: AppSpacing.md),
        if (loaded && results.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: Center(child: Text('لا توجد عمليات مطابقة')),
          )
        else
          for (final group in groups) ...[
            DayGroupCard(
                key: ValueKey(group.key),
                group: group,
                money: money,
                today: now),
            const SizedBox(height: AppSpacing.md),
          ],
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  final ({int count, double expense, double income}) totals;
  final NumberFormat money;
  const _Summary({required this.totals, required this.money});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      '${totals.count} عملية',
      if (totals.expense > 0) 'مصروفات ${money.format(totals.expense)} ⃁',
      if (totals.income > 0) 'دخل ${money.format(totals.income)} ⃁',
    ];
    return Text(
      parts.join(' · '),
      textAlign: TextAlign.center,
      style: const TextStyle(fontWeight: FontWeight.w600),
    );
  }
}
