import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../logic/payroll/payroll_bloc.dart';
import '../../core/app_theme.dart';

class PayslipListPage extends StatelessWidget {
  final String batchId;

  const PayslipListPage({super.key, required this.batchId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          "Batch Payslips",
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
        centerTitle: false,
      ),
      body: BlocBuilder<PayrollBloc, PayrollState>(
        builder: (context, state) {
          // Fetch payslips for this batch if not already loaded
          final payslips = state.batchDetails[batchId];
          if (payslips == null) {
            // Trigger loading
            context.read<PayrollBloc>().add(LoadBatchPayslips(batchId));
            return const Center(child: CircularProgressIndicator());
          }

          if (payslips.isEmpty) {
            return Center(
              child: Text(
                "No payslips found for this batch.",
                style: GoogleFonts.poppins(color: Colors.grey),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "SELECT RIDER TO VIEW PDF",
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF94A3B8),
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView.separated(
                    itemCount: payslips.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final rider = payslips[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFF1F5F9)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFEFF6FF),
                            child: Text(
                              rider.riderName.isNotEmpty ? rider.riderName[0] : '?',
                              style: const TextStyle(color: Color(0xFF3B82F6)),
                            ),
                          ),
                          title: Text(
                            rider.riderName,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text("ID: ${rider.externalId}"),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                "AED ${rider.netSalary.toStringAsFixed(2)}",
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.secondaryColor,
                                ),
                              ),
                              const Icon(
                                Icons.picture_as_pdf,
                                size: 16,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                          onTap: () =>
                              context.push('/payroll/payslip/${rider.id}'),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
