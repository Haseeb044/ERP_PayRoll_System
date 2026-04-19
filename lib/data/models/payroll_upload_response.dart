class PayrollUploadResponse {
  final String batchId;
  final String message;
  final int payslipsCreated;
  final List<String> unmatchedIds;
  final List<String> errorLogs;

  PayrollUploadResponse({
    required this.batchId,
    required this.message,
    required this.payslipsCreated,
    required this.unmatchedIds,
    this.errorLogs = const [],
  });

  factory PayrollUploadResponse.fromJson(Map<String, dynamic> json) {
    return PayrollUploadResponse(
      batchId: json['batch_id'] ?? '',
      message: json['message'] ?? '',
      payslipsCreated: json['payslips_created'] ?? 0,
      unmatchedIds: List<String>.from(json['unmatched_ids'] ?? []),
      errorLogs: List<String>.from(json['error_logs'] ?? []),
    );
  }
}
