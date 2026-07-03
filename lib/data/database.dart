import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'enums.dart';
import 'tables.dart';
import '../domain/date_grouping.dart';
import '../domain/recurrence_math.dart';

part 'database.g.dart';

/// A transaction joined with its category, for display in lists.
class TxnRow {
  final Txn txn;
  final Category category;
  const TxnRow({required this.txn, required this.category});
}

@DriftAccessor(tables: [Categories])
class CategoryDao extends DatabaseAccessor<AppDatabase> with _$CategoryDaoMixin {
  CategoryDao(super.db);

  Future<List<Category>> getAll() => select(categories).get();

  Stream<List<Category>> watchActive() {
    return (select(categories)
          ..where((c) => c.archived.equals(false))
          ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
        .watch();
  }

  Future<int> add({
    required String name,
    required String iconKey,
    required int colorValue,
    required TxnType type,
    int? parentId,
    CategoryKind kind = CategoryKind.essential,
    int sortOrder = 0,
  }) {
    return into(categories).insert(CategoriesCompanion.insert(
      name: name,
      iconKey: iconKey,
      colorValue: colorValue,
      type: type,
      parentId: Value(parentId),
      kind: Value(kind),
      sortOrder: Value(sortOrder),
    ));
  }

  /// Edits an existing category's editable fields. Its [type] and [parentId]
  /// are fixed after creation (they'd orphan sub-categories / mis-file
  /// history), so only presentation + kind are updatable here.
  Future<void> updateCategory({
    required int id,
    required String name,
    required String iconKey,
    required int colorValue,
    required CategoryKind kind,
  }) {
    return (update(categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        name: Value(name),
        iconKey: Value(iconKey),
        colorValue: Value(colorValue),
        kind: Value(kind),
      ),
    );
  }

  Future<void> archive(int id) {
    return (update(categories)..where((c) => c.id.equals(id)))
        .write(const CategoriesCompanion(archived: Value(true)));
  }

  Future<void> unarchive(int id) {
    return (update(categories)..where((c) => c.id.equals(id)))
        .write(const CategoriesCompanion(archived: Value(false)));
  }

  Stream<List<Category>> watchAll() {
    return (select(categories)
          ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
        .watch();
  }
}

@DriftAccessor(tables: [Transactions, Categories])
class TransactionDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionDaoMixin {
  TransactionDao(super.db);

  /// Reactive list of recent transactions joined with their category. Because
  /// this is a `.watch()` stream, inserting a transaction (including ones the
  /// recurrence engine generates) refreshes the UI automatically — no manual
  /// "refresh the month" step.
  Stream<List<TxnRow>> watchRecent({int limit = 200}) {
    final query = select(transactions).join([
      innerJoin(categories, categories.id.equalsExp(transactions.categoryId)),
    ])
      ..orderBy([
        OrderingTerm.desc(transactions.date),
        OrderingTerm.desc(transactions.id),
      ])
      ..limit(limit);
    return query.watch().map((rows) {
      return rows
          .map((r) => TxnRow(
                txn: r.readTable(transactions),
                category: r.readTable(categories),
              ))
          .toList();
    });
  }

  Future<int> add({
    required double amount,
    required int categoryId,
    required TxnType type,
    required DateTime date,
    String? note,
  }) {
    return into(transactions).insert(TransactionsCompanion.insert(
      amount: amount,
      categoryId: categoryId,
      type: type,
      date: date,
      note: Value(note),
    ));
  }

  Future<void> insertGenerated(RecurrenceRule rule, DateTime date) {
    return into(transactions).insert(TransactionsCompanion.insert(
      amount: rule.amount,
      categoryId: rule.categoryId,
      type: rule.type,
      date: date,
      note: Value(rule.note),
      recurrenceId: Value(rule.id),
    ));
  }

  Future<void> deleteById(int id) {
    return (delete(transactions)..where((t) => t.id.equals(id))).go();
  }

  /// Wipes all transactions -- used only by the dev data tools in Settings.
  Future<void> clearAll() => delete(transactions).go();

  /// Every distinct month that has at least one transaction, most recent
  /// first. Only pulls the `date` column (not full rows) and does the
  /// distinct/sort in Dart -- consistent with how the rest of the app treats
  /// dates (recurrence math, day grouping) as plain Dart `DateTime` values
  /// rather than relying on SQLite date functions.
  Stream<List<MonthKey>> watchActiveMonths() {
    final query = selectOnly(transactions)..addColumns([transactions.date]);
    return query.watch().map((rows) {
      final dates = rows.map((r) => r.read(transactions.date)!).toList();
      return distinctMonthsDesc(dates);
    });
  }

  /// Every transaction joined with its category, newest first, uncapped.
  /// Backs the home dashboard, which needs both all-time totals (for the
  /// running balance) and the current month's expense list from one stream.
  Stream<List<TxnRow>> watchAllWithCategory() {
    final query = select(transactions).join([
      innerJoin(categories, categories.id.equalsExp(transactions.categoryId)),
    ])
      ..orderBy([
        OrderingTerm.desc(transactions.date),
        OrderingTerm.desc(transactions.id),
      ]);
    return query.watch().map((rows) {
      return rows
          .map((r) => TxnRow(
                txn: r.readTable(transactions),
                category: r.readTable(categories),
              ))
          .toList();
    });
  }

  /// Transactions within a single month, joined with their category. Backs
  /// month-detail browsing -- a ranged query rather than filtering
  /// [watchRecent], since that stream is capped and would silently show an
  /// incomplete picture for a month older than the cap.
  Stream<List<TxnRow>> watchForMonth(MonthKey month) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final query = select(transactions).join([
      innerJoin(categories, categories.id.equalsExp(transactions.categoryId)),
    ])
      ..where(transactions.date.isBiggerOrEqualValue(start) &
          transactions.date.isSmallerThanValue(end))
      ..orderBy([
        OrderingTerm.desc(transactions.date),
        OrderingTerm.desc(transactions.id),
      ]);
    return query.watch().map((rows) {
      return rows
          .map((r) => TxnRow(
                txn: r.readTable(transactions),
                category: r.readTable(categories),
              ))
          .toList();
    });
  }
}

@DriftAccessor(tables: [RecurrenceRules])
class RecurrenceDao extends DatabaseAccessor<AppDatabase>
    with _$RecurrenceDaoMixin {
  RecurrenceDao(super.db);

  Stream<List<RecurrenceRule>> watchAll() {
    return (select(recurrenceRules)
          ..orderBy([
            (r) => OrderingTerm.desc(r.active),
            (r) => OrderingTerm.asc(r.title),
          ]))
        .watch();
  }

  Stream<List<RecurrenceRule>> watchByType(TxnType type) {
    return (select(recurrenceRules)
          ..where((r) => r.type.equalsValue(type))
          ..orderBy([
            (r) => OrderingTerm.desc(r.active),
            (r) => OrderingTerm.asc(r.title),
          ]))
        .watch();
  }

  Future<List<RecurrenceRule>> activeRules() {
    return (select(recurrenceRules)..where((r) => r.active.equals(true))).get();
  }

  Future<int> add({
    required String title,
    required double amount,
    required int categoryId,
    required TxnType type,
    required Frequency frequency,
    int interval = 1,
    required DateTime startDate,
    DateTime? endDate,
    String? note,
  }) {
    return into(recurrenceRules).insert(RecurrenceRulesCompanion.insert(
      title: title,
      amount: amount,
      categoryId: categoryId,
      type: type,
      frequency: frequency,
      interval: Value(interval),
      startDate: startDate,
      endDate: Value(endDate),
      note: Value(note),
    ));
  }

  Future<void> setLastMaterialized(int id, DateTime date) {
    return (update(recurrenceRules)..where((r) => r.id.equals(id)))
        .write(RecurrenceRulesCompanion(lastMaterialized: Value(date)));
  }

  Future<void> pause(int id) {
    return (update(recurrenceRules)..where((r) => r.id.equals(id)))
        .write(const RecurrenceRulesCompanion(active: Value(false)));
  }

  /// Re-enable a paused rule WITHOUT backfilling the paused gap: move the marker
  /// to today so catch-up only generates occurrences from here on.
  Future<void> reactivate(int id, {DateTime? from}) {
    final marker = dateOnly(from ?? DateTime.now());
    return (update(recurrenceRules)..where((r) => r.id.equals(id))).write(
      RecurrenceRulesCompanion(
        active: const Value(true),
        lastMaterialized: Value(marker),
      ),
    );
  }

  /// Edits an existing rule. `type` is deliberately not editable here -- it
  /// would misrepresent transactions already generated under the old type, so
  /// switching type means pausing this rule and creating a new one.
  ///
  /// Pass [resetMarkerToToday] when the caller determines the schedule itself
  /// changed (frequency/interval/startDate): this mirrors [reactivate]'s
  /// philosophy of never backfilling under a shape the rule didn't have yet.
  /// Leave it false when only cosmetic/amount fields changed, so existing
  /// catch-up progress is preserved.
  Future<void> editRule({
    required int id,
    String? title,
    double? amount,
    int? categoryId,
    Frequency? frequency,
    int? interval,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    String? note,
    bool resetMarkerToToday = false,
  }) {
    return (update(recurrenceRules)..where((r) => r.id.equals(id))).write(
      RecurrenceRulesCompanion(
        title: title != null ? Value(title) : const Value.absent(),
        amount: amount != null ? Value(amount) : const Value.absent(),
        categoryId:
            categoryId != null ? Value(categoryId) : const Value.absent(),
        frequency: frequency != null ? Value(frequency) : const Value.absent(),
        interval: interval != null ? Value(interval) : const Value.absent(),
        startDate:
            startDate != null ? Value(startDate) : const Value.absent(),
        endDate: clearEndDate
            ? const Value(null)
            : (endDate != null ? Value(endDate) : const Value.absent()),
        note: note != null ? Value(note) : const Value.absent(),
        lastMaterialized: resetMarkerToToday
            ? Value(dateOnly(DateTime.now()))
            : const Value.absent(),
      ),
    );
  }

  Future<void> deleteById(int id) {
    return (delete(recurrenceRules)..where((r) => r.id.equals(id))).go();
  }

  /// Wipes all recurrence rules -- used only by the dev data tools.
  Future<void> clearAll() => delete(recurrenceRules).go();
}

@DriftAccessor(tables: [SavingsGoals, SavingsContributions])
class SavingsDao extends DatabaseAccessor<AppDatabase> with _$SavingsDaoMixin {
  SavingsDao(super.db);

