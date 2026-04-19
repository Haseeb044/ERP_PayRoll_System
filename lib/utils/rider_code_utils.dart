import 'dart:math';

/// Utility class for generating and validating rider codes.
/// A valid rider code is exactly 8 characters with mix of:
/// - At least one number (0-9)
/// - At least one uppercase letter (A-Z)
/// - At least one symbol (!@#$%^&*)
class RiderCodeUtils {
  static const String _symbols = "!@#\$%^&*";
  static const String _letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  static const String _numbers = "0123456789";
  static const int _codeLength = 8;

  /// Generate a random valid rider code
  static String generateRandomCode() {
    final random = Random.secure();

    // Ensure we have at least one of each type
    final chars = <String>[];

    // Add one number
    chars.add(_numbers[random.nextInt(_numbers.length)]);

    // Add one letter
    chars.add(_letters[random.nextInt(_letters.length)]);

    // Add one symbol
    chars.add(_symbols[random.nextInt(_symbols.length)]);

    // Fill remaining 5 characters with random mix
    final allChars = "$_numbers$_letters$_symbols";
    for (int i = 0; i < (_codeLength - 3); i++) {
      chars.add(allChars[random.nextInt(allChars.length)]);
    }

    // Shuffle to avoid predictable patterns
    chars.shuffle(random);

    return chars.join();
  }

  /// Validate if a rider code follows the required format
  static String? validateRiderCode(String? value) {
    if (value == null || value.isEmpty) {
      return "Rider ID is required";
    }

    if (value.length != _codeLength) {
      return "Rider ID must be exactly $_codeLength characters";
    }

    final hasNumber = value.contains(RegExp(r'[0-9]'));
    final hasLetter = value.contains(RegExp(r'[A-Z]'));
    final hasSymbol = value.contains(RegExp(r'[!@#\$%^&*]'));

    if (!hasNumber) {
      return "Rider ID must contain at least one number";
    }
    if (!hasLetter) {
      return "Rider ID must contain at least one uppercase letter";
    }
    if (!hasSymbol) {
      return "Rider ID must contain at least one symbol (!@#\$%^&*)";
    }

    return null; // Valid
  }

  /// Check if a rider code is valid (format only, not uniqueness)
  static bool isValidFormat(String code) {
    return validateRiderCode(code) == null;
  }
}
