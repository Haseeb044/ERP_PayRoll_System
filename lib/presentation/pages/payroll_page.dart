import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../../core/app_theme.dart';
import '../../logic/payroll/payroll_bloc.dart';
import '../../utils/user_friendly_error.dart';
import 'package:go_router/go_router.dart';
import '../widgets/payroll_history_tile.dart';

class PayrollPage extends StatefulWidget {
  const PayrollPage({super.key});

  @override
  State<PayrollPage> createState() => _PayrollPageState();
}

class _PayrollPageState extends State<PayrollPage> {
  @override
  void initState() {
    super.initState();
    context.read<PayrollBloc>().add(LoadPayrollHistory());
  }

  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: BlocConsumer<PayrollBloc, PayrollState>(
        listenWhen: (previous, current) {
          // Only navigate to drafts if we weren't already on a draft state
          // (prevents re-pushing when popping back from draft screen)
          if (current is PayrollDraftReady && previous is PayrollDraftReady) {
            return false;
          }
          return true;
        },
        listener: (context, state) {
          if (state is PayrollLoading) {
            // Optional: could show a dialog here if we wanted to block everything
          }
          if (state is PayrollDraftReady) {
            context.go('/payroll/draft');
          }
          if (state is PayrollSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.green,
              ),
            );
          }
          if (state is PayrollUploadSuccessState) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                title: const Text(
                  "Upload Successful",
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Payroll batch created successfully."),
                    const SizedBox(height: 16),
                    Text(
                      "Payslips Created: ${state.response.payslipsCreated}",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    if (state.response.unmatchedIds.isNotEmpty) ...[
                      const Text(
                        "Unmatched IDs:",
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 100,
                        width: double.maxFinite,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.3),
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView(
                          padding: const EdgeInsets.all(8),
                          children: state.response.unmatchedIds
                              .map(
                                (id) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2.0,
                                  ),
                                  child: Text(
                                    id,
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "These IDs were skipped.",
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ] else
                      const Text(
                        "All riders matched successfully!",
                        style: TextStyle(color: Colors.green),
                      ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      // Trigger load draft
                      context.read<PayrollBloc>().add(
                        LoadBatchDetails(state.response.batchId),
                      );
                    },
                    child: const Text("View Draft"),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Close"),
                  ),
                ],
              ),
            );
          }
          if (state is PayrollError) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text(
                  "Upload Failed",
                  style: TextStyle(color: Colors.red),
                ),
                content: Text(state.message),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("OK"),
                  ),
                ],
              ),
            );
          }
        },
        builder: (context, state) {
          return Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 700;
                  final hPad = isNarrow ? 16.0 : 32.0;
                  return Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: hPad,
                      vertical: 24,
                    ),
                    child: Column(
                      children: [
                        // Header
                        isNarrow
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Payroll Management',
                                    style: GoogleFonts.poppins(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF1E293B),
                                    ),
                                  ),
                                  Text(
                                    'Manage platform uploads and monthly payouts',
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: const Color(0xFF64748B),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    onPressed: _showUploadDialog,
                                    icon: const Icon(
                                      Icons.cloud_upload_outlined,
                                      size: 18,
                                    ),
                                    label: const Text("Upload Timesheet"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.secondaryColor,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              'Payroll Management',
                                              style: GoogleFonts.poppins(
                                                fontSize: 28,
                                                fontWeight: FontWeight.bold,
                                                color: const Color(0xFF1E293B),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            IconButton(
                                              onPressed: () => context
                                                  .read<PayrollBloc>()
                                                  .add(LoadPayrollHistory()),
                                              icon: const Icon(
                                                Icons.refresh,
                                                color: AppTheme.primaryColor,
                                              ),
                                              tooltip: 'Refresh History',
                                            ),
                                          ],
                                        ),
                                        Text(
                                          'Manage platform uploads and monthly payouts',
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            color: const Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: _showUploadDialog,
                                    icon: const Icon(
                                      Icons.cloud_upload_outlined,
                                    ),
                                    label: const Text("Upload Timesheet"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.secondaryColor,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                        const SizedBox(height: 24),

                        // Search & Filter (Visual Only for now)
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 50,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const TextField(
                                  decoration: InputDecoration(
                                    prefixIcon: Icon(Icons.search),
                                    border: InputBorder.none,
                                    hintText: "Search History...",
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),

                        Expanded(
                          child:
                              state.history.isEmpty && state is! PayrollLoading
                              ? Center(
                                  child: Text(
                                    "No history found",
                                    style: GoogleFonts.poppins(
                                      color: Colors.grey,
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: state.history.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 16),
                                  itemBuilder: (ctx, i) => PayrollHistoryTile(
                                    batch: state.history[i],
                                  ),
                                ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              // Loading Overlay
              if (state is PayrollLoading)
                Container(
                  color: Colors.black54,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            "Processing Payroll...",
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showUploadDialog() {
    String selectedPlatform = "Talabat";
    DateTime selectedMonth = DateTime.now();

    // Capture the Bloc from the PARENT context (Scaffold/Page)
    // This is safe because the Page is still mounted even if dialog closes.
    final payrollBloc = context.read<PayrollBloc>();
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            "New Payroll Run",
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Select platform and month."),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: selectedPlatform,
                items: ["Talabat", "Keeta", "Deliveroo", "Careem"]
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedPlatform = v!),
              ),
              const SizedBox(height: 10),
              ListTile(
                title: Text(DateFormat('MMMM yyyy').format(selectedMonth)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: selectedMonth,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) setDialogState(() => selectedMonth = d);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                print("DEBUG: Upload confirmed. Closing dialog.");
                Navigator.pop(dialogContext);

                try {
                  print("DEBUG: Invoking File Picker...");
                  FilePickerResult? result = await FilePicker.platform
                      .pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['xlsx', 'xls', 'csv', 'txt'],
                      );

                  if (result != null && result.files.single.path != null) {
                    final path = result.files.single.path!;
                    print("DEBUG: File picked: $path");

                    // CRITICAL FIX: Do NOT check context.mounted for bloc operations
                    // We already captured 'payrollBloc' from the parent page.

                    print("DEBUG: Adding UploadPayrollSheet event to Bloc...");
                    payrollBloc.add(
                      UploadPayrollSheet(
                        file: File(path),
                        platform: selectedPlatform,
                        month: selectedMonth,
                      ),
                    );
                    print("DEBUG: Event added successfully.");

                    // Optional Feedback (if messenger is still valid, which it usually is)
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text("Reading file... please wait."),
                      ),
                    );
                  } else {
                    print("DEBUG: File selection cancelled.");
                  }
                } catch (e, stack) {
                  print("ERROR in Upload Flow: $e");
                  print(stack);
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(toUserFriendlyError(e)),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text("Upload & Process"),
            ),
          ],
        ),
      ),
    );
  }
}
