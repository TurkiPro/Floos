/// Parses user-typed money/count input in an Arabic-first app.
///
/// `double.tryParse` only understands Western digits, but Arabic keyboards
/// commonly emit Eastern Arabic-Indic digits (٠١٢٣٤٥٦٧٨٩ — or the Persian
/// variants ۰۱۲۳۴۵۶۷۸۹), the Arabic decimal separator (٫ U+066B) and the
/// Arabic thousands separator (٬ U+066C). This normalizes all of those, treats
/// both ',' and '٫' as decimal points (matching the app's historic
/// `replaceAll(',', '.')` behavior), strips '٬', and then parses.
double? parseAmount(String raw) {
  final s = _normalizeDigits(raw.trim());
  if (s.isEmpty) return null;
  return double.tryParse(s);
}

/// Same normalization for whole-number fields (e.g. a recurrence interval).
int? parseCount(String raw) {
  final s = _normalizeDigits(raw.trim());
  if (s.isEmpty) return null;
  return int.tryParse(s);
}

String _normalizeDigits(String input) {
  const easternZero = 0x0660; // ٠
  const persianZero = 0x06F0; // ۰
  final out = StringBuffer();
  for (final r in input.runes) {
    if (r >= easternZero && r <= easternZero + 9) {
      out.writeCharCode(0x30 + (r - easternZero));
    } else if (r >= persianZero && r <= persianZero + 9) {
      out.writeCharCode(0x30 + (r - persianZero));
    } else if (r == 0x066B /* ٫ */ || r == 0x2C /* , */) {
      out.write('.');
    } else if (r == 0x066C /* ٬ */) {
      // thousands separator — drop
    } else {
      out.writeCharCode(r);
    }
  }
  return out.toString();
}
