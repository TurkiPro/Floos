import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/year_review.dart';

Category _cat(int id, TxnType type, {int? parentId}) => Category(
      id: id,
      name: 'c$id',
      iconKey: 'k',
      colorValue: 0,
      type: type,
      kind: CategoryKind.essential,
      archived: false,
      sortOrder: 0,
      parentId: parentId,
    );

final _salaryCat = _cat(9, TxnType.income);
final _food = _cat(1, TxnType.expense);
final _coffee = _cat(2, TxnType.expense, parentId: 1);
final _rent = _cat(3, TxnType.expense);
final _fun = _cat(4, TxnType.expense);

var _id = 1;
TxnRow _row(Category c, double amount, DateTime date, {int? recurrenceId}) =>
    TxnRow(
      txn: Txn(
        id: _id++,
        amount: amount,
        categoryId: c.id,
        type: c.type,
        date: date,
        recurrenceId: recurrenceId,
        createdAt: date,
      ),
      category: c,
    );

SavingsContribution _save(double amount, DateTime date) => SavingsContribution(
    id: _id++,
    goalId: 1,
    amount: amount,
    date: date,
    external: false,
    planned: false);

final _salary = [
  RecurrenceRule(
    id: 1,
    title: 'راتب',
    amount: 10000,
    categoryId: 9,
    type: TxnType.income,
    frequency: Frequency.monthly,
    interval: 1,
    startDate: DateTime(2025, 1, 25),
    active: true,
  ),
];

// Payday on the 25th: the current cycle is 25 Oct – 24 Nov 2026, and with the
// eleven before it the review reaches back to 25 Nov 2025.
final _now = DateTime(2026, 11, 5);

void main() {
  final rows = [
    // Outside the twelve cycles: must not count anywhere.
    _row(_salaryCat, 10000, DateTime(2025, 10, 25)),
    _row(_fun, 5000, DateTime(2025, 11, 24)), // last day before the window
    // A strong cycle: 25 Aug – 24 Sep.
    _row(_salaryCat, 10000, DateTime(2026, 8, 25)),
    _row(_rent, 3000, DateTime(2026, 8, 26), recurrenceId: 7),
    _row(_food, 1000, DateTime(2026, 9, 3)),
    // A weak one: 25 Sep – 24 Oct.
    _row(_salaryCat, 10000, DateTime(2026, 9, 25)),
    _row(_rent, 3000, DateTime(2026, 9, 26), recurrenceId: 7),
    _row(_fun, 4000, DateTime(2026, 10, 2)),
    _row(_coffee, 500, DateTime(2026, 10, 10)),
    // The cycle in progress, saving everything so far.
    _row(_salaryCat, 10000, DateTime(2026, 10, 25)),
  ];
  final contributions = [
    _save(4000, DateTime(2026, 8, 28)), // 40% of that salary
    _save(500, DateTime(2026, 9, 28)), // 5%
    _save(9000, DateTime(2026, 10, 26)), // 90%, but the cycle is not over
  ];

  final r = yearReview(
    rows: rows,
    contributions: contributions,
    incomeRules: _salary,
    now: _now,
  );

  test('covers the last twelve cycles only, oldest first', () {
    expect(r.cycles.map((c) => c.period.start), [
      DateTime(2026, 8, 25),
      DateTime(2026, 9, 25),
      DateTime(2026, 10, 25),
    ]);
    expect(r.isCurrent(r.cycles.last), isTrue);
    expect(r.income, 30000, reason: 'the Oct 2025 salary is outside');
    expect(r.spent, 3000 + 1000 + 3000 + 4000 + 500);
    expect(r.saved, 4000 + 500 + 9000);
  });

  test('best and worst are completed cycles only', () {
    expect(r.best!.period.start, DateTime(2026, 8, 25));
    expect(r.worst!.period.start, DateTime(2026, 9, 25),
        reason: 'the 90% current cycle is not over, so it cannot be best');
  });

  test('top categories roll subcategories into their parent', () {
    final top = {for (final s in r.topCategories) s.categoryId: s.total};
    expect(top[1], 1500, reason: 'food 1000 + coffee 500');
    expect(top[3], 6000);
    expect(r.topCategories.first.categoryId, 3);
    expect(top.containsKey(2), isFalse);
  });

  test('committed versus discretionary', () {
    expect(r.committed, 6000);
    expect(r.discretionary, 1000 + 4000 + 500);
  });

  test('each cycle states what the cycle-detail screen sums for it', () {
    // MonthDetailScreen sums income and expense over watchForRange(start,
    // end). This screen must say the same thing for every cycle it shows.
    for (final c in r.cycles) {
      var income = 0.0, expense = 0.0;
      for (final t in rows) {
        if (t.txn.date.isBefore(c.period.start) ||
            !t.txn.date.isBefore(c.period.end)) {
          continue;
        }
        if (t.txn.type == TxnType.income) {
          income += t.txn.amount;
        } else {
          expense += t.txn.amount;
        }
      }
      expect(c.income, income, reason: '${c.period.start} income');
      expect(c.spent, expense, reason: '${c.period.start} spent');
    }
  });

  test('fewer than twelve cycles of history is fine', () {
    final short = yearReview(
      rows: [_row(_salaryCat, 10000, DateTime(2026, 10, 25))],
      contributions: const [],
      incomeRules: _salary,
      now: _now,
    );
    expect(short.cycles, hasLength(1));
    expect(short.best, isNull);
    expect(short.worst, isNull);
  });
}
