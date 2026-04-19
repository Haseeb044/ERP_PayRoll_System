import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/payroll_model.dart';
import '../../data/models/payslip_item_model.dart';
import '../../logic/payroll/payroll_bloc.dart';
import '../../logic/payroll/payslip_pdf_service.dart';

class PayslipPdfView extends StatelessWidget {
  final String riderId;

  const PayslipPdfView({super.key, required this.riderId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Payslip Preview",
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: BlocBuilder<PayrollBloc, PayrollState>(
        builder: (context, state) {
          // Find the payslip in batchDetails by matching the payslip id
          PayslipDraftModel? payslip;
          for (final entry in state.batchDetails.values) {
            for (final p in entry) {
              if (p.id == riderId || p.externalId == riderId) {
                payslip = p;
                break;
              }
            }
            if (payslip != null) break;
          }

          if (payslip == null) {
            return Center(
              child: Text(
                "Payslip data not found.",
                style: GoogleFonts.poppins(color: Colors.grey),
              ),
            );
          }

          final resolvedPayslip = payslip;

          final loanDeduction = resolvedPayslip.items
              .where((item) {
                final isDeduction =
                item.type == PayslipItemType.loan ||
                item.type == PayslipItemType.deduction ||
                item.type == PayslipItemType.platformDeduction;
                final lowerLabel = item.label.toLowerCase();
                final isLoan =
                    lowerLabel.contains('loan') || lowerLabel.contains('advance');
              return isDeduction && (isLoan || item.type == PayslipItemType.loan);
              })
              .fold<double>(0.0, (sum, item) => sum + item.amount.abs());

          final expenseDeduction = resolvedPayslip.items
              .where((item) {
                final isDeduction =
                item.type == PayslipItemType.deduction ||
                item.type == PayslipItemType.platformDeduction;
                final lowerLabel = item.label.toLowerCase();
                final isLoan =
                    lowerLabel.contains('loan') || lowerLabel.contains('advance');
                return isDeduction && !isLoan;
              })
              .fold<double>(0.0, (sum, item) => sum + item.amount.abs());

          final fallbackExpenseDeduction =
              resolvedPayslip.totalExpenses + resolvedPayslip.totalFines;
          final finalExpenseDeduction =
              expenseDeduction > 0 ? expenseDeduction : fallbackExpenseDeduction;

          return PdfPreview(
            build: (format) => PayslipPdfService.generatePayslip(
              riderName: resolvedPayslip.riderName,
              riderId: resolvedPayslip.externalId,
              month: DateTime.now(),
              grossSalary: resolvedPayslip.grossSalary,
              platformDeduction: resolvedPayslip.platformDeductions,
              expenseDeduction: finalExpenseDeduction,
              loanDeduction: loanDeduction,
              netSalary: resolvedPayslip.netSalary,
              platform: resolvedPayslip.platform,
            ),
            canDebug: false,
            loadingWidget: const Center(child: CircularProgressIndicator()),
          );
        },
      ),
    );
  }
}