  Stream<List<SavingsGoal>> watchGoals() {
    return (select(savingsGoals)..where((g) => g.archived.equals(false)))
        .watch();
  }

  /// Wipes all goals and contributions -- used only by the dev data tools.
  Future<void> clearAll() async {
    await delete(savingsContributions).go();
    await delete(savingsGoals).go();
  }

  Future<int> addGoal({
    required String name,
    required double targetAmount,
    DateTime? targetDate,
  }) {
    return into(savingsGoals).insert(SavingsGoalsCompanion.insert(
      name: name,
      targetAmount: targetAmount,
      targetDate: Value(targetDate),
    ));
  }

  Future<int> addContribution({
    required int goalId,
    required double amount,
    required DateTime date,
    String? note,
  }) {
    return into(savingsContributions)
        .insert(SavingsContributionsCompanion.insert(
      goalId: goalId,
      amount: amount,
      date: date,
      note: Value(note),
    ));
  }

  Stream<List<SavingsContribution>> watchContributions(int goalId) {
    return (select(savingsContributions)
          ..where((c) => c.goalId.equals(goalId))
          ..orderBy([(c) => OrderingTerm.desc(c.date)]))
        .watch();
  }

  /// Every contribution across all goals, newest first. The home dashboard
  /// derives both the total saved (running balance) and this month's saved
  /// amount from this one stream, in Dart -- consistent with how the app
  /// treats dates elsewhere.
  Stream<List<SavingsContribution>> watchAllContributions() {
    return (select(savingsContributions)
          ..orderBy([(c) => OrderingTerm.desc(c.date)]))
        .watch();
  }

