import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_settings.dart';
import '../data/backup.dart';
import '../data/database.dart';
import '../data/dev_seed.dart';
import '../data/export.dart';
import '../data/pdf_export.dart';
import '../services/alerts_coordinator.dart';
import '../services/app_lock_service.dart';
import '../services/notification_service.dart';
import 'budgets_screen.dart';
import 'category_editor_screen.dart';
import 'investments_screen.dart';
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

  /// iOS (and share_plus) rejects a share with a zero-rect origin — the
  /// `{{0,0},{0,0}} must be non-zero` crash. Anchor the sheet to the current
  /// view's frame so the popover has somewhere to point (harmless on iPhone,
  /// required on iPad).
  Rect _shareOrigin(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
    final size = MediaQuery.of(context).size;
    return Rect.fromLTWH(0, 0, size.width, size.height / 2);
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
              icon: Icons.account_balance_wallet_outlined,
              label: 'الميزانيات',
              onTap: () => _push(context, const BudgetsScreen())),
          _navTile(context,
              icon: Icons.trending_up,
              label: 'الاستثمارات',
              onTap: () => _push(context, const InvestmentsScreen())),
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
              label: 'تصدير العمليات',
              onTap: () => _export(context, db)),
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
          const SizedBox(height: AppSpacing.lg),
          _sectionLabel(context, 'الخط'),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final f in AppFont.values)
                ChoiceChip(
                  label: Text(f.label, style: TextStyle(fontFamily: f.family)),
                  selected: settings.fontChoice == f,
                  onSelected: (_) => settings.setFontChoice(f),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          _sectionLabel(context, 'لون التمييز'),
          const SizedBox(height: AppSpacing.sm),
          // Six equal Expanded slots keep every accent on a single row at any
          // phone width — the old Wrap of fixed 56px circles spilled onto a
          // second row on narrow screens.
          Row(
            children: [
              for (final accent in AppAccent.values)
                Expanded(
                  child: _AccentSwatch(
                    accent: accent,
                    selected: accent == settings.accent,
                    onTap: () => settings.setAccent(accent),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          _sectionLabel(context, 'التنبيهات'),
          Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_outlined),
                  title: const Text('تفعيل التنبيهات'),
                  subtitle: const Text('تذكيرك بتحديث مصاريفك'),
                  value: settings.notificationsEnabled,
                  onChanged: (v) async {
                    if (v) {
                      final granted =
                          await NotificationService.requestPermission();
                      if (!granted) {
                        // Leave the setting off — the OS will never deliver.
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'التنبيهات مرفوضة من النظام — فعّلها من إعدادات الجهاز.')),
                          );
                        }
                        return;
                      }
                    }
                    settings.setNotificationsEnabled(v);
                    await refreshAlerts(db, settings);
                  },
                ),
                if (settings.notificationsEnabled) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.repeat),
                    title: const Text('التكرار'),
                    trailing: DropdownButton<ReminderCadence>(
                      value: settings.reminderCadence,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final c in ReminderCadence.values)
                          DropdownMenuItem(value: c, child: Text(c.label)),
                      ],
                      onChanged: (c) async {
                        if (c == null) return;
                        settings.setReminderCadence(c);
                        await refreshAlerts(db, settings);
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.schedule),
                    title: const Text('وقت التذكير'),
                    trailing: Text(
                      settings.reminderTime.format(context),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: settings.reminderTime,
                      );
                      if (picked == null) return;
                      settings.setReminderTime(picked);
                      await refreshAlerts(db, settings);
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.calculate_outlined),
                    title: const Text('ميزانية الأسبوع جاهزة'),
                    value: settings.notifyWeeklyBudget,
                    onChanged: (v) async {
                      settings.setNotifyWeeklyBudget(v);
                      await refreshAlerts(db, settings);
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.insights_outlined),
                    title: const Text('تعال شوف إحصائياتك'),
                    value: settings.notifyStats,
                    onChanged: (v) async {
                      settings.setNotifyStats(v);
                      await refreshAlerts(db, settings);
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.payments_outlined),
                    title: const Text('يوم الراتب'),
                    value: settings.notifySalaryDay,
                    onChanged: (v) async {
                      settings.setNotifySalaryDay(v);
                      await refreshAlerts(db, settings);
                    },
                  ),
                ],
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.filter_1_outlined),
                  title: const Text('عرض ميزانية الأسبوع على أيقونة التطبيق'),
                  subtitle: const Text(
                      'بدلًا من عدد الإشعارات، يظهر المتبقي من ميزانية الأسبوع'),
                  value: settings.badgeWeeklyBudget,
                  onChanged: (v) async {
                    if (v) {
                      // iOS only shows an app-icon badge if notification
                      // authorization (incl. the badge option) was granted —
                      // request it here, since the user may want the badge
                      // without the reminder notifications.
                      final granted =
                          await NotificationService.requestPermission();
                      if (!granted) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'الشارة تحتاج إذن الإشعارات — فعّله من إعدادات الجهاز.')),
                          );
                        }
                        return;
                      }
                    }
                    settings.setBadgeWeeklyBudget(v);
                    await refreshAlerts(db, settings);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _sectionLabel(context, 'عام'),
          Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: const Text('التقويم'),
                  trailing: SegmentedButton<CalendarSystem>(
                    segments: [
                      for (final c in CalendarSystem.values)
                        ButtonSegment(value: c, label: Text(c.label)),
                    ],
                    selected: {settings.calendar},
                    onSelectionChanged: (s) => settings.setCalendar(s.first),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.speed_outlined),
                  title: const Text('حالة ميزانية الأسبوع في الرئيسية'),
                  subtitle: const Text(
                      'بطاقة تبيّن إن كنت ضمن ميزانية الأسبوع أو تجاوزتها'),
                  value: settings.showWeeklyStatusOnHome,
                  onChanged: settings.setShowWeeklyStatusOnHome,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.volume_up_outlined),
                  title: const Text('صوت عند إضافة عملية'),
                  value: settings.soundEnabled,
                  onChanged: settings.setSoundEnabled,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.fingerprint),
                  title: const Text('قفل التطبيق'),
                  subtitle: const Text('بصمة أو بصمة الوجه أو رمز الجهاز'),
                  value: settings.appLockEnabled,
                  onChanged: (v) async {
                    if (v) {
                      final available = await AppLockService.isAvailable();
                      if (!available) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'جهازك لا يدعم القفل — فعّل بصمة أو رمزًا أولًا.')),
                          );
                        }
                        return;
                      }
                      final ok = await AppLockService.authenticate();
                      if (!ok) return;
                    }
                    settings.setAppLockEnabled(v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _sectionLabel(context, 'البيانات'),
          _navTile(context,
              icon: Icons.backup_outlined,
              label: 'نسخة احتياطية',
              onTap: () => _backup(context, db)),
          _navTile(context,
              icon: Icons.restore_outlined,
              label: 'استعادة نسخة احتياطية',
              onTap: () => _restore(context, db)),
          // Deleting everything is a real user-facing feature, not a dev tool:
          // the published privacy policy promises exactly this control
          // ("الإعدادات ← حذف كل البيانات"), so it ships in release too.
          _navTile(context,
              icon: Icons.delete_outline,
              label: 'حذف كل البيانات',
              onTap: () => _confirmClear(context, db)),

          // The app mark doubles as a hidden developer unlock: tap it six times
          // to reveal the dev tools (test notification + demo-data seeding).
          // Those tools are destructive or for-testing, so they never sit in the
          // normal settings where a real user could hit them by accident.
          _DevFooter(db: db),
        ],
      ),
    );
  }

  /// Lets the user pick a format, then hands the file to the OS share sheet so
  /// they can save it anywhere (Files/iCloud/Drive) or send it to another app
  /// (WhatsApp, mail, …) — not silently dropped into an app-private directory.
  Future<void> _export(BuildContext context, AppDatabase db) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('CSV (جدول بيانات)'),
              subtitle: const Text('للتحليل في Excel أو Google Sheets'),
              onTap: () => Navigator.of(context).pop('csv'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF (كشف للطباعة أو المشاركة)'),
              onTap: () => Navigator.of(context).pop('pdf'),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final origin = _shareOrigin(context);
    try {
      final File file = choice == 'pdf'
          ? await writeTransactionsPdf(db)
          : File(await exportTransactionsCsvToFile(db));
      await Share.shareXFiles([XFile(file.path)], sharePositionOrigin: origin);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('تعذّر التصدير: $e')));
    }
  }

  Future<void> _backup(BuildContext context, AppDatabase db) async {
    final messenger = ScaffoldMessenger.of(context);
    final origin = _shareOrigin(context);
    try {
      final file = await writeBackupFile(db);
      await Share.shareXFiles([XFile(file.path)], sharePositionOrigin: origin);
    } catch (e) {
      // Surface the actual reason instead of a generic "couldn't" — this is
      // what turns a mystified user report into a fixable one.
      messenger.showSnackBar(
        SnackBar(content: Text('تعذّر إنشاء النسخة الاحتياطية: $e')),
      );
    }
  }

  Future<void> _restore(BuildContext context, AppDatabase db) async {
    final messenger = ScaffoldMessenger.of(context);
    // Accept .json by both extension and the iOS uniform type, so the user's
    // backup isn't greyed-out and unpickable in the Files sheet.
    const group = XTypeGroup(
      label: 'JSON',
      extensions: ['json'],
      uniformTypeIdentifiers: ['public.json'],
    );
    final XFile? picked;
    try {
      picked = await openFile(acceptedTypeGroups: const [group]);
    } catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text('تعذّر فتح منتقي الملفات: $e')));
      return;
    }
    if (picked == null) {
      messenger.showSnackBar(const SnackBar(content: Text('لم تختر أي ملف.')));
      return;
    }
    // readAsString on a security-scoped iOS file can throw; it used to run
    // outside any try, so a failure here silently did nothing.
    final String json;
    try {
      json = await picked.readAsString();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('تعذّر قراءة الملف: $e')));
      return;
    }
    if (!context.mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('استعادة النسخة الاحتياطية؟'),
        content: const Text(
            'سيتم حذف كل البيانات الحالية واستبدالها بمحتوى النسخة الاحتياطية. '
            'لا يمكن التراجع. (الملف غير مشفّر — احتفظ به في مكان آمن.)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('استعادة'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await restoreBackupJson(db, json);
      if (context.mounted) {
        await refreshAlerts(db, context.read<AppSettings>());
      }
      messenger.showSnackBar(const SnackBar(content: Text('تمت الاستعادة')));
    } on BackupFormatException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('ملف نسخة احتياطية غير صالح: ${e.message}')),
      );
    } catch (e) {
      // The restore runs in a transaction, so a mid-way failure rolls back.
      messenger.showSnackBar(
        SnackBar(content: Text('فشلت الاستعادة — لم تتغير بياناتك: $e')),
      );
    }
  }

  Future<void> _confirmClear(BuildContext context, AppDatabase db) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف كل البيانات؟'),
        content: const Text(
            'سيتم حذف كل العمليات والأهداف والقواعد المتكررة. لا يمكن التراجع.'),
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
      await db.transaction(() async {
        await db.transactionDao.clearAll();
        await db.savingsDao.clearAll();
        await db.recurrenceDao.clearAll();
        await db.budgetDao.clearAll();
        await db.investmentDao.clearAll();
      });
      if (!context.mounted) return;
      // The schedule/badge derived from the deleted data must not survive it.
      await refreshAlerts(db, context.read<AppSettings>());
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف كل البيانات')),
      );
    }
  }
}

