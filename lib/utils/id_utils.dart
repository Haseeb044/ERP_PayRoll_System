/// Utility to clean platform IDs from various Excel formats.
/// Handles scientific notation (1.75508e+15 → 1755080009514672),
/// decimal format (2834891.0 → 2834891), and trims whitespace.
/// Returns a plain integer string with no decimals, no scientific notation, no spaces.
String cleanPlatformId(dynamic rawValue) {
  if (rawValue == null) return '';
  String raw = rawValue.toString().trim();
  if (raw.isEmpty) return '';
  try {
    if (raw.contains('e') || raw.contains('E') || raw.contains('.')) {
      double parsed = double.parse(raw);
      return parsed.toStringAsFixed(0);
    }
  } catch (_) {}
  return raw;
}
