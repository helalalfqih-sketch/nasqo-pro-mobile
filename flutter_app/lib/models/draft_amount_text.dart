/// Formats an existing numeric draft amount for decimal-only input without
/// rounding it or injecting a currency. Keeps negative diagnostic values as-is.
String draftAmountText(double? value) {
  if (value == null) return '';
  final text = value.toString();
  final separator = text.indexOf('e');
  if (separator < 0) return text;
  final exponent = int.tryParse(text.substring(separator + 1));
  if (exponent == null) return text;
  final negative = text.startsWith('-');
  final mantissa = text.substring(negative ? 1 : 0, separator);
  final point = mantissa.indexOf('.');
  final digits = mantissa.replaceAll('.', '');
  final index = (point < 0 ? mantissa.length : point) + exponent;
  final String plain;
  if (index <= 0) {
    plain = '0.${''.padLeft(-index, '0')}$digits';
  } else if (index >= digits.length) {
    plain = digits.padRight(index, '0');
  } else {
    plain = '${digits.substring(0, index)}.${digits.substring(index)}';
  }
  return negative ? '-$plain' : plain;
}
