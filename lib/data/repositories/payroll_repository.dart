import '../models/payroll_model.dart';
import '../models/payroll_upload_response.dart';
import 'dart:io';

abstract class PayrollRepository {
  Future<List<PayrollBatchModel>> fetchPayrollHistory();
  Future<List<PayslipDraftModel>> uploadPayrollSheet(
    File file,
    String platform,
    DateTime month,
  );
  Future<void> finalizePayroll(
    List<PayslipDraftModel> drafts,
    String platform,
    DateTime month, {
    String? batchId,
  });
  Future<Map<String, dynamic>> fetchPayslips(String batchId);
  Future<PayrollUploadResponse> uploadPayroll(
    String month,
    String platform,
    List<Map<String, dynamic>> rows,
  );
  Future<void> finalizePayrollWithJournals(
    String batchId,
    String drawerId,
  );
  Future<void> finalizeIndividualPayslip(
    String payslipId,
    String drawerId,
  );
  Future<void> updatePayslipData(
    String payslipId,
    Map<String, dynamic> data,
  );
  Future<void> recalculateDeductions(String payslipId, String riderId);
  Future<void> syncBatch(String batchId);
  Future<void> editPayslipDeductionItem({
    required String payslipId,
    required int itemIndex,
    required double newAmount,
    String? expectedLabel,
    String? reason,
  });
  Future<void> replacePayslipItems({
    required String payslipId,
    required List<Map<String, dynamic>> items,
    String? reason,
  });
  Future<Map<String, dynamic>> getPayslipGroupedDeductions(String payslipId);
  Future<Map<String, dynamic>> getBatchFlaggedPayslips(String batchId);
  Future<Map<String, dynamic>> getBatchReviewSummary(String batchId);
  Future<Map<String, dynamic>> getCarryForwardOptions(String riderId);
  Future<Map<String, dynamic>> applyCarryForwardSelections(
    String payslipId,
    List<Map<String, dynamic>> selections,
  );
}
