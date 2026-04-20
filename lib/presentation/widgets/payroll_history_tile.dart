import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import '../../logic/payroll/payroll_bloc.dart';
import '../../data/models/payroll_model.dart';
import '../../logic/payroll/payroll_journal_pdf_service.dart';
import '../../core/app_theme.dart';

class PayrollHistoryTile extends StatefulWidget {
  final PayrollBatchModel batch;

  const PayrollHistoryTile({super.key, required this.batch});

  @override
  State<PayrollHistoryTile> createState() => _PayrollHistoryTileState();
}

class _PayrollHistoryTileState extends State<PayrollHistoryTile> {
  bool _isExpanded = false;
  final ScrollController _horizontalScrollController = ScrollController();

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PayrollBloc, PayrollState>(
      builder: (context, state) {
        final payslips = state.batchDetails[widget.batch.id];
        final isLoading = _isExpanded && payslips == null;
        final liveTotalAmount = payslips != null
          ? (() {
            final isDraftBatch = widget.batch.status == PayrollBatchStatus.draft;
            final source = isDraftBatch
              ? payslips
                  .where((p) => p.status != PayslipDraftStatus.finalized)
                  .toList(growable: false)
              : payslips;
            return source.fold<double>(0.0, (sum, p) => sum + p.netSalary);
            })()
          : widget.batch.totalAmount;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF1F5F9)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Summary Row
              InkWell(
                onTap: () {
                  setState(() => _isExpanded = !_isExpanded);
                  if (_isExpanded && payslips == null) {
                    context.read<PayrollBloc>().add(
                      LoadBatchPayslips(widget.batch.id),
                    );
                  }
                },
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet,
                          color: Color(0xFF3B82F6),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "${widget.batch.platform} - ${DateFormat('MMMM yyyy').format(widget.batch.month)}",
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Batch ID: ${widget.batch.id}",
                              style: GoogleFonts.poppins(
                                color: const Color(0xFF94A3B8),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "AED ${liveTotalAmount.toStringAsFixed(2)}",
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                icon: const Icon(
                                  Icons.open_in_new,
                                  size: 20,
                                  color: Color(0xFF64748B),
                                ),
                                onPressed: () {
                                  context.read<PayrollBloc>().add(
                                    LoadBatchDetails(widget.batch.id),
                                  );
                                },
                                tooltip: "View Details",
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _StatusBadge(status: widget.batch.status),
                              const SizedBox(width: 8),
                              Icon(
                                _isExpanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                color: const Color(0xFF94A3B8),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Expanded Content
              if (_isExpanded) ...[
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Payslip Details",
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Row(
                            children: [
                              if (widget.batch.status ==
                                  PayrollBatchStatus.draft) ...[
                                ElevatedButton.icon(
                                  onPressed: () {
                                    context.read<PayrollBloc>().add(
                                      LoadBatchDetails(widget.batch.id),
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.check_circle,
                                    size: 18,
                                  ),
                                  label: const Text("Finalize Run"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.secondaryColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              ElevatedButton.icon(
                                onPressed: payslips == null
                                    ? null
                                    : () async {
                                        final pdfBytes =
                                            await PayrollJournalPdfService.generateJournalPdf(
                                              payslips: payslips,
                                              batchName: widget.batch.platform,
                                              month: widget.batch.month,
                                            );

                                        final fileName =
                                            'Payroll_Journal_${widget.batch.platform}_${DateFormat('MMM_yyyy').format(widget.batch.month)}.pdf';

                                        try {
                                          final directory =
                                              await getDownloadsDirectory();
                                          if (directory != null) {
                                            final filePath =
                                                '${directory.path}/$fileName';
                                            final file = File(filePath);
                                            await file.writeAsBytes(pdfBytes);

                                            if (mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    "Saved to Downloads: $fileName",
                                                  ),
                                                  backgroundColor: Colors.green,
                                                ),
                                              );
                                            }
                                          } else {
                                            await Printing.layoutPdf(
                                              onLayout: (format) => pdfBytes,
                                              name: fileName,
                                            );
                                          }
                                        } catch (e) {
                                          await Printing.layoutPdf(
                                            onLayout: (format) => pdfBytes,
                                            name: fileName,
                                          );
                                        }
                                      },
                                icon: const Icon(Icons.download, size: 18),
                                label: const Text("Export Journal"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryColor,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  textStyle: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (isLoading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20.0),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (payslips == null || payslips.isEmpty)
                        const Text("No payslips found for this batch.")
                      else
                        _buildPayslipTable(payslips),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildPayslipTable(List<PayslipDraftModel> payslips) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Scrollbar(
        controller: _horizontalScrollController,
        thumbVisibility: false,
        child: SingleChildScrollView(
          controller: _horizontalScrollController,
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 24,
            headingRowHeight: 40,
            dataRowMinHeight: 40,
            dataRowMaxHeight: 48,
            columns: [
              const DataColumn(label: Text("Rider Name")),
              const DataColumn(label: Text("Ext ID")),
              const DataColumn(label: Text("Gross")),
              const DataColumn(label: Text("Fines")),
              const DataColumn(label: Text("Exp.")),
              const DataColumn(label: Text("Net")),
              const DataColumn(label: Text("Actions")),
            ],
            rows: payslips.map((p) {
              return DataRow(
                cells: [
                  DataCell(Text(p.riderName)),
                  DataCell(Text(p.externalId)),
                  DataCell(Text(p.grossSalary.toStringAsFixed(2))),
                  DataCell(
                    Text(
                      p.totalFines.toStringAsFixed(2),
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                  DataCell(
                    Text(
                      p.totalExpenses.toStringAsFixed(2),
                      style: const TextStyle(color: Colors.orange),
                    ),
                  ),
                  DataCell(
                    Text(
                      p.netSalary.toStringAsFixed(2),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataCell(
                    IconButton(
                      icon: const Icon(Icons.visibility, size: 18),
                      onPressed: () {
                        context.read<PayrollBloc>().add(
                          LoadBatchDetails(widget.batch.id),
                        );
                      },
                      tooltip: "View in Review",
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final PayrollBatchStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;

    switch (status) {
      case PayrollBatchStatus.finalized:
      case PayrollBatchStatus.posted:
        bgColor = const Color(0xFFDCFCE7);
        textColor = const Color(0xFF166534);
        break;
      case PayrollBatchStatus.draft:
        bgColor = const Color(0xFFFEF9C3);
        textColor = const Color(0xFF854D0E);
        break;
      case PayrollBatchStatus.error:
        bgColor = const Color(0xFFFFF1F2);
        textColor = const Color(0xFFE11D48);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        status.name.toUpperCase(),
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }
}

