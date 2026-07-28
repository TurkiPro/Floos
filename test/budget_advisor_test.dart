import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/budget_advisor.dart';

// A fixed "now" so cycle math is deterministic. With a salary on the 25th, the
// current period is [2026-06-25, 2026-07-25) and the completed cycles before it
// are the five 25th-to-25th windows back to 2026-01-25.
final now = DateTime(2026, 7, 15);

Category _cat({
  required int id,
  CategoryKind kind = CategoryKind.essential,
  int? parentId,
}) =>
    Category(
      id: id,
      name: 'c$id',
      iconKey: 'k',
      colorValue: 0,
      type: TxnType.expense,
      kind: kind,
      archived: false,
      sortOrder: 0,
      parentId: parentId,
    );

TxnRow _exp({
  required int catId,
  required double amount,
  required DateTime date,
  CategoryKind kind = CategoryKind.essential,
  int? parentId,
}) =>
    TxnRow(
      txn: Txn(
        id: 1,
        amount: amount,
        categoryId: catId,
        type: TxnType.expense,
        date: date,
        createdAt: date,
      ),
      category: _cat(id: catId, kind: kind, parentId: parentId),
    );

RecurrenceRule _salary({
  double amount = 10000,
  DateTime? start,
  DateTime? lastPaid,
}) =>
    RecurrenceRule(
      id: 1,
      title: 'راتب',
      amount: amount,
      categoryId: 9,
      type: TxnType.income,
      frequency: Frequency.monthly,
      interval: 1,
      startDate: start ?? DateTime(2026, 1, 25),
      lastPaidDate: lastPaid,
      active: true,
    );

// A recurring obligation row (rent/subscription): carries a recurrenceId, so
// it's committed and must be excluded from the discretionary median.
TxnRow _recurring({
  required int catId,
  required double amount,
  required DateTime date,
  CategoryKind kind = CategoryKind.essential,
}) =>
    TxnRow(
      txn: Txn(
        id: 1,
        amount: amount,
        categoryId: catId,
        type: TxnType.expense,
        date: date,
        recurrenceId: 99,
        createdAt: date,
      ),
      category: _cat(id: catId, kind: kind),
    );

Map<int, BudgetSuggestion> _byId(List<BudgetSuggestion> xs) =>
    {for (final s in xs) s.categoryId: s};

