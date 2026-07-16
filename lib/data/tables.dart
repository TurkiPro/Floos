import 'package:drift/drift.dart';

import 'enums.dart';

/// User-editable categories. Shipping a good default set (seeded on first run)
/// fixes the "five ugly fixed categories" problem in the original.
@DataClassName('Category')
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get iconKey => text().withLength(min: 1, max: 40)();
  IntColumn get colorValue => integer()(); // ARGB int
  IntColumn get type => intEnum<TxnType>()();
  // Null => a top-level category. Non-null => a sub-category of that parent.
  // Only two levels are supported (a sub-category never has children).
  IntColumn get parentId => integer().nullable().references(Categories, #id)();
  // Necessity vs discretionary; a sub-category may override its parent's kind.
  IntColumn get kind =>
      intEnum<CategoryKind>().withDefault(const Constant(0))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

/// A recurrence RULE — not pre-created rows. The engine evaluates this lazily
/// to materialise due transactions. One mechanism drives recurring income,
/// weekly expenses, and monthly bills (التزامات شهرية).
@DataClassName('RecurrenceRule')
class RecurrenceRules extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 80)();
  RealColumn get amount => real()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  IntColumn get type => intEnum<TxnType>()();
  IntColumn get frequency => intEnum<Frequency>()();
  IntColumn get interval =>
      integer().withDefault(const Constant(1))(); // every N units
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  // Through this date, transactions have already been generated. Advancing it
  // is what makes catch-up idempotent.
  DateTimeColumn get lastMaterialized => dateTime().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  TextColumn get note => text().nullable()();
  // A one-shot override for the NEXT occurrence only (e.g. this month's salary
  // landing a day or two early/late). [nextOverrideScheduled] is the scheduled
  // occurrence date being replaced; [nextOverrideDate] is the date to use
  // instead. Both are cleared the moment the engine materializes that
  // occurrence, so they never affect the month after.
  DateTimeColumn get nextOverrideScheduled => dateTime().nullable()();
  DateTimeColumn get nextOverrideDate => dateTime().nullable()();
}

@DataClassName('Txn')
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get amount => real()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  IntColumn get type => intEnum<TxnType>()();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().nullable()();
  // Non-null => this row was generated from a recurrence rule. ON DELETE SET
  // NULL: deleting a rule keeps its already-generated transactions (real money
  // that changed hands) but drops the now-dangling link.
  IntColumn get recurrenceId => integer()
      .nullable()
      .references(RecurrenceRules, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// A user-set monthly spending budget for one top-level category. At most one
/// row per category (enforced in the DAO by upserting). The "spent" side is
/// never stored — it's summed live from this month's transactions, same
/// ledger philosophy as savings.
@DataClassName('CategoryBudget')
class CategoryBudgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId =>
      integer().references(Categories, #id, onDelete: KeyAction.cascade)();
  RealColumn get amount => real()(); // monthly limit
}

/// Savings goal. The current balance is NOT stored here — it is summed from the
/// contributions ledger below. A stored balance is what drifts out of sync and
/// makes "savings" feel buggy.
@DataClassName('SavingsGoal')
class SavingsGoals extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  RealColumn get targetAmount => real()();
  DateTimeColumn get targetDate => dateTime().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('SavingsContribution')
class SavingsContributions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get goalId => integer().references(SavingsGoals, #id)();
  RealColumn get amount => real()();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().nullable()();
  // External deposits are money that already existed (a gift, prior savings),
  // not set aside from tracked income. They count toward a goal's total but
  // are excluded from the running balance and the savings rate — otherwise
  // they'd wrongly subtract from income the user never recorded.
  BoolColumn get external => boolean().withDefault(const Constant(false))();
}