/// The app mark at the foot of Settings, doubling as the classic
/// tap-six-times developer unlock. Once unlocked it reveals the dev-only tools
/// (send a test notification, seed demo data) that must never sit in the normal
/// settings — seeding in particular wipes the whole database.
class _DevFooter extends StatefulWidget {
  final AppDatabase db;
  const _DevFooter({required this.db});

  @override
  State<_DevFooter> createState() => _DevFooterState();
}

class _DevFooterState extends State<_DevFooter>
    with SingleTickerProviderStateMixin {
  static const _needed = 6;
  int _taps = 0;
  bool _unlocked = false;
  double _markScale = 1.0;
  String _version = '';

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _reveal =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = info.version);
    } catch (_) {}
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // Six taps toggle the dev tools — no on-screen countdown, just a bump on the
  // mark and an animated reveal (or hide on the next six taps).
  void _onMarkTap() {
    _taps++;
    if (_taps < _needed) return;
    _taps = 0;
    setState(() {
      _unlocked = !_unlocked;
      _markScale = 1.22;
    });
    _unlocked ? _c.forward() : _c.reverse();
    Future.delayed(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => _markScale = 1.0);
    });
  }

  Future<void> _sendTestNotification() async {
    await NotificationService.showTest();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('أقفل شاشة جوالك الآن — سيصلك تنبيه خلال ٦ ثوانٍ ✅')));
  }

  Future<void> _seed() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعبئة ببيانات تجريبية؟'),
        content: const Text(
            'سيتم حذف كل بياناتك الحالية واستبدالها ببيانات وهمية لآخر ٦ أشهر. لا يمكن التراجع.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('استبدال'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await seedDummyData(widget.db);
    if (!mounted) return;
    await refreshAlerts(widget.db, context.read<AppSettings>());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت تعبئة بيانات آخر ٦ أشهر')));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final faded = scheme.onSurfaceVariant.withValues(alpha: 0.6);
    return Column(
      children: [
        const SizedBox(height: AppSpacing.xl),
        GestureDetector(
          onTap: _onMarkTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: AnimatedScale(
              scale: _markScale,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.account_balance_wallet_rounded,
                      size: 18, color: faded),
                  const SizedBox(width: 6),
                  Text('فلوس',
                      style: TextStyle(
                          fontSize: AppTextSizes.row,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          color: faded)),
                  if (_version.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text('· $_version',
                        style: TextStyle(
                            fontSize: AppTextSizes.label, color: faded)),
                  ],
                ],
              ),
            ),
          ),
        ),
        // The dev tools reveal (or hide) with a coordinated size + fade.
        SizeTransition(
          sizeFactor: _reveal,
          child: FadeTransition(
            opacity: _reveal,
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text('أدوات المطوّر',
                        style: TextStyle(
                            fontSize: AppTextSizes.label,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant)),
                  ),
                ),
                Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Column(
                    children: [
                      ListTile(
                        leading:
                            const Icon(Icons.notifications_active_outlined),
                        title: const Text('إرسال تنبيه تجريبي'),
                        subtitle: const Text('تأكّد أن التنبيهات تصل جهازك'),
                        onTap: _sendTestNotification,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.auto_awesome_outlined),
                        title: const Text('تعبئة ببيانات تجريبية'),
                        subtitle:
                            const Text('يحذف بياناتك ويملؤها ببيانات وهمية'),
                        onTap: _seed,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
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
    // Opaque hit-testing so the whole (wider) slot around the circle taps,
    // not just the 44px disc itself.
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.primary,
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(color: scheme.onSurface, width: 3)
                  : null,
            ),
            child: selected
                ? Icon(Icons.check, size: 20, color: accent.onPrimary)
                : null,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            accent.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: AppTextSizes.label),
          ),
        ],
      ),
    );
  }
}
