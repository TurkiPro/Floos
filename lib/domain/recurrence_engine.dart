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

          // A one-shot override adjusts a single occurrence's date. ovSched is
          // the scheduled occurrence it replaces; ovDate is the date to use.
          final ovSched = rule.nextOverrideScheduled == null
              ? null
              : dateOnly(rule.nextOverrideScheduled!);
          final ovDate = rule.nextOverrideDate == null
              ? null
              : dateOnly(rule.nextOverrideDate!);
          final hasOverride = ovSched != null && ovDate != null;
          var consumed = false;

          for (final date in occs) {
            if (hasOverride && date == ovSched) {
              // The overridden occurrence has come up in the schedule. Create it
              // at its override date only if that date has arrived; if it's a
              // delay into the future, skip for now (the marker still advances
              // below, and the override fires on a later run once ovDate lands).
              if (!ovDate.isAfter(until)) {
                await db.transactionDao.insertGenerated(rule, ovDate);
                created++;
                consumed = true;
              }
            } else {
              await db.transactionDao.insertGenerated(rule, date);
              created++;
            }
          }

          DateTime? newMarker =
              occs.isEmpty ? rule.lastMaterialized : occs.last;

          // An override that's due now but whose scheduled slot isn't in this
          // window: an early payday (scheduled still ahead) or a delayed one
          // finally arriving (scheduled already behind the marker).
          if (hasOverride && !consumed && !ovDate.isAfter(until)) {
            await db.transactionDao.insertGenerated(rule, ovDate);
            created++;
            consumed = true;
            // Push the marker to/at the overridden scheduled date so the normal
            // schedule can never recreate that occurrence.
            if (newMarker == null || ovSched.isAfter(newMarker)) {
              newMarker = ovSched;
            }
          }

          if (consumed) {
            await db.recurrenceDao.clearNextPaydayOverride(rule.id);
          }
          if (newMarker != null && newMarker != rule.lastMaterialized) {
            await db.recurrenceDao.setLastMaterialized(rule.id, newMarker);
          }
        }
      });
      return created;
    } finally {
      _running = false;
    }
  }
}
