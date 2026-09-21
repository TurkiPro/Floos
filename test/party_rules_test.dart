import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
  });

  Future<int> aGoal() =>
      db.savingsDao.addGoal(name: 'سيارة', targetAmount: 1000);

  group('remember / lookup', () {
    test('round-trips an expense rule', () async {
      await db.partyRuleDao.remember(
        rawParty: 'RED BOX',
        disposition: PartyDisposition.expense,
        categoryId: 1,
      );
      final rule = await db.partyRuleDao.lookup('RED BOX');
      expect(rule, isNotNull);
      expect(rule!.disposition, PartyDisposition.expense);
      expect(rule.categoryId, 1);
      expect(rule.rawParty, 'RED BOX');
      expect(rule.partyKey, 'red box');
    });

    test('round-trips a savings rule', () async {
      final goalId = await aGoal();
      await db.partyRuleDao.remember(
        rawParty: '**7772',
        disposition: PartyDisposition.savings,
        displayName: 'حسابي للادخار',
        goalId: goalId,
      );
      final rule = await db.partyRuleDao.lookup('**7772');
      expect(rule!.disposition, PartyDisposition.savings);
      expect(rule.goalId, goalId);
      expect(rule.displayName, 'حسابي للادخار');
    });

    test('round-trips an ignore rule with no category or goal', () async {
      await db.partyRuleDao
          .remember(rawParty: 'ابل باي', disposition: PartyDisposition.ignore);
      final rule = await db.partyRuleDao.lookup('ابل باي');
      expect(rule!.disposition, PartyDisposition.ignore);
      expect(rule.categoryId, isNull);
      expect(rule.goalId, isNull);
    });

    test('lookup is case- and whitespace-insensitive', () async {
      await db.partyRuleDao.remember(
        rawParty: 'RED BOX',
        disposition: PartyDisposition.expense,
        categoryId: 1,
      );
      expect(await db.partyRuleDao.lookup('  red   box '), isNotNull);
    });

    test('an unknown party has no rule', () async {
      expect(await db.partyRuleDao.lookup('NOPE'), isNull);
      expect(await db.partyRuleDao.lookup(''), isNull);
    });

    test('remembering the same party twice updates, never duplicates',
        () async {
      await db.partyRuleDao.remember(
        rawParty: 'RED BOX',
        disposition: PartyDisposition.expense,
        categoryId: 1,
      );
      await db.partyRuleDao.remember(
        rawParty: 'red box',
        disposition: PartyDisposition.expense,
        categoryId: 2,
        displayName: 'ريد بوكس',
      );
      final all = await db.partyRuleDao.getAll();
      expect(all, hasLength(1));
      expect(all.single.categoryId, 2);
      expect(all.single.displayName, 'ريد بوكس');
    });

    test('a truncated name finds a rule saved under the full one', () async {
      await db.partyRuleDao.remember(
        rawParty: 'Ali bin Abi Taleb',
        disposition: PartyDisposition.expense,
        categoryId: 1,
      );
      final rule = await db.partyRuleDao.lookup('Ali bin Ab');
      expect(rule, isNotNull);
      expect(rule!.rawParty, 'Ali bin Abi Taleb');
    });

    test('an exact match wins over a prefix match', () async {
      await db.partyRuleDao.remember(
        rawParty: 'eski kebap house',
        disposition: PartyDisposition.expense,
        categoryId: 1,
      );
      await db.partyRuleDao.remember(
        rawParty: 'eski kebap',
        disposition: PartyDisposition.expense,
        categoryId: 2,
      );
      final rule = await db.partyRuleDao.lookup('eski kebap');
      expect(rule!.categoryId, 2, reason: 'the exact rule, not the longer one');
    });
  });

  group('invalid combinations are refused', () {
    test('expense without a category', () {
      expect(
        () => db.partyRuleDao
            .remember(rawParty: 'X', disposition: PartyDisposition.expense),
        throwsArgumentError,
      );
    });

    test('savings without a goal', () {
      expect(
        () => db.partyRuleDao
            .remember(rawParty: 'X', disposition: PartyDisposition.savings),
        throwsArgumentError,
      );
    });

    test('ignore carrying a category', () {
      expect(
        () => db.partyRuleDao.remember(
          rawParty: 'X',
          disposition: PartyDisposition.ignore,
          categoryId: 1,
        ),
        throwsArgumentError,
      );
    });

    test('expense carrying a goal', () async {
      final goalId = await aGoal();
      expect(
        () => db.partyRuleDao.remember(
          rawParty: 'X',
          disposition: PartyDisposition.expense,
          categoryId: 1,
          goalId: goalId,
        ),
        throwsArgumentError,
      );
    });

    test('a blank party', () {
      expect(
        () => db.partyRuleDao.remember(
          rawParty: '   ',
          disposition: PartyDisposition.ignore,
        ),
        throwsArgumentError,
      );
    });
  });

  group('cascades', () {
    test('deleting a category takes its expense rule with it', () async {
      final catId = await db.categoryDao.add(
        name: 'اختبار',
        iconKey: 'category',
        colorValue: 0xFF000000,
        type: TxnType.expense,
      );
      await db.partyRuleDao.remember(
        rawParty: 'RED BOX',
        disposition: PartyDisposition.expense,
        categoryId: catId,
      );
      expect(await db.partyRuleDao.getAll(), hasLength(1));

      await (db.delete(db.categories)..where((c) => c.id.equals(catId))).go();
      expect(await db.partyRuleDao.getAll(), isEmpty);
    });

    test('deleting a goal takes its savings rule with it', () async {
      final goalId = await aGoal();
      await db.partyRuleDao.remember(
        rawParty: '**7772',
        disposition: PartyDisposition.savings,
        goalId: goalId,
      );
      expect(await db.partyRuleDao.getAll(), hasLength(1));

      await (db.delete(db.savingsGoals)..where((g) => g.id.equals(goalId)))
          .go();
      expect(await db.partyRuleDao.getAll(), isEmpty);
    });
  });
}
