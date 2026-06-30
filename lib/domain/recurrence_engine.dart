import '../data/database.dart';
import 'recurrence_math.dart';

/// Materializes due recurring transactions by evaluating each rule lazily.
/// Call it on app start and on resume. Safe to call repeatedly.
///
/// This is what replaces the original's background-task approach (which iOS and
/// Android silently kill, causing the "sometimes it adds, sometimes it doesn't"
/// behaviour and the manual-refresh requirement).
class RecurrenceEngine {
  final AppDatabase db;
  RecurrenceEngine(this.db);

  // Shared across instances so a start-up call and a resume call can't overlap
  // and double-insert.
  static bool _running = false;

  /// Generates any transactions due up to [asOf] (default: today) for every
  /// active rule, then advances each rule's marker. Returns how many were
  /// created. Wrapped in a DB transaction so a failure part-way commits nothing
  /// and the next launch simply retries.
  Future<int> catchUp({DateTime? asOf}) async {
    if (_running) return 0;
    _running = true;
    try {
      final until = dateOnly(asOf ?? DateTime.now());
      var created = 0;
      await db.transaction(() async {
        final rules = await db.recurrenceDao.activeRules();
        for (final rule in rules) {
          final occs = occurrencesBetween(
            startDate: rule.startDate,
            frequency: rule.frequency,
            interval: rule.interval,
            endDate: rule.endDate,
            lastMaterialized: rule.lastMaterialized,
            until: until,
          );
          if (occs.isEmpty) continue;
          for (final date in occs) {
            await db.transactionDao.insertGenerated(rule, date);
          }
          created += occs.length;
          await db.recurrenceDao.setLastMaterialized(rule.id, occs.last);
        }
      });
      return created;
    } finally {
      _running = false;
    }
  }
}
