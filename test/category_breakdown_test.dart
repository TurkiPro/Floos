import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/category_breakdown.dart';

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

TxnRow _row(Category cat, double amount, {TxnType? type}) => TxnRow(
      txn: Txn(
        id: 1,
        amount: amount,
        categoryId: cat.id,
        type: type ?? cat.type,
        date: DateTime(2026, 7, 1),
        createdAt: DateTime(2026, 7, 1),
      ),
      category: cat,
    );

void main() {
  group('categoryBreakdown', () {
    test('sums per top category and sorts biggest first', () {
      final food = _cat(id: 1);
      final transport = _cat(id: 2);
      final stats = categoryBreakdown([
        _row(transport, 30),
        _row(food, 100),
        _row(food, 50),
      ]);
      expect(stats.length, 2);
      expect(stats.first.categoryId, 1); // food, biggest total
      expect(stats.first.total, 150);
      expect(stats.last.categoryId, 2);
    });

    test('rolls sub-categories up into their parent', () {
      final food = _cat(id: 1);
      final coffee = _cat(id: 11, parentId: 1);
      final stats = categoryBreakdown([
        _row(food, 40),
        _row(coffee, 60),
      ]);
      expect(stats.length, 1);
      expect(stats.single.categoryId, 1);
      expect(stats.single.total, 100);
      expect(stats.single.count, 2);
    });

    test('count and average are per rolled-up category', () {
      final food = _cat(id: 1);
      final stats = categoryBreakdown([
        _row(food, 100),
        _row(food, 50),
        _row(food, 30),
      ]);
      expect(stats.single.count, 3);
      expect(stats.single.average, closeTo(60, 0.001));
    });

    test('income rows are ignored', () {
      final food = _cat(id: 1);
      final salary = _cat(id: 9);
      final stats = categoryBreakdown([
        _row(food, 100),
        _row(salary, 5000, type: TxnType.income),
      ]);
      expect(stats.length, 1);
      expect(stats.single.categoryId, 1);
      expect(stats.single.total, 100);
    });
  });
}
