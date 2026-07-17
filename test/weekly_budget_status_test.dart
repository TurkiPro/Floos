import 'package:flutter_test/flutter_test.dart';
import 'package:floos/domain/weekly_budget_status.dart';

void main() {
  group('WeeklyBudgetStatus', () {
    test('within budget: shows remaining, not over', () {
      const s = WeeklyBudgetStatus(budget: 700, spent: 450);
      expect(s.isOver, isFalse);
      expect(s.remaining, 250);
      expect(s.over, 0);
      expect(s.ratio, closeTo(450 / 700, 1e-9));
    });

    test('over budget: shows the overshoot, ratio clamps to 1', () {
      const s = WeeklyBudgetStatus(budget: 700, spent: 850);
      expect(s.isOver, isTrue);
      expect(s.over, 150);
      expect(s.remaining, 0);
      expect(s.ratio, 1.0);
    });

    test('spending exactly the budget is not "over"', () {
      const s = WeeklyBudgetStatus(budget: 700, spent: 700);
      expect(s.isOver, isFalse);
      expect(s.remaining, 0);
      expect(s.over, 0);
    });

    test('no budget: bar is empty until something is spent, then over', () {
      expect(const WeeklyBudgetStatus(budget: 0, spent: 0).ratio, 0.0);
      expect(const WeeklyBudgetStatus(budget: 0, spent: 0).isOver, isFalse);
      expect(const WeeklyBudgetStatus(budget: 0, spent: 10).ratio, 1.0);
      expect(const WeeklyBudgetStatus(budget: 0, spent: 10).isOver, isTrue);
      expect(const WeeklyBudgetStatus(budget: 0, spent: 10).over, 10);
    });
  });
}
