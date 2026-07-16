import '../data/database.dart';
import '../data/enums.dart';
import 'budget_advisor.dart' show previousCycles;
import 'category_breakdown.dart';

/// Whether a category's spending this cycle is running above, below, or near
/// the user's own recent norm.
enum TrendDirection { up, down, steady }

class CategoryTrend {
  final TrendDirection direction;

  /// Percent change vs the norm (+ above, − below). Zero when there's no norm
  /// to compare against yet.
  final double pctChange;
  const CategoryTrend(this.direction, this.pctChange);

  static const none = CategoryTrend(TrendDirection.steady, 0);
}

// Above/below this fraction of the norm counts as a real move, not noise.
const _trendBand = 0.15;

double _median(List<double> xs) {
  if (xs.isEmpty) return 0;
  final s = [...xs]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

/// For each top category, how this cycle's spend compares to the median of the
/// previous [maxCycles] completed cycles (the user's own norm). Only cycles
/// that actually contain spending count, so early empty months don't drag a
/// norm to zero. Categories with no prior norm come back [CategoryTrend.none].
Map<int, CategoryTrend> categoryTrends({
  required List<TxnRow> rows,
  required List<RecurrenceRule> incomeRules,
  required DateTime now,
  required Map<int, double> thisCycleTotals,
  int maxCycles = 3,
}) {
  final cycles = previousCycles(incomeRules, now, maxCycles);
  // cycleIndex -> topCategoryId -> total
  final byCycle = [for (var _ in cycles) <int, double>{}];
  for (final r in rows) {
    if (r.txn.type != TxnType.expense) continue;
    for (var i = 0; i < cycles.length; i++) {
      if (cycles[i].contains(r.txn.date)) {
        final topId = r.category.parentId ?? r.category.id;
        byCycle[i][topId] = (byCycle[i][topId] ?? 0) + r.txn.amount;
        break;
      }
    }
  }
  final activeCycles = [
    for (var i = 0; i < cycles.length; i++)
      if (byCycle[i].isNotEmpty) i,
  ];

  final out = <int, CategoryTrend>{};
  thisCycleTotals.forEach((topId, thisTotal) {
    final perCycle = [for (final i in activeCycles) byCycle[i][topId] ?? 0.0];
    final norm = _median(perCycle);
    if (norm <= 0) {
      out[topId] = CategoryTrend.none;
      return;
    }
    final pct = (thisTotal - norm) / norm * 100;
    final dir = pct > _trendBand * 100
        ? TrendDirection.up
        : (pct < -_trendBand * 100
            ? TrendDirection.down
            : TrendDirection.steady);
    out[topId] = CategoryTrend(dir, pct);
  });
  return out;
}

/// A category worth trimming, with a short human reason.
class CutSuggestion {
  final int categoryId;
  final String reason;
  final double score;
  const CutSuggestion({
    required this.categoryId,
    required this.reason,
    required this.score,
  });
}

/// Ranks where cutting spend would help most: discretionary (كماليات) weighs
/// far heavier than essentials (you can trim wants, not rent), a category that's
/// *rising* vs your norm weighs up, one that's falling weighs down, and a bigger
/// share of the period's spend weighs up. Returns the top few real candidates
/// (essentials that are steady/falling are effectively filtered out).
List<CutSuggestion> cutSuggestions({
  required List<CategoryStat> breakdown,
  required Map<int, Category> byId,
  required Map<int, CategoryTrend> trends,
  required double periodTotal,
  int limit = 3,
}) {
  final out = <CutSuggestion>[];
  for (final stat in breakdown) {
    final cat = byId[stat.categoryId];
    if (cat == null) continue;
    final share = periodTotal > 0 ? stat.total / periodTotal : 0.0;
    final luxury = cat.kind == CategoryKind.luxury;
    final trend = trends[stat.categoryId] ?? CategoryTrend.none;

    var score = share * (luxury ? 2.0 : 0.5);
    if (trend.direction == TrendDirection.up) {
      score *= 1.6;
    } else if (trend.direction == TrendDirection.down) {
      score *= 0.7;
    }
    // Nothing worth flagging: a small, steady essential.
    if (score < 0.05) continue;

    final reasons = <String>[
      if (luxury) 'كماليات',
      if (trend.direction == TrendDirection.up)
        'ترتفع ${trend.pctChange.abs().toStringAsFixed(0)}٪ عن معدلك',
      '${(share * 100).toStringAsFixed(0)}٪ من إنفاقك',
    ];
    out.add(CutSuggestion(
      categoryId: stat.categoryId,
      reason: reasons.join('  •  '),
      score: score,
    ));
  }
  out.sort((a, b) => b.score.compareTo(a.score));
  return out.take(limit).toList();
}
