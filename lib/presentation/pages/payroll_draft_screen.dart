import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../logic/payroll/payroll_bloc.dart';
import '../../data/models/payroll_model.dart';
import '../../data/models/payslip_item_model.dart';

class PayrollDraftScreen extends StatefulWidget {
  const PayrollDraftScreen({super.key});

  @override
  State<PayrollDraftScreen> createState() => _PayrollDraftScreenState();
}

class _PayrollDraftScreenState extends State<PayrollDraftScreen> {
  final ScrollController _summaryScrollController = ScrollController();

  @override
  void dispose() {
    _summaryScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PayrollBloc, PayrollState>(
      listener: (context, state) {
        if (state is PayrollSuccess) {
          context.pop();
        }
        if (state is PayrollError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: Colors.red),
          );
        }
      },
      builder: (context, state) {
        if (state is PayrollLoading) {
          return Scaffold(
            backgroundColor: const Color(0xFFF5F6FA),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    "Processing...",
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          );
        }

        if (state is! PayrollDraftReady) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final sourceDrafts = state.allDrafts;
        final displayedDrafts = state.drafts;
        final errorDrafts = displayedDrafts
            .where((d) => d.status == PayslipDraftStatus.error)
            .toList();
        final matchedDrafts = displayedDrafts
            .where((d) => d.status == PayslipDraftStatus.matched)
            .toList();

        final totalRiders = sourceDrafts.length;
        final matchedCount = sourceDrafts
            .where((d) => d.status == PayslipDraftStatus.matched)
            .length;
        final errorCount = sourceDrafts
            .where((d) => d.status == PayslipDraftStatus.error)
            .length;
        final payableDrafts = sourceDrafts
            .where((d) => d.status != PayslipDraftStatus.finalized)
            .toList(growable: false);

        final totalGross = payableDrafts.fold<double>(
          0.0,
          (s, d) => s + d.grossSalary,
        );
        final totalNet = payableDrafts.fold<double>(
          0.0,
          (s, d) => s + d.netSalary,
        );
        final totalDeductions = totalGross - totalNet;

        final hasNegativeSalary = sourceDrafts.any((d) => d.netSalary < 0);
        final isLocked =
            (state.batchId != null) &&
            state.history.any(
              (b) =>
                  b.id == state.batchId &&
                  (b.status == PayrollBatchStatus.posted ||
                      b.status == PayrollBatchStatus.finalized),
            );

        return Scaffold(
          backgroundColor: const Color(0xFFF5F6FA),
          body: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              children: [
                // Header Row
                _buildHeader(context, state),
                const SizedBox(height: 20),

                // NEW: Upload Results / Error Logs
                if (state.lastUploadErrorLogs.isNotEmpty)
                  _buildUploadResults(state),

                // Summary Bar
                _buildSummaryBar(
                  totalRiders: totalRiders,
                  matchedCount: matchedCount,
                  errorCount: errorCount,
                  totalGross: totalGross,
                  totalDeductions: totalDeductions,
                  totalNet: totalNet,
                ),
                const SizedBox(height: 20),

                // Search Bar
                _buildSearchBar(context),
                const SizedBox(height: 20),

                // Content
                Expanded(
                  child: displayedDrafts.isEmpty
                      ? Center(
                          child: Text(
                            "No drafts found matching your search.",
                            style: GoogleFonts.poppins(color: Colors.grey),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final isDesktop = constraints.maxWidth > 900;
                            final listItems = <Map<String, dynamic>>[];

                            if (hasNegativeSalary) {
                              listItems.add({'type': 'negative_warning'});
                            }

                            if (errorDrafts.isNotEmpty) {
                              listItems.add({
                                'type': 'header',
                                'title': 'Unresolved Riders',
                                'count': errorCount,
                                'color': const Color(0xFFE11D48),
                                'icon': Icons.warning_amber_rounded,
                              });
                              for (var d in errorDrafts) {
                                listItems.add({'type': 'draft', 'data': d});
                              }
                            }

                            if (matchedDrafts.isNotEmpty) {
                              listItems.add({
                                'type': 'header',
                                'title': 'Resolved Riders',
                                'count': matchedCount,
                                'color': const Color(0xFF16A34A),
                                'icon': Icons.check_circle_outline,
                              });
                              for (var d in matchedDrafts) {
                                listItems.add({'type': 'draft', 'data': d});
                              }
                            }

                            if (isDesktop) {
                              final draftsOnly = listItems
                                  .where((i) => i['type'] == 'draft')
                                  .toList();
                              final rowCount = (draftsOnly.length / 2).ceil();

                              return CustomScrollView(
                                slivers: [
                                  SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) {
                                        final item = listItems
                                            .where((i) => i['type'] != 'draft')
                                            .toList()[index];
                                        if (item['type'] ==
                                            'negative_warning') {
                                          return _buildNegativeWarning();
                                        }
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            top: 16.0,
                                            bottom: 12.0,
                                          ),
                                          child: _buildSectionHeader(
                                            item['title'],
                                            item['count'],
                                            item['color'],
                                            item['icon'],
                                          ),
                                        );
                                      },
                                      childCount: listItems
                                          .where((i) => i['type'] != 'draft')
                                          .length,
                                    ),
                                  ),
                                  SliverList(
                                    delegate: SliverChildBuilderDelegate((
                                      context,
                                      index,
                                    ) {
                                      final firstIdx = index * 2;
                                      final secondIdx = firstIdx + 1;

                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 16.0,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Align(
                                                alignment: Alignment.topCenter,
                                                child: _buildDraftCard(
                                                  context,
                                                  draftsOnly[firstIdx]['data'],
                                                  state,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child:
                                                  secondIdx < draftsOnly.length
                                                  ? Align(
                                                      alignment:
                                                          Alignment.topCenter,
                                                      child: _buildDraftCard(
                                                        context,
                                                        draftsOnly[secondIdx]['data'],
                                                        state,
                                                      ),
                                                    )
                                                  : const SizedBox(),
                                            ),
                                          ],
                                        ),
                                      );
                                    }, childCount: rowCount),
                                  ),
                                ],
                              );
                            }

                            return ListView.builder(
                              itemCount: listItems.length,
                              itemBuilder: (context, index) {
                                final item = listItems[index];

                                if (item['type'] == 'negative_warning') {
                                  return _buildNegativeWarning();
                                }

                                if (item['type'] == 'header') {
                                  return Padding(
                                    padding: const EdgeInsets.only(
                                      top: 16.0,
                                      bottom: 12.0,
                                    ),
                                    child: _buildSectionHeader(
                                      item['title'],
                                      item['count'],
                                      item['color'],
                                      item['icon'],
                                    ),
                                  );
                                }

                                if (item['type'] == 'draft') {
                                  return _buildDraftCard(
                                    context,
                                    item['data'],
                                    state,
                                  );
                                }

                                return const SizedBox();
                              },
                            );
                          },
                        ),
                ),
                const SizedBox(height: 16),

                // Footer Actions
                if (!isLocked)
                  _buildFooter(
                    context,
                    errorCount > 0,
                    hasNegativeSalary,
                    state.platform,
                    state.month,
                    state.batchId,
                  ),
                if (isLocked)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.lock_outline,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          "This payroll batch is POSTED and locked.",
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ UPLOAD RESULTS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildUploadResults(PayrollDraftReady state) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: ExpansionTile(
        initiallyExpanded: state.lastUploadErrorLogs.any(
          (log) => log.contains('CRITICAL') || log.contains('ERROR'),
        ),
        leading: Icon(
          state.lastUploadErrorLogs.any((log) => log.contains('ERROR'))
              ? Icons.error_outline
              : Icons.info_outline,
          color: state.lastUploadErrorLogs.any((log) => log.contains('ERROR'))
              ? Colors.red
              : Colors.orange,
        ),
        title: Text(
          state.lastUploadMessage ?? "Upload Summary",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: const Color(0xFF1E293B),
          ),
        ),
        children: [
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: state.lastUploadErrorLogs.length,
              itemBuilder: (context, index) {
                final log = state.lastUploadErrorLogs[index];
                final isError =
                    log.contains('ERROR') || log.contains('CRITICAL');
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isError ? Icons.close_rounded : Icons.info_outline,
                        size: 14,
                        color: isError ? Colors.red : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          log,
                          style: GoogleFonts.robotoMono(
                            fontSize: 12,
                            color: isError
                                ? Colors.red[900]
                                : Colors.orange[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ HEADER â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildHeader(BuildContext context, PayrollDraftReady state) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () {
                context.read<PayrollBloc>().add(CancelPayrollDraft());
                context.pop();
              },
              icon: const Icon(Icons.arrow_back, color: Colors.black87),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Payroll Draft Preview",
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                Text(
                  "${state.platform} - ${DateFormat('MMMM yyyy').format(state.month)}",
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
        ),
        Row(
          children: [
            if (state.batchId != null)
              OutlinedButton.icon(
                onPressed: () => context.read<PayrollBloc>().add(
                  SyncPayrollBatch(state.batchId!),
                ),
                icon: const Icon(Icons.sync, size: 18),
                label: const Text("Sync Latest Data"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  side: const BorderSide(color: AppTheme.primaryColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            const SizedBox(width: 8),
            if (state.batchId != null)
              IconButton(
                onPressed: () => context.read<PayrollBloc>().add(
                  LoadBatchDetails(state.batchId!),
                ),
                icon: const Icon(Icons.refresh, color: Color(0xFF64748B)),
                tooltip: 'Refresh View',
              ),
          ],
        ),
      ],
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ SUMMARY BAR â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildSummaryBar({
    required int totalRiders,
    required int matchedCount,
    required int errorCount,
    required double totalGross,
    required double totalDeductions,
    required double totalNet,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool isSmall = constraints.maxWidth < 700;

          return Wrap(
            spacing: 32,
            runSpacing: 24,
            alignment: WrapAlignment.spaceBetween,
            children: [
              _summaryItem(
                "Total Riders",
                "$totalRiders",
                const Color(0xFF3B82F6),
                isSmall,
              ),
              _summaryItem(
                "Matched",
                "$matchedCount",
                const Color(0xFF16A34A),
                isSmall,
              ),
              _summaryItem(
                "Errors",
                "$errorCount",
                errorCount > 0
                    ? const Color(0xFFE11D48)
                    : const Color(0xFF94A3B8),
                isSmall,
              ),
              _summaryItem(
                "Total Gross",
                "AED ${totalGross.toStringAsFixed(0)}",
                const Color(0xFF1E293B),
                isSmall,
              ),
              _summaryItem(
                "Total Deductions",
                "AED ${totalDeductions.toStringAsFixed(0)}",
                const Color(0xFFEA580C),
                isSmall,
              ),
              _summaryItem(
                "Total Net",
                "AED ${totalNet.toStringAsFixed(0)}",
                AppTheme.primaryColor,
                isSmall,
                isMain: true,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryItem(
    String label,
    String value,
    Color color,
    bool isSmall, {
    bool isMain = false,
  }) {
    return Container(
      constraints: BoxConstraints(minWidth: isSmall ? 100 : 140),
      child: Column(
        crossAxisAlignment: isSmall
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: const Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: isMain ? 22 : 18,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ SECTION HEADER â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildSectionHeader(
    String title,
    int count,
    Color color,
    IconData icon,
  ) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            "$count",
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ SEARCH â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildSearchBar(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        decoration: InputDecoration(
          hintText: "Search Rider Name or ID...",
          hintStyle: GoogleFonts.poppins(color: Colors.grey),
          prefixIcon: const Icon(Icons.search, color: AppTheme.primaryColor),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
        onChanged: (value) {
          context.read<PayrollBloc>().add(SearchPayroll(value));
        },
      ),
    );
  }

  Widget _buildNegativeWarning() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF43F5E)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFE11D48)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Some riders have a negative net salary. Please adjust deductions or resolve issues before finalizing.",
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: const Color(0xFFBE123C),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ DRAFT CARD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildDraftCard(
    BuildContext context,
    PayslipDraftModel draft,
    PayrollDraftReady state,
  ) {
    final isError = draft.status == PayslipDraftStatus.error;
    final isFinalized = draft.status == PayslipDraftStatus.finalized;
    final isReviewRequired = draft.reviewRequired;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isError
            ? const BorderSide(color: Color(0xFFE11D48), width: 1.5)
            : const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: isFinalized
              ? LinearGradient(
                  colors: [Colors.green.withValues(alpha: 0.05), Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 16,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            leading: Hero(
              tag: 'hero-${draft.id}',
              child: CircleAvatar(
                radius: 28,
                backgroundColor: isError
                    ? const Color(0xFFFFF1F2)
                    : isFinalized
                    ? const Color(0xFFDCFCE7)
                    : const Color(0xFFF1F5F9),
                child: Text(
                  draft.riderName.isNotEmpty ? draft.riderName[0] : '?',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isError
                        ? const Color(0xFFE11D48)
                        : isFinalized
                        ? const Color(0xFF166534)
                        : const Color(0xFF475569),
                  ),
                ),
              ),
            ),
            title: Text(
              draft.riderName,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1E293B),
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  "Platform ID: ${draft.externalId}",
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (isError)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1F2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          draft.errorReason ?? "Unresolved Alias",
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFFE11D48),
                          ),
                        ),
                      )
                    else if (isFinalized)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check_circle,
                              size: 14,
                              color: Color(0xFF166534),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "FINALIZED",
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF166534),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "MATCHED",
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.blue[700],
                          ),
                        ),
                      ),
                    if (!isError && !isFinalized && isReviewRequired) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "REVIEW",
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFFB45309),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "NET SALARY",
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    color: const Color(0xFF94A3B8),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  "AED ${draft.netSalary.toStringAsFixed(2)}",
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: isError
                        ? const Color(0xFFE11D48)
                        : AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1, color: Color(0xFFF1F5F9)),
              ),
              const SizedBox(height: 12),
              // Metrics Row
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    if (draft.orderCount > 0)
                      Expanded(
                        child: _buildMetricItem(
                          "Orders",
                          draft.orderCount.toString(),
                          Icons.shopping_bag_outlined,
                        ),
                      ),
                    if (draft.orderCount > 0 && draft.onlineHours > 0)
                      const SizedBox(width: 12),
                    if (draft.onlineHours > 0)
                      Expanded(
                        child: _buildMetricItem(
                          "Hours",
                          draft.onlineHours.toStringAsFixed(1),
                          Icons.access_time_rounded,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Breakdown Header (Premium Look)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Breakdown",
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  Text(
                    "All amounts in AED",
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 1. EARNINGS SECTION
              _buildBreakdownSection(
                title: "Earnings",
                icon: Icons.add_circle_outline,
                color: const Color(0xFF16A34A),
                items: draft.items
                    .where((i) => i.type == PayslipItemType.earning)
                    .map((i) => {'label': i.label, 'amount': i.amount.abs()})
                    .toList(),
              ),

              const SizedBox(height: 16),

              // 2. DEDUCTIONS SECTION
              _buildBreakdownSection(
                title: "Deductions",
                icon: Icons.remove_circle_outline,
                color: const Color(0xFFE11D48), // Rose Red
                items: draft.items
                    .where((i) => i.type != PayslipItemType.earning)
                    .map((i) => {'label': i.label, 'amount': i.amount.abs()})
                    .toList(),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(height: 1, color: Color(0xFFE2E8F0)),
              ),

              // Total Summary Row
              _buildDeductionRow(
                "Net Salary Total",
                draft.netSalary,
                isBold: true,
                isPositive: true,
              ),
              const SizedBox(height: 24),
              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isError)
                    TextButton.icon(
                      onPressed: () {
                        context.push(
                          '/alias-resolution/pending',
                          extra: {
                            'payslipId': draft.id,
                            'platform': state.platform,
                            'platformRiderId': draft.externalId,
                            'riderNameFromSheet': draft.riderName,
                            'grossSalary': draft.grossSalary,
                            'payrollMonth':
                                "${state.month.year}-${state.month.month.toString().padLeft(2, '0')}",
                          },
                        );
                      },
                      icon: const Icon(Icons.build_circle_outlined, size: 18),
                      label: const Text("Fix Alias"),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFE11D48),
                      ),
                    ),
                  if (isError) const SizedBox(width: 12),
                  if (!isError && !isFinalized)
                    ElevatedButton.icon(
                      onPressed: () =>
                          _showDrawerSelectionDialog(context, draft.id),
                      icon: const Icon(Icons.bolt, size: 18),
                      label: const Text("Generate"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      context.push('/payroll/preview', extra: draft);
                    },
                    icon: Icon(
                      isFinalized ? Icons.visibility_outlined : Icons.edit_note,
                      size: 18,
                    ),
                    label: Text(isFinalized ? "View" : "Adjust"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryColor,
                      side: const BorderSide(color: AppTheme.primaryColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () => _generateAndPrintPdf(context, draft),
                    icon: const Icon(Icons.print_outlined, size: 20),
                    tooltip: "Print Payslip",
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey[100],
                      foregroundColor: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDrawerSelectionDialog(BuildContext context, String payslipId) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: Supabase.instance.client.from('drawer').select().asStream(),
          builder: (context, snapshot) {
            if (!snapshot.hasData)
              return const Center(child: CircularProgressIndicator());
            final drawers = snapshot.data!;
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                "Select Payment Drawer",
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: 400,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: drawers.length,
                  itemBuilder: (ctx, idx) {
                    final d = drawers[idx];
                    return ListTile(
                      leading: const Icon(
                        Icons.account_balance_wallet,
                        color: AppTheme.primaryColor,
                      ),
                      title: Text(d['name'] ?? 'Unnamed Drawer'),
                      subtitle: Text("Balance: AED ${d['balance']}"),
                      onTap: () {
                        context.read<PayrollBloc>().add(
                          GenerateIndividualPayslip(
                            payslipId: payslipId,
                            drawerId: d['id'].toString(),
                          ),
                        );
                        Navigator.pop(dialogCtx);
                      },
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMetricItem(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: AppTheme.primaryColor),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: GoogleFonts.poppins(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: const Color(0xFF94A3B8),
                ),
              ),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ FOOTER â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildBreakdownSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<Map<String, dynamic>> items,
  }) {
    // Filter out zero items to keep it clean
    final activeItems = items
        .where((i) => (i['amount'] as num).toDouble() != 0)
        .toList();
    if (activeItems.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: color,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.1)),
          ),
          child: Column(
            children: activeItems.map((item) {
              return _buildDeductionRow(
                item['label'],
                (item['amount'] as num).toDouble(),
                isPositive: title == "Earnings",
                showIndicator: true,
                indicatorColor: color,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildDeductionRow(
    String label,
    double amount, {
    bool isBold = false,
    bool isPositive = false,
    bool showIndicator = false,
    Color? indicatorColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          if (showIndicator && indicatorColor != null)
            Container(
              width: 3,
              height: 14,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: indicatorColor.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
                color: isBold
                    ? const Color(0xFF1E293B)
                    : const Color(0xFF475569),
              ),
            ),
          ),
          Text(
            "${isPositive ? '+' : '-'} AED ${amount.toStringAsFixed(2)}",
            style: GoogleFonts.jetBrainsMono(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              color: isPositive
                  ? const Color(0xFF16A34A)
                  : const Color(0xFFE11D48),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(
    BuildContext context,
    bool hasErrors,
    bool hasNegativeSalary,
    String platform,
    DateTime month,
    String? batchId,
  ) {
    bool canFinalizeMatched = !hasNegativeSalary;
    String buttonText = hasErrors ? "Generate All Matched" : "Finalize Payroll";

    if (hasNegativeSalary) buttonText = "Fix Negative Salaries First";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Row(
        children: [
          if (hasErrors)
            Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: Color(0xFF6366F1),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  "Some records are unmatched. Matched ones will be posted.",
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: const Color(0xFF475569),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          const Spacer(),
          TextButton(
            onPressed: () {
              context.read<PayrollBloc>().add(CancelPayrollDraft());
              context.pop();
            },
            child: Text(
              "Save as Draft",
              style: GoogleFonts.poppins(
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 32),
          ElevatedButton.icon(
            onPressed: !canFinalizeMatched
                ? null
                : () => _showFinalizeDialog(context, platform, month, batchId),
            icon: const Icon(Icons.check_circle_rounded),
            label: Text(buttonText),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
              disabledBackgroundColor: Colors.grey[300],
            ),
          ),
        ],
      ),
    );
  }

  void _showFinalizeDialog(
    BuildContext context,
    String platform,
    DateTime month,
    String? batchId,
  ) async {
    final bloc = context.read<PayrollBloc>();
    final currentState = bloc.state;
    if (currentState is! PayrollDraftReady) return;

    List<Map<String, dynamic>> drawers = [];
    String? selectedDrawerId;

    try {
      final res = await Supabase.instance.client
          .from('drawer')
          .select('id, name, balance')
          .order('name');
      drawers = List<Map<String, dynamic>>.from(res);
    } catch (e) {
      drawers = [];
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Row(
              children: [
                const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(width: 12),
                Text(
                  "Post Journals",
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Only matched riders will be posted. Unmatched will stay in draft.",
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: const Color(0xFF64748B),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  "Select Payment Drawer",
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: DropdownButtonFormField<String>(
                    value: selectedDrawerId,
                    items: drawers
                        .map(
                          (d) => DropdownMenuItem<String>(
                            value: d['id'].toString(),
                            child: Text(
                              "${d['name']} (AED ${(d['balance'] as num?)?.toStringAsFixed(0) ?? '0'})",
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) =>
                        setDialogState(() => selectedDrawerId = v),
                    decoration: const InputDecoration(border: InputBorder.none),
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF1E293B),
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text(
                  "Cancel",
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: selectedDrawerId == null
                    ? null
                    : () {
                        Navigator.pop(dialogCtx);
                        bloc.add(
                          FinalizeBatch(
                            batchId: batchId ?? '',
                            drafts: currentState.allDrafts,
                            platform: platform,
                            month: month,
                            drawerId: selectedDrawerId,
                          ),
                        );
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text("Post Matched"),
              ),
            ],
          );
        },
      ),
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ PDF EXPORT â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _generateAndPrintPdf(
    BuildContext context,
    PayslipDraftModel draft,
  ) async {
    final pdf = pw.Document();

    pw.Font baseFont;
    pw.Font boldFont;
    try {
      baseFont = await PdfGoogleFonts.notoSansRegular();
      boldFont = await PdfGoogleFonts.notoSansBold();
    } catch (_) {
      baseFont = pw.Font.helvetica();
      boldFont = pw.Font.helveticaBold();
    }

    final green = PdfColor.fromInt(0xFF054D2E);

    final white = PdfColors.white;
    final grey = PdfColors.grey600;

    final earningItems = draft.items
        .where(
          (item) =>
              item.type == PayslipItemType.earning &&
              item.amount.abs() > 0.0001,
        )
        .toList();
    final fineItems = draft.items
        .where(
          (item) =>
              item.type == PayslipItemType.fine && item.amount.abs() > 0.0001,
        )
        .toList();
    final loanItems = draft.items
      .where(
        (item) =>
          (item.type == PayslipItemType.loan ||
            item.type == PayslipItemType.deduction ||
            item.type == PayslipItemType.platformDeduction) &&
          item.amount.abs() > 0.0001 &&
          (item.label.toLowerCase().contains('loan') ||
            item.label.toLowerCase().contains('advance')),
      )
      .toList();
    final expenseItems = draft.items
        .where(
          (item) =>
              (item.type == PayslipItemType.deduction ||
                  item.type == PayslipItemType.platformDeduction) &&
          !(item.label.toLowerCase().contains('loan') ||
            item.label.toLowerCase().contains('advance')) &&
              item.amount.abs() > 0.0001,
        )
        .toList();

    final earningsTotal = earningItems.fold<double>(
      0.0,
      (sum, item) => sum + item.amount.abs(),
    );
    final finesTotal = fineItems.fold<double>(
      0.0,
      (sum, item) => sum + item.amount.abs(),
    );
    final expensesTotal = expenseItems.fold<double>(
      0.0,
      (sum, item) => sum + item.amount.abs(),
    );
    final loansTotal = loanItems.fold<double>(
      0.0,
      (sum, item) => sum + item.amount.abs(),
    );
    final deductionsTotal = finesTotal + expensesTotal + loansTotal;
    final companyName = (draft.platform ?? '').trim().toUpperCase();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Theme(
            data: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Rider ERP',
                          style: pw.TextStyle(
                            color: green,
                            fontSize: 24,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          'Official Payslip',
                          style: pw.TextStyle(color: grey, fontSize: 10),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'PAYSLIP',
                          style: pw.TextStyle(
                            color: green,
                            fontSize: 32,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          DateFormat('MMMM yyyy').format(DateTime.now()),
                          style: pw.TextStyle(
                            color: grey,
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 40),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'To:',
                          style: pw.TextStyle(color: grey, fontSize: 10),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          draft.riderName,
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'ID: ${draft.externalId}',
                          style: pw.TextStyle(color: grey, fontSize: 12),
                        ),
                        if (companyName.isNotEmpty)
                          pw.Text(
                            'Company: $companyName',
                            style: pw.TextStyle(
                              color: grey,
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 32),
                // Table header
                pw.Container(
                  decoration: pw.BoxDecoration(
                    color: green,
                    borderRadius: const pw.BorderRadius.vertical(
                      top: pw.Radius.circular(4),
                    ),
                  ),
                  padding: const pw.EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        flex: 4,
                        child: pw.Text(
                          'Description',
                          style: pw.TextStyle(
                            color: white,
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text(
                          'Amount',
                          style: pw.TextStyle(
                            color: white,
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10,
                          ),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),

                _pdfSectionHeader('Earnings', green),
                if (earningItems.isEmpty)
                  _pdfRow('Basic Gross', draft.grossSalary.abs())
                else
                  ...earningItems.map(
                    (item) => _pdfRow(item.label, item.amount.abs()),
                  ),

                _pdfSectionHeader('Deductions - Fine', green),
                if (fineItems.isEmpty)
                  _pdfRow('No Fine', 0)
                else
                  ...fineItems.map(
                    (item) => _pdfRow(item.label, -item.amount.abs()),
                  ),

                _pdfSectionHeader('Deductions - Expense', green),
                if (expenseItems.isEmpty)
                  _pdfRow('No Expense', 0)
                else
                  ...expenseItems.map(
                    (item) => _pdfRow(item.label, -item.amount.abs()),
                  ),

                _pdfSectionHeader('Deductions - Loan', green),
                if (loanItems.isEmpty)
                  _pdfRow('No Loan', 0)
                else
                  ...loanItems.map(
                    (item) => _pdfRow(item.label, -item.amount.abs()),
                  ),

                pw.Divider(color: PdfColors.grey300),
                _pdfSummaryRow('Total Earnings', earningsTotal),
                _pdfSummaryRow('Total Fines', -finesTotal),
                _pdfSummaryRow('Total Expenses', -expensesTotal),
                _pdfSummaryRow('Total Loans', -loansTotal),
                _pdfSummaryRow('Total Deductions', -deductionsTotal),
                pw.SizedBox(height: 16),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Container(
                      width: 200,
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: green,
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'NET PAY',
                            style: pw.TextStyle(
                              color: white,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Text(
                            'AED ${draft.netSalary.toStringAsFixed(2)}',
                            style: pw.TextStyle(
                              color: white,
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.Spacer(),
                pw.Divider(color: PdfColors.grey300),
                pw.SizedBox(height: 8),
                pw.Center(
                  child: pw.Text(
                    'Generated via Rider ERP System',
                    style: const pw.TextStyle(
                      color: PdfColors.grey500,
                      fontSize: 8,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  pw.Widget _pdfRow(String label, double amount) {
    final isNeg = amount < 0;
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey100)),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: 4,
            child: pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              amount.toStringAsFixed(2),
              style: pw.TextStyle(
                fontSize: 10,
                color: isNeg ? PdfColors.red900 : PdfColors.black,
              ),
              textAlign: pw.TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfSectionHeader(String title, PdfColor green) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      color: PdfColor.fromInt(0xFFEFF7F2),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          color: green,
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  pw.Widget _pdfSummaryRow(String label, double amount) {
    final isNeg = amount < 0;
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: 4,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              amount.toStringAsFixed(2),
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: isNeg ? PdfColors.red900 : PdfColors.black,
              ),
              textAlign: pw.TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

