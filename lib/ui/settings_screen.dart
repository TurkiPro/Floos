import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_settings.dart';
import '../data/database.dart';
import '../data/dev_seed.dart';
import '../data/export.dart';
import 'category_editor_screen.dart';
import 'months_screen.dart';
import 'recurring_screen.dart';
import 'statistics_screen.dart';
import 'theme/tokens.dart';

/// Appearance settings (theme mode + accent) plus the app's secondary
/// destinations (obligations, months, statistics, categories, export), all
/// gathered here now that the home screen keeps only the settings entry point.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(
          text,
          style: TextStyle(
            fontSize: AppTextSizes.label,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );

  Widget _navTile(BuildContext context,
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: const Icon(Icons.chevron_left),
        onTap: onTap,
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final db = context.read<AppDatabase>();

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _sectionLabel(context, 'الإدارة'),
          _navTile(context,
              icon: Icons.insights_outlined,
              label: 'الإحصائيات',
              onTap: () => _push(context, const StatisticsScreen())),
          _navTile(context,
              icon: Icons.event_repeat_outlined,
              label: 'الالتزامات الشهرية',
              onTap: () => _push(context, const ObligationsScreen())),
          _navTile(context,
              icon: Icons.calendar_month_outlined,
              label: 'الأشهر',
              onTap: () => _push(context, const MonthsScreen())),
          _navTile(context,
              icon: Icons.category_outlined,
              label: 'الفئات',
              onTap: () => _push(context, const CategoryEditorScreen())),
          _navTile(context,
              icon: Icons.file_download_outlined,
              label: 'تصدير CSV',
              onTap: () async {
                final path = await exportTransactionsCsvToFile(db);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تم التصدير: $path')),
                  );
                }
              }),
          const SizedBox(height: AppSpacing.lg),
          _sectionLabel(context, 'المظهر'),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.light,
                label: Text('فاتح'),
                icon: Icon(Icons.light_mode_outlined),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text('داكن'),
                icon: Icon(Icons.dark_mode_outlined),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                label: Text('تلقائي'),
                icon: Icon(Icons.brightness_auto_outlined),
              ),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (s) => settings.setThemeMode(s.first),
          ),
          const SizedBox(height: AppSpacing.xl),
          _sectionLabel(context, 'لون التمييز'),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.lg,
            children: [
              for (final accent in AppAccent.values)
                _AccentSwatch(
                  accent: accent,
                  selected: accent == settings.accent,
                  onTap: () => settings.setAccent(accent),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          _sectionLabel(context, 'أدوات تجريبية'),
          _navTile(context,
              icon: Icons.auto_awesome_outlined,
              label: 'تعبئة ببيانات تجريبية',
              onTap: () async {
                await seedDummyData(db);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('تمت تعبئة بيانات آخر ٦ أشهر')),
                  );
                }
              }),
          _navTile(context,
              icon: Icons.delete_outline,
              label: 'حذف كل البيانات',
              onTap: () => _confirmClear(context, db)),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, AppDatabase db) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف كل البيانات؟'),
        content: const Text(
            'سيتم حذف كل الحركات والأهداف والقواعد المتكررة. لا يمكن التراجع.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await db.transactionDao.clearAll();
      await db.savingsDao.clearAll();
      await db.recurrenceDao.clearAll();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف كل البيانات')),
        );
      }
    }
  }
}

class _AccentSwatch extends StatelessWidget {
  final AppAccent accent;
  final bool selected;
  final VoidCallback onTap;
  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: accent.primary,
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(color: scheme.onSurface, width: 3)
                  : null,
            ),
            child: selected
                ? Icon(Icons.check, color: accent.onPrimary)
                : null,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(accent.label, style: const TextStyle(fontSize: AppTextSizes.label)),
        ],
      ),
    );
  }
}