  /// Current balance is the SUM of the ledger — never a stored, mutable field,
  /// so it can't drift out of sync.
  Stream<double> watchTotal(int goalId) {
    final total = savingsContributions.amount.sum();
    final q = selectOnly(savingsContributions)
      ..addColumns([total])
      ..where(savingsContributions.goalId.equals(goalId));
    return q.watchSingle().map((row) => row.read(total) ?? 0.0);
  }
}

@DriftDatabase(
  tables: [
    Categories,
    Transactions,
    RecurrenceRules,
    SavingsGoals,
    SavingsContributions,
  ],
  daos: [CategoryDao, TransactionDao, RecurrenceDao, SavingsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedDefaultCategories();
          await _seedDefaultSubcategories();
        },
        onUpgrade: (m, from, to) async {
          // v2 introduced sub-categories (parentId) and the essentials/luxuries
          // tag (kind). Existing rows become top-level essentials until the
          // user re-tags them.
          if (from < 2) {
            await m.addColumn(categories, categories.parentId);
            await m.addColumn(categories, categories.kind);
          }
          // v3 seeds a starter set of sub-categories under the default
          // categories (matched by icon), skipping any parent that already has
          // children so it never disturbs a user's own edits.
          if (from < 3) {
            await _seedDefaultSubcategories();
          }
        },
      );

