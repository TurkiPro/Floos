/// Parses user-typed money/count input in an Arabic-first app.
///
/// `double.tryParse` only understands Western digits, but Arabic keyboards
/// commonly emit Eastern Arabic-Indic digits (٠١٢٣٤٥٦٧٨٩ — or the Persian
/// variants ۰۱۲۳۴۵۶۷۸۹), the Arabic decimal separator (٫ U+066B) and the
/// Arabic thousands separator (٬ U+066C). This normalizes all of those.
///
/// The decimal separators (Western '.' and Arabic '٫') become '.'; the
/// thousands separators (Western ',' and Arabic '٬') are dropped — matching the
/// live grouping the amount fields now show (1,000.00), where a comma always
/// means "thousands", never "decimal".
double? parseAmount(String raw) {
  final s = normalizeAmountInput(raw);
  if (s.isEmpty) return null;
  return double.tryParse(s);
}

/// Same normalization for whole-number fields (e.g. a recurrence interval).
int? parseCount(String raw) {
  final s = normalizeAmountInput(raw);
  if (s.isEmpty) return null;
  return int.tryParse(s);
}

/// Turns any script's numeric input into a bare Western-digit string with '.'
/// as the only decimal separator and no grouping — ready for `double.tryParse`
/// or for the amount fields' live comma-grouping formatter to re-group.
String normalizeAmountInput(String input) {
  const easternZero = 0x0660; // ٠
  const persianZero = 0x06F0; // ۰
  final out = StringBuffer();
  for (final r in input.trim().runes) {
    if (r >= easternZero && r <= easternZero + 9) {
      out.writeCharCode(0x30 + (r - easternZero));
    } else if (r >= persianZero && r <= persianZero + 9) {
      out.writeCharCode(0x30 + (r - persianZero));
    } else if (r == 0x066B /* ٫ Arabic decimal */) {
      out.write('.');
    } else if (r == 0x066C /* ٬ Arabic thousands */ || r == 0x2C /* , */) {
      // thousands separator — drop
    } else {
      out.writeCharCode(r);
    }
  }
  return out.toString();
}
