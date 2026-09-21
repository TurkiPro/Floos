import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_settings.dart';
import '../data/database.dart';
import '../domain/bank_sms.dart';
import '../services/alerts_coordinator.dart';
import 'import_review_screen.dart';
import 'theme/tokens.dart';
import 'widgets/amount_input.dart';

/// Import a batch of bank notification messages by pasting them.
///
/// This is the whole feature's entry point, reached from Settings. Reading SMS
/// directly is impossible on iOS and restricted on Android, and OCR of
/// screenshots would need a model download — the app's first network call.
/// Pasting text needs no permission, no native code and no network, which is
/// the only option compatible with the app's promises.
///
/// The page also lists past imports, because a batch written from
/// heuristically parsed text has to be takeable-back in one action.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _controller = TextEditingController();
  List<BankMessage> _parsed = const [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_reparse);
  }

  @override
  void dispose() {
    _controller.removeListener(_reparse);
    _controller.dispose();
    super.dispose();
  }

  void _reparse() {
    final parsed = parseBankSms(_controller.text);
    setState(() => _parsed = parsed);
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الحافظة فارغة')),
      );
      return;
    }
    _controller.text = text;
  }

  Future<void> _continue() async {
    final db = context.read<AppDatabase>();
    final saved = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => ImportReviewScreen(db: db, drafts: _parsed),
      ),
    );
    if (!mounted || saved == null) return;
    _controller.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم حفظ $saved عملية')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final usable = _parsed.where((m) => m.isUsable).length;

    return Scaffold(
      appBar: AppBar(title: const Text('استيراد من رسائل البنك')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const _HowTo(),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            maxLines: 8,
            minLines: 5,
            decoration: const InputDecoration(
              hintText: 'الصق رسائل البنك هنا…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste, size: 18),
                  label: const Text('لصق من الحافظة'),
                ),
              ),
              if (_controller.text.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  onPressed: _controller.clear,
                  icon: const Icon(Icons.close),
                  tooltip: 'مسح',
                ),
              ],
            ],
          ),
          if (_parsed.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              usable == _parsed.length
                  ? 'تم العثور على ${_parsed.length} عملية'
                  : 'تم العثور على ${_parsed.length} رسالة — '
                      '$usable منها مقروءة',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: _parsed.isEmpty ? null : _continue,
            child: const Text('متابعة'),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'عمليات الاستيراد السابقة',
            style: TextStyle(
              fontSize: AppTextSizes.label,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _PastImports(db: db),
        ],
      ),
    );
  }
}

class _HowTo extends StatelessWidget {
  const _HowTo();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Text(
        // Multi-select in the Messages app offers Forward, not Copy — so the
        // path that actually works is worth spelling out.
        'من تطبيق الرسائل: اختر الرسائل ← إعادة توجيه ← حدّد النص كاملًا '
        'وانسخه، ثم الصقه هنا. تُقرأ المبالغ والتواريخ تلقائيًا، ولا يُحفظ '
        'شيء قبل مراجعتك.',
        style: TextStyle(
          fontSize: AppTextSizes.label,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Past imports, newest first. Only the most recent one offers undo: rows from
/// an older batch may have been edited or deleted since, and quietly removing
/// something the user has changed would be worse than making them delete it by
/// hand.
class _PastImports extends StatelessWidget {
  final AppDatabase db;
  const _PastImports({required this.db});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ImportBatch>>(
      stream: db.importBatchDao.watchRecent(),
      builder: (context, snap) {
        final batches = snap.data ?? const <ImportBatch>[];
        if (batches.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text('لا يوجد استيراد سابق'),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < batches.length; i++)
              _BatchTile(
                db: db,
                batch: batches[i],
                canUndo: i == 0,
              ),
          ],
        );
      },
    );
  }
}

class _BatchTile extends StatelessWidget {
  final AppDatabase db;
  final ImportBatch batch;
  final bool canUndo;
  const _BatchTile({
    required this.db,
    required this.batch,
    required this.canUndo,
  });

  Future<void> _undo(BuildContext context) async {
    final counts = await db.importBatchDao.countsFor(batch.id);
    if (!context.mounted) return;

    final parts = <String>[
      if (counts.txns > 0) '${counts.txns} عملية',
      if (counts.contributions > 0) '${counts.contributions} إيداع ادخار',
    ];
    final what = parts.isEmpty ? 'لا شيء' : parts.join(' و ');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('التراجع عن الاستيراد'),
        content: Text(
          'سيُحذف $what.\n\n'
          'كما ستُنسى الجهات التي تعرّف عليها هذا الاستيراد لأول مرة، '
          'وسيسألك التطبيق عنها من جديد في المرة القادمة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('تراجع'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await db.importBatchDao.undo(batch.id);
    if (!context.mounted) return;
    // The balance, the weekly badge and every alert move with the ledger.
    refreshAlerts(db, context.read<AppSettings>());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم التراجع عن الاستيراد')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = StringBuffer('${batch.rowCount} عملية');
    if (batch.ignoredCount > 0) {
      subtitle.write(' — ${batch.ignoredCount} متجاهلة');
    }
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        title: Text(DateFormat('yyyy-MM-dd  HH:mm').format(batch.importedAt)),
        subtitle: Text(subtitle.toString()),
        trailing: canUndo
            ? TextButton(
                onPressed: () => _undo(context),
                child: const Text('تراجع'),
              )
            : Text(
                '${groupedAmount(batch.totalAmount)} ⃁',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
      ),
    );
  }
}
