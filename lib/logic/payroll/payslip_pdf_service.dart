import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

class PayslipPdfService {
  static Future<Uint8List> generatePayslip({
    required String riderName,
    required String riderId,
    required DateTime month,
    required double grossSalary,
    required double platformDeduction,
    required double expenseDeduction,
    required double loanDeduction,
    required double netSalary,
    String? platform,
  }) async {
    final pdf = pw.Document();
    final monthStr = DateFormat('MMMM yyyy').format(month);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(40),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          "RIDER PAYROLL ERP",
                          style: pw.TextStyle(
                            fontSize: 24,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.green900,
                          ),
                        ),
                        pw.Text(
                          "Official Payslip",
                          style: pw.TextStyle(
                            fontSize: 14,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                    pw.Text(
                      monthStr,
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 40),
                pw.Divider(thickness: 2, color: PdfColors.grey300),
                pw.SizedBox(height: 20),

                // Section 1: Rider Details
                pw.Text(
                  "RIDER INFORMATION",
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Row(
                  children: [
                    pw.Expanded(child: _infoField("Name", riderName)),
                    pw.Expanded(child: _infoField("Rider ID", riderId)),
                    if (platform != null)
                      pw.Expanded(child: _infoField("Platform", platform.toUpperCase())),
                  ],
                ),
                pw.SizedBox(height: 30),

                // Section 2: Earnings & Deductions Table
                pw.Table(
                  border: pw.TableBorder.all(
                    color: PdfColors.grey200,
                    width: 0.5,
                  ),
                  children: [
                    // Header Row
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey100,
                      ),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(10),
                          child: pw.Text(
                            "Description",
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(10),
                          child: pw.Text(
                            "Amount (AED)",
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                            textAlign: pw.TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                    // Earnings
                    _tableRow("Gross Salary / Base Pay", grossSalary),
                    // Deductions
                    _tableRow("Platform Fee / Deduction", -platformDeduction),
                    _tableRow("Expense Deductions", -expenseDeduction),
                    _tableRow("Loan Deductions", -loanDeduction),
                  ],
                ),

                pw.Spacer(),

                // Final Net Pay
                pw.Divider(thickness: 1, color: PdfColors.grey300),
                pw.SizedBox(height: 10),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          "NET PAYOUT",
                          style: pw.TextStyle(
                            fontSize: 12,
                            color: PdfColors.grey600,
                          ),
                        ),
                        pw.Text(
                          "AED ${netSalary.toStringAsFixed(2)}",
                          style: pw.TextStyle(
                            fontSize: 28,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 40),

                // Footer
                pw.Center(
                  child: pw.Text(
                    "This is a system-generated payslip and does not require a physical signature.",
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey500,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _infoField(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey500),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  static pw.TableRow _tableRow(String label, double amount) {
    return pw.TableRow(
      children: [
        pw.Padding(padding: const pw.EdgeInsets.all(10), child: pw.Text(label)),
        pw.Padding(
          padding: const pw.EdgeInsets.all(10),
          child: pw.Text(
            amount.toStringAsFixed(2),
            textAlign: pw.TextAlign.right,
          ),
        ),
      ],
    );
  }
}
