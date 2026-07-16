import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/budget_risk.dart';

Category _cat({required int id, int? parentId}) => Category(
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

TxnRow _exp(int catId, double amount, DateTime date, {int? parentId}) => TxnRow(
      txn: Txn(
        id: 1,
        amount: amount,
        categoryId: catId,
        type: TxnType.expense,
        date: date,
        createdAt: date,
      ),
      category: _cat(id: catId, parentId: parentId),
    );

CategoryBudget _budget(int categoryId, double amount) =>
    CategoryBudget(id: categoryId, categoryId: categoryId, amount: amount);

void main() {
  // Day 16 of a 31-day month: pace projects to ~1.94x the spend so far.
  final now = DateTime(2026, 7, 16);

  test('flags a budget the pace will blow, and rolls sub-categories up', () {
    final risks = budgetRisks(
      [_budget(1, 1000)],
      [
        _exp(1, 400, DateTime(2026, 7, 5)),
        _exp(11, 200, DateTime(2026, 7, 10), parentId: 1), // rolls up to 1
      ],
      now,
    );
    expect(risks.length, 1);
    expect(risks.single.categoryId, 1);
    expect(risks.single.spent, 600);
    // 600 * 31 / 16 = 1162.5 > 1000
    expect(risks.single.projected, closeTo(1162.5, 1e-6));
    expect(risks.single.overBy, closeTo(162.5, 1e-6));
  });

  test('a budget the pace stays under is not flagged', () {
    final risks = budgetRisks(
      [_budget(1, 2000)],
      [_exp(1, 500, DateTime(2026, 7, 5))], // projects to ~969, under 2000
      now,
    );
    expect(risks, isEmpty);
  });

  test('a category with no spend is ignored', () {
    final risks = budgetRisks([_budget(1, 100)], const [], now);
    expect(risks, isEmpty);
  });

  test('already-over vs merely-projected split', () {
    final risks = budgetRisks(
      [_budget(1, 1000), _budget(2, 1000)],
      [
        _exp(1, 1200, DateTime(2026, 7, 5)), // past budget already
        _exp(2, 600, DateTime(2026, 7, 5)), // only projected to exceed
      ],
      now,
    );
    final over = {for (final r in risks) r.categoryId: r};

    expect(over[1]!.alreadyOver, isTrue);
    expect(over[1]!.spentOverPct, closeTo(20, 1e-6)); // (1200-1000)/1000

    expect(over[2]!.alreadyOver, isFalse);
    expect(over[2]!.spentOverPct, 0, reason: 'not actually over yet');
    expect(over[2]!.overByPct, greaterThan(0), reason: 'but projected over');
  });
}
