import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/database.dart';
import 'package:floos/domain/balance_transfers.dart';

SavingsContribution _c(double amount, DateTime date,
        {int goalId = 1, bool external = false}) =>
    SavingsContribution(
        id: 1, goalId: goalId, amount: amount, date: date, external: external);

Investment _i(String name, double amount, DateTime date,
        {bool external = false}) =>
    Investment(
        id: 1, name: name, amount: amount, date: date, external: external);

void main() {
  const names = {1: 'سيارة'};

  test('savings deposit is a balance outflow; a withdrawal is an inflow', () {
    final t = balanceTransfers(
      contributions: [
        _c(500, DateTime(2026, 7, 1)), // deposit
        _c(-200, DateTime(2026, 7, 3)), // withdraw
      ],
      investments: const [],
      goalNames: names,
    );
    // Newest first.
    expect(t[0].amount, 200); // the withdrawal came back to the balance
    expect(t[0].label, 'من الادخار: سيارة');
    expect(t[0].savings, isTrue);
    expect(t[1].amount, -500); // the deposit left the balance
    expect(t[1].label, 'إلى الادخار: سيارة');
  });

  test('investing is an outflow; selling is an inflow', () {
    final t = balanceTransfers(
      contributions: const [],
      investments: [
        _i('TASI', 1000, DateTime(2026, 7, 1)),
        _i('بيع', -400, DateTime(2026, 7, 2)),
      ],
      goalNames: const {},
    );
    expect(t[0].amount, 400);
    expect(t[0].label, 'من الاستثمار: بيع');
    expect(t[1].amount, -1000);
    expect(t[1].label, 'إلى الاستثمار: TASI');
    expect(t.every((x) => !x.savings), isTrue);
  });

  test('external (standalone) entries never touched the balance, excluded', () {
    final t = balanceTransfers(
      contributions: [_c(500, DateTime(2026, 7, 1), external: true)],
      investments: [_i('x', 1000, DateTime(2026, 7, 2), external: true)],
      goalNames: const {},
    );
    expect(t, isEmpty);
  });
}
