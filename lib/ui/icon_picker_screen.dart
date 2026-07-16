import 'package:flutter/material.dart';

import 'icon_registry.dart';
import 'theme/tokens.dart';
import 'widgets/category_icon_tile.dart';
import 'widgets/color_swatch_picker.dart';

/// Full-screen icon + colour chooser opened from the category sheet. Gives the
/// browsing room a cramped inline grid never had: a live preview, colour
/// swatches, a search box over the built-in library, and an emoji field so the
/// user can turn ANY emoji into a category icon. Returns the chosen
/// `(iconKey, colour)` via [Navigator.pop]; the sheet keeps its keyboard hidden
/// while this is open because it's a separate route.
class IconPickerScreen extends StatefulWidget {
  final String initialIconKey;
  final Color initialColor;
  const IconPickerScreen({
    super.key,
    required this.initialIconKey,
    required this.initialColor,
  });

  @override
  State<IconPickerScreen> createState() => _IconPickerScreenState();
}

class _IconPickerScreenState extends State<IconPickerScreen> {
  late String _iconKey = widget.initialIconKey;
  late Color _color = widget.initialColor;
  final _searchCtrl = TextEditingController();
  final _emojiCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    _emojiCtrl.dispose();
    super.dispose();
  }

  /// Groups filtered by the search box: a match on the group's (Arabic) label
  /// keeps the whole group; otherwise only the keys whose name contains the
  /// query. Empty query returns everything.
  List<IconGroup> get _filteredGroups {
    final raw = _query.trim();
    if (raw.isEmpty) return iconGroups;
    final q = raw.toLowerCase();
    final result = <IconGroup>[];
    for (final g in iconGroups) {
      if (g.label.contains(raw)) {
        result.add(g);
        continue;
      }
      final keys = g.keys.where((k) => k.toLowerCase().contains(q)).toList();
      if (keys.isNotEmpty) result.add(IconGroup(g.label, keys));
    }
    return result;
  }

  void _useEmoji() {
    final chars = _emojiCtrl.text.trim().characters;
    if (chars.isEmpty) return;
    // Take a single user-perceived character, so a ZWJ emoji (👨‍👩‍👧) counts once.
    setState(() => _iconKey = emojiIconKey(chars.first));
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groups = _filteredGroups;
    return Scaffold(
      appBar: AppBar(
        title: const Text('اختر الأيقونة'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop((_iconKey, _color)),
            child: const Text('تم'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Live preview + colour swatches.
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CategoryIconTile(
                  iconKey: _iconKey,
                  colorValue: _color.toARGB32(),
                  size: 56,
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: ColorSwatchPicker(
                    selected: _color,
                    onChanged: (c) => setState(() => _color = c),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'ابحث عن أيقونة',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emojiCtrl,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.emoji_emotions_outlined),
                      hintText: 'أو استخدم إيموجي 🎁',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _useEmoji(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: _useEmoji,
                  child: const Text('استخدام'),
                ),
              ],
            ),
          ),
          const Divider(height: AppSpacing.xl),
          Expanded(
            child: groups.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Text('لا نتائج — جرّب إيموجي بدلاً من ذلك'),
                    ),
                  )
                : ListView(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    children: [
                      for (final group in groups) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.sm),
                          child: Text(
                            group.label,
                            style: TextStyle(
                              fontSize: AppTextSizes.label,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: AppSpacing.md,
                          runSpacing: AppSpacing.md,
                          children: [
                            for (final key in group.keys)
                              GestureDetector(
                                onTap: () => setState(() => _iconKey = key),
                                child: CategoryIconTile(
                                  iconKey: key,
                                  colorValue: _color.toARGB32(),
                                  size: 46,
                                  selected: key == _iconKey,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
