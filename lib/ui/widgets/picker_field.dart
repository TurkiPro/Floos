import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// One selectable option for [PickerField].
class PickerOption<T> {
  final T value;
  final String label;
  const PickerOption(this.value, this.label);
}

/// A dropdown-styled field that opens its choices in a modal bottom sheet
/// instead of Material's legacy `DropdownButton` overlay. The legacy overlay
/// mispositions itself when it lives inside another bottom sheet (it tries to
/// float the selected item over the button and lands mid-screen); a modal list
/// is positioned by the framework and behaves identically on every platform.
class PickerField<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<PickerOption<T>> options;
  final ValueChanged<T> onChanged;

  const PickerField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == null
        ? null
        : options.where((o) => o.value == value).firstOrNull;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.tile),
      onTap: () => _open(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected?.label ?? '',
                style: const TextStyle(fontSize: AppTextSizes.row),
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final o in options)
              ListTile(
                title: Text(o.label),
                trailing: o.value == value
                    ? Icon(Icons.check,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () => Navigator.of(context).pop(o.value),
              ),
          ],
        ),
      ),
    );
    if (picked != null) onChanged(picked);
  }
}
