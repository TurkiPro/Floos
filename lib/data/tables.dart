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
  // The ACTUAL date of the most recent materialized occurrence. Differs from
  // [lastMaterialized] (the scheduled slot) when an override moved a payday
  // early or late: e.g. a July-25 salary pulled in to July 23 has
  // lastMaterialized = July 25 but lastPaidDate = July 23. The financial period
  // anchors to this, so "the day you were actually paid" starts the cycle.
  DateTimeColumn get lastPaidDate => dateTime().nullable()();
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
  // Non-null => this row came from a bank-message import. ON DELETE CASCADE:
  // deleting the batch row IS how "undo this import" works.
  //
  // Note this is deliberately the opposite of [recurrenceId] above. A
  // generated transaction is real money that outlives its rule, so that one
  // is SET NULL. An import is a single user action over text the app parsed
  // heuristically, so undoing it means those rows were never meant to exist.
  IntColumn get importBatchId => integer()
      .nullable()
      .references(ImportBatches, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// One run of the bank-message importer.
///
/// Exists so a whole batch can be taken back in one action: everything the
/// import wrote points here with ON DELETE CASCADE, so undo is a single row
/// delete that cannot half-apply. The counts are stored rather than derived so
/// the confirmation dialog can state what it is about to remove without a scan.
@DataClassName('ImportBatch')
class ImportBatches extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get importedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get rowCount => integer()();
  RealColumn get totalAmount => real()();
  // Rows the user marked "ignore" — parsed, deliberately not written.
  IntColumn get ignoredCount => integer().withDefault(const Constant(0))();
}

/// One remembered decision about a merchant or transfer destination, keyed by
/// the normalized string the bank sends ("RED BOX", "**7772", "KR-133").
///
/// The stored decision is a DISPOSITION, not just a category: a bank message
/// can be a purchase, income, a savings deposit, or nothing the ledger should
/// record at all. [displayName] exists because the bank's own strings are
/// frequently unreadable — a POS terminal code or an account number — and
/// naming one once should fix it forever.
@DataClassName('PartyRule')
class PartyRules extends Table {
  IntColumn get id => integer().autoIncrement()();
  // Normalized via partyKey(); unique, and the DAO upserts on it.
  TextColumn get partyKey => text().withLength(min: 1, max: 120)();
  // What the bank literally sent, kept for display and debugging.
  TextColumn get rawParty => text().withLength(min: 1, max: 120)();
  // The user's readable name for this party, if they gave one.
  TextColumn get displayName => text().nullable()();
  IntColumn get disposition => intEnum<PartyDisposition>()();
  // Set when disposition is expense/income. CASCADE: a rule pointing at a
  // deleted category can never be applied, so it goes with it.
  IntColumn get categoryId => integer()
      .nullable()
      .references(Categories, #id, onDelete: KeyAction.cascade)();
  // Set when disposition is savings.
  IntColumn get goalId => integer()
      .nullable()
      .references(SavingsGoals, #id, onDelete: KeyAction.cascade)();
  // The import that FIRST taught this rule. CASCADE so undoing that import
  // also forgets what it learned — otherwise "undo, fix, re-import" would
  // re-apply the same wrong category from the rule the bad import had just
  // created. A rule a later batch merely re-used keeps its original batch here
  // and is untouched when that later batch is undone.
  IntColumn get createdByBatchId => integer()
      .nullable()
      .references(ImportBatches, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {partyKey}
      ];
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

/// One free-text reflection the user wrote about a given week's budget outcome
/// (why they stayed on track, or why they overspent). Keyed by the week's start
/// (a Saturday). At most one per week — the DAO upserts. Kept so the weekly
/// performance view can show the user's own notes alongside each week.
@DataClassName('WeeklyReflection')
class WeeklyReflections extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get weekStart => dateTime()();
  TextColumn get note => text()();
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
  // Non-null => this deposit came from a bank-message import. CASCADE, for the
  // same reason as Transactions.importBatchId.
  IntColumn get importBatchId => integer()
      .nullable()
      .references(ImportBatches, #id, onDelete: KeyAction.cascade)();
}

/// A single investment entry — money put into a stock, fund, portfolio, etc.,
/// tracked separately from expenses (it's not spending). Only the amount put in
/// is recorded, never a live price (no networking). Like a savings deposit, a
/// non-[external] entry comes out of the current balance; an [external] one is a
/// standalone amount already invested elsewhere that doesn't touch the balance.
@DataClassName('Investment')
class Investments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  RealColumn get amount => real()();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().nullable()();
  BoolColumn get external => boolean().withDefault(const Constant(false))();
}