void main() {
  group('suggestBudgets — income seed (day one)', () {
    final cats = [
      _cat(id: 1), // essential
      _cat(id: 2), // essential
      _cat(id: 3, kind: CategoryKind.luxury),
    ];

    test('splits income 50/30 across essentials/luxuries, evenly within each',
        () {
      final s = _byId(suggestBudgets(
        rows: const [],
        topExpenseCats: cats,
        incomeRules: [_salary(amount: 10000)],
        expenseRules: const [],
        contributions: const [],
        now: now,
        lifestyleFactor: 1.0,
      ));
      // needs pool = 5000 over two essentials -> 2500 each;
      // wants pool = 3000 over one luxury -> 3000.
      expect(s[1]!.amount, 2500);
      expect(s[2]!.amount, 2500);
      expect(s[3]!.amount, 3000);
      expect(s[1]!.basis, BudgetSuggestionBasis.fromIncome);
      expect(s[1]!.cyclesUsed, 0);
    });

    test('lifestyle factor scales the seed and stays rounded to 10', () {
      final frugal = _byId(suggestBudgets(
        rows: const [],
        topExpenseCats: cats,
        incomeRules: [_salary(amount: 10000)],
        expenseRules: const [],
        contributions: const [],
        now: now,
        lifestyleFactor: 0.8,
      ));
      final comfy = _byId(suggestBudgets(
        rows: const [],
        topExpenseCats: cats,
        incomeRules: [_salary(amount: 10000)],
        expenseRules: const [],
        contributions: const [],
        now: now,
        lifestyleFactor: 1.2,
      ));
      expect(frugal[1]!.amount, 2000); // 2500 * 0.8
      expect(frugal[3]!.amount, 2400); // 3000 * 0.8
      expect(comfy[1]!.amount, 3000); // 2500 * 1.2
      expect(comfy[3]!.amount, 3600); // 3000 * 1.2
    });

    test('no income at all yields no suggestions', () {
      final out = suggestBudgets(
        rows: const [],
        topExpenseCats: cats,
        incomeRules: const [],
        expenseRules: const [],
        contributions: const [],
        now: now,
        lifestyleFactor: 1.0,
      );
      expect(out, isEmpty);
    });
  });

  group('suggestBudgets — history median (established)', () {
    test('median of per-cycle spend, over only the active cycles', () {
      final rows = [
        _exp(catId: 1, amount: 100, date: DateTime(2026, 2, 1)),
        _exp(catId: 1, amount: 200, date: DateTime(2026, 3, 1)),
        _exp(catId: 1, amount: 300, date: DateTime(2026, 4, 1)),
      ];
      final s = _byId(suggestBudgets(
        rows: rows,
        topExpenseCats: [_cat(id: 1)],
        incomeRules: [_salary()],
        expenseRules: const [],
        contributions: const [],
        now: now,
        lifestyleFactor: 1.0,
      ));
      expect(s[1]!.amount, 200); // median(100,200,300)
      expect(s[1]!.basis, BudgetSuggestionBasis.fromHistory);
      expect(s[1]!.cyclesUsed, 3); // three cycles had spending
    });

    test('sub-category spend rolls up into the parent suggestion', () {
      final rows = [
        // one active cycle: parent (50) + child (150) => 200 under parent id 1.
        _exp(catId: 1, amount: 50, date: DateTime(2026, 2, 1)),
        _exp(catId: 11, amount: 150, date: DateTime(2026, 2, 2), parentId: 1),
      ];
      final s = _byId(suggestBudgets(
        rows: rows,
        topExpenseCats: [_cat(id: 1)],
        incomeRules: [_salary()],
        expenseRules: const [],
        contributions: const [],
        now: now,
        lifestyleFactor: 1.0,
      ));
      expect(s[1]!.amount, 200);
      expect(s[1]!.cyclesUsed, 1);
    });

    test('the in-progress current cycle is excluded from the median', () {
      final rows = [
        _exp(catId: 1, amount: 100, date: DateTime(2026, 2, 1)),
        _exp(catId: 1, amount: 200, date: DateTime(2026, 3, 1)),
        _exp(catId: 1, amount: 300, date: DateTime(2026, 4, 1)),
        // A huge spend inside the current period [06-25, 07-25): must not count.
        _exp(catId: 1, amount: 9999, date: DateTime(2026, 7, 1)),
      ];
      final s = _byId(suggestBudgets(
        rows: rows,
        topExpenseCats: [_cat(id: 1)],
        incomeRules: [_salary()],
        expenseRules: const [],
        contributions: const [],
        now: now,
        lifestyleFactor: 1.0,
      ));
      expect(s[1]!.amount, 200);
      expect(s[1]!.cyclesUsed, 3);
    });

    test('a category never spent on gets no suggestion (not income-seeded)',
        () {
      final rows = [
        _exp(catId: 1, amount: 100, date: DateTime(2026, 2, 1)),
      ];
      final out = suggestBudgets(
        rows: rows,
        topExpenseCats: [_cat(id: 1), _cat(id: 2)],
        incomeRules: [_salary()],
        expenseRules: const [],
        contributions: const [],
        now: now,
        lifestyleFactor: 1.0,
      );
      final s = _byId(out);
      expect(s.containsKey(1), isTrue);
      expect(s.containsKey(2), isFalse, reason: 'never spent -> no suggestion');
    });

    test('committed (recurring) spend is excluded from the median', () {
      final rows = [
        _exp(catId: 1, amount: 300, date: DateTime(2026, 2, 1)),
        // A big recurring obligation in the same category/cycle must not inflate
        // the discretionary budget.
        _recurring(catId: 1, amount: 5000, date: DateTime(2026, 2, 2)),
      ];
      final s = _byId(suggestBudgets(
        rows: rows,
        topExpenseCats: [_cat(id: 1)],
        incomeRules: [_salary()],
        expenseRules: const [],
        contributions: const [],
        now: now,
        lifestyleFactor: 1.0,
      ));
      expect(s[1]!.amount, 300, reason: 'the 5000 obligation is not budgeted');
    });
  });

  group('suggestBudgets — fitting to the salary envelope', () {
    test('protects essentials and trims luxuries when medians overshoot', () {
      // Salary 3000, no commitments/savings => disposable 3000. One completed
      // cycle with 2000 essential + 2000 luxury (total 4000 > 3000).
      final rows = [
        _exp(catId: 1, amount: 2000, date: DateTime(2026, 2, 1)),
        _exp(
            catId: 3,
            amount: 2000,
            date: DateTime(2026, 2, 1),
            kind: CategoryKind.luxury),
      ];
      final s = _byId(suggestBudgets(
        rows: rows,
        topExpenseCats: [_cat(id: 1), _cat(id: 3, kind: CategoryKind.luxury)],
        incomeRules: [_salary(amount: 3000)],
        expenseRules: const [],
        contributions: const [],
        now: now,
        lifestyleFactor: 1.0,
      ));
      // Essential kept whole; the luxury absorbs the whole cut so the total fits.
      expect(s[1]!.amount, 2000);
      expect(s[3]!.amount, 1000);
      expect(s[1]!.amount + s[3]!.amount, 3000);
    });

    test('commitments shrink the envelope the budgets must fit inside', () {
      // Salary 5000 − a 3000/mo obligation => disposable 2000. A 2500 essential
      // median scales down to the 2000 that's actually left.
      final obligation = RecurrenceRule(
        id: 50,
        title: 'إيجار',
        amount: 3000,
        categoryId: 1,
        type: TxnType.expense,
        frequency: Frequency.monthly,
        interval: 1,
        startDate: DateTime(2026, 1, 1),
        active: true,
      );
      final rows = [
        _exp(catId: 1, amount: 2500, date: DateTime(2026, 2, 1)),
      ];
      final s = _byId(suggestBudgets(
        rows: rows,
        topExpenseCats: [_cat(id: 1)],
        incomeRules: [_salary(amount: 5000)],
        expenseRules: [obligation],
        contributions: const [],
        now: now,
        lifestyleFactor: 1.0,
      ));
      expect(s[1]!.amount, 2000);
    });
  });

  group('previousCycles — early/late payday', () {
    test('a completed cycle is still recognised when the payday came early',
        () {
      // Salary scheduled on the 25th but actually paid on the 22nd of June, so
      // the current cycle starts 22 June. A full prior cycle of discretionary
      // spend must still switch the advisor onto history (not the income seed).
      final salary = _salary(amount: 6000, lastPaid: DateTime(2026, 6, 22));
      final rows = [
        _exp(catId: 1, amount: 400, date: DateTime(2026, 6, 1)),
      ];
      final s = _byId(suggestBudgets(
        rows: rows,
        topExpenseCats: [_cat(id: 1)],
        incomeRules: [salary],
        expenseRules: const [],
        contributions: const [],
        now: DateTime(2026, 7, 10),
        lifestyleFactor: 1.0,
      ));
      expect(s[1]!.basis, BudgetSuggestionBasis.fromHistory,
          reason: 'the early payday must not hide the completed cycle');
      expect(s[1]!.amount, 400);
    });
  });
}
