import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/budget_progress.dart';
import 'package:floos/domain/financial_period.dart';

// The current salary cycle = July, so July rows count and June ones don't.
final period = FinancialPeriod(DateTime(2026, 7, 1), DateTime(2026, 8, 1));

Category _cat({int id = 1, int? parentId}) => Category(
      id: id,
      name: 'c$id',
      iconKey: 'k',
      colorValue: 0,
      type: TxnType.expense,
      kind: CategoryKind.essential,
      archived: false,
      sortOrder: 0,
      parentId: parentId,
    );

TxnRow _expense(double amount, DateTime date, {int id = 1, int? parentId}) =>
    TxnRow(
      txn: Txn(
        id: 1,
        amount: amount,
        categoryId: id,
        type: TxnType.expense,
        date: date,
        createdAt: date,
      ),
      category: _cat(id: id, parentId: parentId),
    );

CategoryBudget _budget(int categoryId, double amount) =>
    CategoryBudget(id: categoryId, categoryId: categoryId, amount: amount);

void main() {
  group('budgetProgress', () {
    test('sums this-month expenses per top-level category', () {
      final budgets = [_budget(1, 500)];
      final rows = [
        _expense(200, DateTime(2026, 7, 3), id: 1),
        _expense(100, DateTime(2026, 7, 9), id: 1),
        // last month, ignored:
        _expense(999, DateTime(2026, 6, 1), id: 1),
      ];
      final lines = budgetProgress(budgets, rows, period);
      expect(lines, hasLength(1));
      expect(lines.single.spent, 300);
      expect(lines.single.budgeted, 500);
      expect(lines.single.remaining, 200);
      expect(lines.single.isOver, isFalse);
    });

    test('rolls sub-category spend up to the parent budget', () {
      final budgets = [_budget(1, 400)];
      final rows = [
        _expense(150, DateTime(2026, 7, 2), id: 10, parentId: 1),
        _expense(50, DateTime(2026, 7, 4), id: 11, parentId: 1),
      ];
      final lines = budgetProgress(budgets, rows, period);
      expect(lines.single.spent, 200);
    });

    test('ignores income and other categories', () {
      final budgets = [_budget(1, 100)];
      final rows = [
        _expense(80, DateTime(2026, 7, 2), id: 1),
        // different category, no budget:
        _expense(500, DateTime(2026, 7, 2), id: 2),
      ];
      final lines = budgetProgress(budgets, rows, period);
      expect(lines.single.spent, 80);
    });

    test('flags over-budget and keeps a >1 ratio', () {
      final budgets = [_budget(1, 100)];
      final rows = [_expense(130, DateTime(2026, 7, 2), id: 1)];
      final lines = budgetProgress(budgets, rows, period);
      expect(lines.single.isOver, isTrue);
      expect(lines.single.remaining, -30);
      expect(lines.single.ratio, closeTo(1.3, 1e-9));
    });

    test('a budget with no spend yet shows zero spent', () {
      final lines = budgetProgress([_budget(1, 100)], const [], period);
      expect(lines.single.spent, 0);
      expect(lines.single.ratio, 0);
    });

    test('sorts most-consumed first', () {
      final budgets = [_budget(1, 100), _budget(2, 100)];
      final rows = [
        _expense(20, DateTime(2026, 7, 2), id: 1), // 20%
        _expense(90, DateTime(2026, 7, 2), id: 2), // 90%
      ];
      final lines = budgetProgress(budgets, rows, period);
      expect(lines.first.categoryId, 2);
      expect(lines[1].categoryId, 1);
    });

    test('DAO setBudget upserts (one row per category)', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      // Category id 1 (طعام) is seeded on create.
      await db.budgetDao.setBudget(1, 500);
      await db.budgetDao.setBudget(1, 800); // replaces, not duplicates
      final all = await db.budgetDao.getAll();
      expect(all, hasLength(1));
      expect(all.single.amount, 800);

      await db.budgetDao.removeBudget(1);
      expect(await db.budgetDao.getAll(), isEmpty);
    });
  });
}