  Future<void> _seedDefaultCategories() async {
    await batch((b) {
      b.insertAll(categories, _defaultCategories);
    });
  }

  /// Adds the default sub-categories under each matching top-level default
  /// category. Idempotent: a parent that already has any sub-category is left
  /// untouched. Sub-categories inherit their parent's colour and type.
  Future<void> _seedDefaultSubcategories() async {
    final tops =
        await (select(categories)..where((c) => c.parentId.isNull())).get();
    for (final entry in _defaultSubcategories.entries) {
      Category? parent;
      for (final t in tops) {
        if (t.iconKey == entry.key && !t.archived) {
          parent = t;
          break;
        }
      }
      if (parent == null) continue;
      final p = parent;
      final existing =
          await (select(categories)..where((c) => c.parentId.equals(p.id)))
              .get();
      if (existing.isNotEmpty) continue;
      var order = 0;
      await batch((b) {
        for (final sub in entry.value) {
          b.insert(
            categories,
            CategoriesCompanion.insert(
              name: sub.name,
              iconKey: sub.icon,
              colorValue: p.colorValue,
              type: p.type,
              parentId: Value(p.id),
              kind: Value(sub.kind),
              sortOrder: Value(order++),
            ),
          );
        }
      });
    }
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'floos.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

/// Seeded once on first launch. Categories are user-editable after that — this is
/// just a sane starting set so the app isn't empty and isn't limited to five icons.
const _defaultCategories = <CategoriesCompanion>[
  // Expenses (kind: necessities vs discretionary as a sensible starting guess)
  CategoriesCompanion(name: Value('طعام'), iconKey: Value('food'), colorValue: Value(0xFFEF5350), type: Value(TxnType.expense), kind: Value(CategoryKind.essential), sortOrder: Value(0)),
  CategoriesCompanion(name: Value('مواصلات'), iconKey: Value('transport'), colorValue: Value(0xFF42A5F5), type: Value(TxnType.expense), kind: Value(CategoryKind.essential), sortOrder: Value(1)),
  CategoriesCompanion(name: Value('تسوق'), iconKey: Value('shopping'), colorValue: Value(0xFFAB47BC), type: Value(TxnType.expense), kind: Value(CategoryKind.luxury), sortOrder: Value(2)),
  CategoriesCompanion(name: Value('فواتير'), iconKey: Value('bills'), colorValue: Value(0xFFFFCA28), type: Value(TxnType.expense), kind: Value(CategoryKind.essential), sortOrder: Value(3)),
  CategoriesCompanion(name: Value('صحة'), iconKey: Value('health'), colorValue: Value(0xFF26A69A), type: Value(TxnType.expense), kind: Value(CategoryKind.essential), sortOrder: Value(4)),
  CategoriesCompanion(name: Value('ترفيه'), iconKey: Value('entertainment'), colorValue: Value(0xFFEC407A), type: Value(TxnType.expense), kind: Value(CategoryKind.luxury), sortOrder: Value(5)),
  CategoriesCompanion(name: Value('منزل'), iconKey: Value('home'), colorValue: Value(0xFF8D6E63), type: Value(TxnType.expense), kind: Value(CategoryKind.essential), sortOrder: Value(6)),
  CategoriesCompanion(name: Value('أخرى'), iconKey: Value('other'), colorValue: Value(0xFF78909C), type: Value(TxnType.expense), kind: Value(CategoryKind.essential), sortOrder: Value(7)),
  // Income (kind is irrelevant for income, defaults to essential)
  CategoriesCompanion(name: Value('راتب'), iconKey: Value('salary'), colorValue: Value(0xFF66BB6A), type: Value(TxnType.income), sortOrder: Value(8)),
  CategoriesCompanion(name: Value('دخل إضافي'), iconKey: Value('extra_income'), colorValue: Value(0xFF9CCC65), type: Value(TxnType.income), sortOrder: Value(9)),
  CategoriesCompanion(name: Value('استثمار'), iconKey: Value('investment'), colorValue: Value(0xFF26C6DA), type: Value(TxnType.income), sortOrder: Value(10)),
];

/// Default sub-categories, keyed by the parent's icon so they attach to the
/// right default category. Seeded under expense categories only (income rarely
/// needs finer buckets). Each inherits its parent's colour + type.
typedef _Sub = ({String name, String icon, CategoryKind kind});
const _defaultSubcategories = <String, List<_Sub>>{
  'food': [
    (name: 'مطاعم', icon: 'fastfood', kind: CategoryKind.luxury),
    (name: 'بقالة', icon: 'local_grocery_store', kind: CategoryKind.essential),
    (name: 'مقاهي', icon: 'local_cafe', kind: CategoryKind.luxury),
    (name: 'توصيل طعام', icon: 'moped', kind: CategoryKind.luxury),
  ],
  'transport': [
    (name: 'وقود', icon: 'local_gas_station', kind: CategoryKind.essential),
    (name: 'تطبيقات النقل', icon: 'local_taxi', kind: CategoryKind.essential),
    (name: 'صيانة', icon: 'directions_car', kind: CategoryKind.essential),
    (name: 'مواقف', icon: 'local_parking', kind: CategoryKind.essential),
  ],
  'shopping': [
    (name: 'ملابس', icon: 'checkroom', kind: CategoryKind.luxury),
    (name: 'إلكترونيات', icon: 'devices', kind: CategoryKind.luxury),
    (name: 'هدايا', icon: 'card_giftcard', kind: CategoryKind.luxury),
  ],
  'bills': [
    (name: 'كهرباء', icon: 'bolt', kind: CategoryKind.essential),
    (name: 'ماء', icon: 'water_drop', kind: CategoryKind.essential),
    (name: 'إنترنت', icon: 'wifi', kind: CategoryKind.essential),
    (name: 'جوال', icon: 'phone_iphone', kind: CategoryKind.essential),
  ],
  'health': [
    (name: 'أدوية', icon: 'medication', kind: CategoryKind.essential),
    (name: 'عيادات', icon: 'local_hospital', kind: CategoryKind.essential),
    (name: 'لياقة', icon: 'fitness_center', kind: CategoryKind.luxury),
  ],
  'entertainment': [
    (name: 'اشتراكات', icon: 'subscriptions', kind: CategoryKind.luxury),
    (name: 'ألعاب', icon: 'sports_esports', kind: CategoryKind.luxury),
    (name: 'سينما', icon: 'theaters', kind: CategoryKind.luxury),
    (name: 'مطاعم وخروج', icon: 'nightlife', kind: CategoryKind.luxury),
  ],
  'home': [
    (name: 'أثاث', icon: 'chair', kind: CategoryKind.essential),
    (name: 'أدوات المطبخ', icon: 'kitchen', kind: CategoryKind.essential),
    (name: 'تنظيف', icon: 'cleaning_services', kind: CategoryKind.essential),
  ],
  'other': [
    (name: 'سجائر', icon: 'cigarette', kind: CategoryKind.luxury),
    (name: 'رسوم', icon: 'attach_money', kind: CategoryKind.essential),
  ],
};
