String toUserFriendlyErrorMessage(
  Object error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  final raw = error.toString();
  final lower = raw.toLowerCase();

  if (lower.contains('insufficient funds') || lower.contains('insufficient balance')) {
    final detail = RegExp(r'insufficient[^\n\r]*', caseSensitive: false)
        .firstMatch(raw)
        ?.group(0);
    if (detail != null && detail.isNotEmpty) {
      return detail;
    }
    return 'Insufficient balance. Please top up and try again.';
  }

  if (lower.contains('uq_batch_month_platform') || lower.contains('duplicate key value')) {
    return 'This payroll month and platform is already uploaded.';
  }

  if (lower.contains('failed host lookup') ||
      lower.contains('socketexception') ||
      lower.contains('readerror') ||
      lower.contains('winerror 10035')) {
    return 'Network connection issue. Please check internet and retry.';
  }

  if (lower.contains('invalid input value for enum')) {
    return 'Data format mismatch detected. Please refresh and try again.';
  }

  if (lower.contains('column expenses.category does not exist')) {
    return 'Report configuration mismatch detected. Please contact support.';
  }

  if (raw.startsWith('Exception: ')) {
    return raw.replaceFirst('Exception: ', '');
  }

  return fallback;
}

String toUserFriendlyError(
  Object error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  return toUserFriendlyErrorMessage(error, fallback: fallback);
}
