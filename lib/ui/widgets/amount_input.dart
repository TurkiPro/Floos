import 'package:flutter/services.dart';

import '../../domain/parse_amount.dart';

/// Live thousands-grouping for amount fields: as the user types, the integer
/// part is grouped with commas (1000 → 1,000) so large numbers are readable at
/// a glance. Any script's digits are normalised to Western first, so the field
/// always reads the same way the rest of the app formats money. The decimal
/// part (after '.') is kept ungrouped and capped at two places.
///
/// [parseAmount] strips those commas back out, so the grouping never affects
/// the saved value.
class ThousandsInputFormatter extends TextInputFormatter {
  const ThousandsInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    // Western digits, '.' decimal, no grouping — then keep only [0-9.].
    var norm =
        normalizeAmountInput(newValue.text).replaceAll(RegExp(r'[^0-9.]'), '');
    if (norm.isEmpty) return const TextEditingValue();

    // Collapse to a single decimal point (keep the first).
    final firstDot = norm.indexOf('.');
    final hasDot = firstDot >= 0;
    if (hasDot) {
      norm = norm.substring(0, firstDot + 1) +
          norm.substring(firstDot + 1).replaceAll('.', '');
    }

    var intPart = hasDot ? norm.substring(0, firstDot) : norm;
    var decPart = hasDot ? norm.substring(firstDot + 1) : null;
    if (decPart != null && decPart.length > 2) {
      decPart = decPart.substring(0, 2);
    }

    // Drop leading zeros (keep one digit); "" becomes "0" only when a decimal
    // follows, so a bare "" stays empty and "0." shows while typing.
    intPart = intPart.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (intPart.isEmpty && hasDot) intPart = '0';

    final grouped = intPart.isEmpty ? '' : _group(intPart);
    final text = hasDot ? '$grouped.$decPart' : grouped;

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  static String _group(String digits) {
    final buf = StringBuffer();
    final n = digits.length;
    for (var i = 0; i < n; i++) {
      if (i > 0 && (n - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return buf.toString();
  }
}

/// Formats a stored amount for pre-filling an edit field with the same grouping
/// the [ThousandsInputFormatter] produces (no currency symbol). Whole values
/// show no decimals; otherwise up to two.
String groupedAmount(double value) {
  final whole = value == value.roundToDouble();
  final s = whole ? value.toInt().toString() : value.toStringAsFixed(2);
  final dot = s.indexOf('.');
  final intPart = dot >= 0 ? s.substring(0, dot) : s;
  final decPart = dot >= 0 ? s.substring(dot + 1) : null;
  final grouped = ThousandsInputFormatter._group(intPart);
  return decPart != null ? '$grouped.$decPart' : grouped;
}
