import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/txn_search.dart';

Category _cat(int id, String name, TxnType type, {int? parentId}) => Category(
      id: id,
      name: name,
      iconKey: 'k',
      colorValue: 0,
      type: type,
      kind: CategoryKind.essential,
      archived: false,
      sortOrder: 0,
      parentId: parentId,
    );

final _restaurants = _cat(1, 'مطاعم', TxnType.expense);
final _coffee = _cat(2, 'قهوة', TxnType.expense, parentId: 1);
final _groceries = _cat(3, 'بقالة', TxnType.expense);
final _salaryCat = _cat(9, 'راتب', TxnType.income);
final _byId = {
  for (final c in [_restaurants, _coffee, _groceries, _salaryCat]) c.id: c
};

var _nextId = 1;
TxnRow _row(Category cat, double amount, DateTime date, {String? note}) =>
    TxnRow(
      txn: Txn(
        id: _nextId++,
        amount: amount,
        categoryId: cat.id,
        type: cat.type,
        date: date,
        note: note,
        createdAt: date,
      ),
      category: cat,
    );

RecurrenceRule _salary() => RecurrenceRule(
      id: 1,
      title: 'راتب',
      amount: 10000,
      categoryId: 9,
      type: TxnType.income,
      frequency: Frequency.monthly,
      interval: 1,
      startDate: DateTime(2026, 1, 25),
      active: true,
    );

// Payday on the 25th: the current cycle is 25 Jul – 24 Aug.
final _now = DateTime(2026, 8, 5);

List<TxnRow> _search(List<TxnRow> rows, TxnQuery q) => searchTransactions(
      rows,
      q,
      categoriesById: _byId,
      incomeRules: [_salary()],
      now: _now,
    );

void main() {
  group('normalizeForSearch', () {
    test('hamza forms fold onto a bare alef', () {
      expect(normalizeForSearch('أسعار'), normalizeForSearch('اسعار'));
      expect(normalizeForSearch('إيجار'), normalizeForSearch('ايجار'));
      expect(normalizeForSearch('آخر'), normalizeForSearch('اخر'));
    });

    test('taa marbuta and alef maqsura fold', () {
      expect(normalizeForSearch('قهوة'), normalizeForSearch('قهوه'));
      expect(normalizeForSearch('مستشفى'), normalizeForSearch('مستشفي'));
    });

    test('tashkeel and tatweel are ignored', () {
      expect(normalizeForSearch('مَطاعِم'), normalizeForSearch('مطاعم'));
      expect(normalizeForSearch('مطـــاعم'), normalizeForSearch('مطاعم'));
    });

    test('Arabic-Indic and Persian digits become ASCII', () {
      expect(normalizeForSearch('٨٧'), '87');
      expect(normalizeForSearch('۸۷'), '87');
    });

    test('Latin case and whitespace runs are folded', () {
      expect(normalizeForSearch('  RED   Box '), 'red box');
    });
  });

  group('searchTransactions', () {
    test('matches the note', () {
      final rows = [
        _row(_restaurants, 30, DateTime(2026, 8, 1), note: 'RED BOX'),
        _row(_groceries, 50, DateTime(2026, 8, 1), note: 'بنده'),
      ];
      final out = _search(rows, const TxnQuery(text: 'red box'));
      expect(out.map((r) => r.txn.note), ['RED BOX']);
    });

    test('matches the category, and a parent name finds its subcategories',
        () {
      final rows = [
        _row(_coffee, 18, DateTime(2026, 8, 2), note: 'بارنز'),
        _row(_groceries, 50, DateTime(2026, 8, 2)),
      ];
      expect(_search(rows, const TxnQuery(text: 'مطاعم')), hasLength(1),
          reason: 'a coffee row is filed under the restaurants parent');
      expect(_search(rows, const TxnQuery(text: 'قهوه')), hasLength(1),
          reason: 'taa marbuta must not matter');
    });

    test('a plain number matches the amount, in either digit script', () {
      final rows = [
        _row(_groceries, 87, DateTime(2026, 8, 2)),
        _row(_groceries, 870, DateTime(2026, 8, 2)),
      ];
      expect(_search(rows, const TxnQuery(text: '87')).single.txn.amount, 87);
      expect(_search(rows, const TxnQuery(text: '٨٧')).single.txn.amount, 87);
      expect(
          _search(rows, const TxnQuery(text: '87.00')).single.txn.amount, 87);
    });

    test('a number is still tried as text', () {
      final rows = [
        _row(_groceries, 12, DateTime(2026, 8, 2), note: 'فاتورة 87'),
      ];
      expect(_search(rows, const TxnQuery(text: '87')), hasLength(1));
    });

    test('an expression is not treated as an amount', () {
      final rows = [_row(_groceries, 57, DateTime(2026, 8, 2))];
      expect(_search(rows, const TxnQuery(text: '45+12')), isEmpty);
    });

    test('filters by type', () {
      final rows = [
        _row(_salaryCat, 10000, DateTime(2026, 7, 25)),
        _row(_groceries, 50, DateTime(2026, 8, 2)),
      ];
      final out = _search(rows, const TxnQuery(type: TxnType.income));
      expect(out.single.txn.type, TxnType.income);
    });

    test('a top-level category filter includes its subcategories', () {
      final rows = [
        _row(_restaurants, 40, DateTime(2026, 8, 1)),
        _row(_coffee, 18, DateTime(2026, 8, 2)),
        _row(_groceries, 50, DateTime(2026, 8, 2)),
      ];
      expect(_search(rows, const TxnQuery(categoryId: 1)), hasLength(2));
      expect(_search(rows, const TxnQuery(categoryId: 2)), hasLength(1));
    });

    test('ranges are salary cycles, cut at the payday', () {
      final rows = [
        _row(_groceries, 1, DateTime(2026, 7, 25)), // first day of this cycle
        _row(_groceries, 2, DateTime(2026, 7, 24)), // last day of the previous
        _row(_groceries, 3, DateTime(2026, 5, 25)), // first day, 3 cycles back
        _row(_groceries, 4, DateTime(2026, 5, 24)), // just outside 3 cycles
        _row(_groceries, 5, DateTime(2025, 1, 1)), // a long time ago
      ];
      List<double> amounts(SearchRange r) =>
          _search(rows, TxnQuery(range: r)).map((t) => t.txn.amount).toList();

      expect(amounts(SearchRange.thisCycle), [1]);
      expect(amounts(SearchRange.last3Cycles), [1, 2, 3]);
      expect(amounts(SearchRange.last12Cycles), [1, 2, 3, 4]);
      expect(amounts(SearchRange.all), [1, 2, 3, 4, 5]);
    });

    test('newest first', () {
      final rows = [
        _row(_groceries, 1, DateTime(2026, 7, 26)),
        _row(_groceries, 2, DateTime(2026, 8, 3)),
      ];
      expect(_search(rows, const TxnQuery()).map((r) => r.txn.amount), [2, 1]);
    });
  });

  test('totals keep expense and income apart', () {
    final rows = [
      _row(_salaryCat, 10000, DateTime(2026, 7, 25)),
      _row(_groceries, 50, DateTime(2026, 8, 2)),
      _row(_groceries, 25, DateTime(2026, 8, 3)),
    ];
    final t = searchTotals(rows);
    expect(t.count, 3);
    expect(t.expense, 75);
    expect(t.income, 10000);
  });
}
