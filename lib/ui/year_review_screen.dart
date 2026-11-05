import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_settings.dart';
import '../data/database.dart';
import '../data/enums.dart';
import '../domain/calendar_format.dart';
import '../domain/period_summary.dart';
import '../domain/year_review.dart';
import 'theme/tokens.dart';

/// The last twelve salary cycles side by side: which one was expensive,
/// whether saving is trending up, and where the money went.
class YearReviewScreen extends StatelessWidget {
  const YearReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final hijri = context.watch<AppSettings>().useHijri;
    final money = NumberFormat('#,##0');

    return Scaffold(
      appBar: AppBar(title: const Text('آخر ١٢ دورة')),
      body: StreamBuilder<List<TxnRow>>(
        stream: db.transactionDao.watchAllWithCategory(),
        builder: (context, txnSnap) {
          return StreamBuilder<List<SavingsContribution>>(
            stream: db.savingsDao.watchAllContributions(),
            builder: (context, savSnap) {
              return StreamBuilder<List<RecurrenceRule>>(
                stream: db.recurrenceDao.watchByType(TxnType.income),
                builder: (context, rulesSnap) {
                  return StreamBuilder<List<Category>>(
                    stream: db.categoryDao.watchAll(),
                    builder: (context, catSnap) {
                      if (!txnSnap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final names = {
                        for (final c in catSnap.data ?? const <Category>[])
                          c.id: c.name
                      };
                      final review = yearReview(
                        rows: txnSnap.data!,
                        contributions:
                            savSnap.data ?? const <SavingsContribution>[],
                        incomeRules: rulesSnap.data ?? const <RecurrenceRule>[],
                        now: DateTime.now(),
                      );
                      if (review.cycles.isEmpty) {
                        return const Center(child: Text('لا توجد عمليات بعد'));
                      }
                      return _Body(
                          review: review,
                          names: names,
                          money: money,
                          hijri: hijri);
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final YearReview review;
  final Map<int, String> names;
  final NumberFormat money;
  final bool hijri;
  const _Body({
    required this.review,
    required this.names,
    required this.money,
    required this.hijri,
  });

  String _rate(double? r) => r == null ? '—' : '${(r * 100).round()}%';

  String _label(CycleSummary c) => cycleLabelFor(c.period, hijri: hijri);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = review;
    // Every bar is drawn on one scale, so cycles compare at a glance.
    final scale = r.cycles.fold<double>(1, (m, c) {
      final out = c.spent + (c.saved > 0 ? c.saved : 0);
      final top = c.income > out ? c.income : out;
      return top > m ? top : m;
    });
    final spentTotal = r.committed + r.discretionary;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _Card(children: [
          if (r.cycles.length < reviewCycles)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text('${r.cycles.length} دورة حتى الآن',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
          _Line('الدخل', '${money.format(r.income)} ⃁'),
          _Line('المصروف', '${money.format(r.spent)} ⃁'),
          _Line('الادخار', '${money.format(r.saved)} ⃁'),
          _Line('نسبة الادخار', _rate(r.savingsRate), bold: true),
        ]),
        const SizedBox(height: AppSpacing.md),
        _Card(title: 'كل دورة', children: [
          for (final c in r.cycles)
            _CycleBar(
              label: r.isCurrent(c) ? '${_label(c)} (جارية)' : _label(c),
              cycle: c,
              scale: scale,
              money: money,
              rate: _rate(c.savingsRate),
            ),
          Row(
            children: [
              _Legend(color: scheme.primary, text: 'مصروف'),
              const SizedBox(width: AppSpacing.md),
              const _Legend(color: AppColors.income, text: 'ادخار'),
            ],
          ),
        ]),
        if (r.best != null) ...[
          const SizedBox(height: AppSpacing.md),
          _Card(title: 'أفضل وأسوأ دورة (المكتملة)', children: [
            _Line('الأفضل: ${_label(r.best!)}', _rate(r.best!.savingsRate)),
            if (r.worst != null && r.worst != r.best)
              _Line('الأسوأ: ${_label(r.worst!)}', _rate(r.worst!.savingsRate)),
          ]),
        ],
        if (r.topCategories.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _Card(title: 'أين ذهب المال', children: [
            for (final s in r.topCategories)
              _Line(
                names[s.categoryId] ?? '—',
                '${money.format(s.total)} ⃁'
                '  ·  ${spentTotal > 0 ? (s.total / spentTotal * 100).round() : 0}%',
              ),
          ]),
        ],
        const SizedBox(height: AppSpacing.md),
        _Card(title: 'التزامات مقابل اختيارية', children: [
          _Line('التزامات متكررة', '${money.format(r.committed)} ⃁'),
          _Line('اختيارية', '${money.format(r.discretionary)} ⃁'),
        ]),
      ],
    );
  }
}

class _CycleBar extends StatelessWidget {
  final String label;
  final CycleSummary cycle;
  final double scale;
  final NumberFormat money;
  final String rate;
  const _CycleBar({
    required this.label,
    required this.cycle,
    required this.scale,
    required this.money,
    required this.rate,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Shares of the common scale; a net-negative month (refunds outweighing
    // spending) or a net withdrawal draws as nothing rather than backwards.
    double share(double v) => v <= 0 ? 0 : (v / scale).clamp(0.0, 1.0);
    final spent = share(cycle.spent);
    final saved = share(cycle.saved);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Text(
                '${money.format(cycle.spent)} ⃁ · $rate',
                style: TextStyle(
                    fontSize: AppTextSizes.label,
                    color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 10,
              child: LayoutBuilder(
                builder: (context, box) => Stack(
                  children: [
                    Container(color: scheme.surfaceContainerHighest),
                    Row(
                      children: [
                        Container(
                            width: box.maxWidth * spent, color: scheme.primary),
                        Container(
                            width: box.maxWidth *
                                (saved < 1 - spent ? saved : 1 - spent),
                            color: AppColors.income),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const _Card({this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(title!,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: AppSpacing.md),
            ],
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _Line(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w700 : null);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
              child:
                  Text(label, style: style, overflow: TextOverflow.ellipsis)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String text;
  const _Legend({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, color: color),
        const SizedBox(width: AppSpacing.xs),
        Text(text, style: const TextStyle(fontSize: AppTextSizes.label)),
      ],
    );
  }
}
