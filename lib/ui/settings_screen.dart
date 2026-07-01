import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_settings.dart';
import 'theme/tokens.dart';

/// Appearance settings: light/dark/system theme mode and the accent color.
/// Both are persisted by [AppSettings] and applied to the whole app instantly.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(
            'المظهر',
            style: TextStyle(
              fontSize: AppTextSizes.label,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
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
          Text(
            'لون التمييز',
            style: TextStyle(
              fontSize: AppTextSizes.label,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
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
        ],
      ),
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
