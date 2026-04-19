import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import '../../logic/reports/report_bloc.dart';
import '../../data/models/financial_report_model.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final SupabaseClient _client = Supabase.instance.client;

  static const Map<String, String> _csvLabelAliases = {
    'a': 'Basic Salary',
    'b': 'Bonus',
    't': 'Tips',
    'oil': 'Oil',
    'loan': 'Loan',
    'cod deficit': 'COD Deficit',
    'clawback deduction': 'Clawback Deduction',
    'late delivery': 'Late Delivery',
    'traffic fine': 'Traffic Fine',
  };

  String _normalizeLabelKey(String label) {
    return label.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _cleanLabel(String label) {
    return label.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _csvDisplayLabel(String rawLabel) {
    final cleaned = _cleanLabel(rawLabel);
    final key = _normalizeLabelKey(cleaned);
    return _csvLabelAliases[key] ?? cleaned;
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  bool _isDeductionType(String type) {
    final lower = type.toLowerCase();
    return lower == 'deduction' ||
        lower == 'fine' ||
        lower == 'loan' ||
        lower == 'platform_deduction' ||
        lower == 'platformdeduction';
  }

  bool _isLoanLabel(String label) {
    final lower = _normalizeLabelKey(label);
    return lower.contains('loan') || lower.contains('advance');
  }

  Future<List<Map<String, dynamic>>> _fetchRiderPayslipsForMonth(DateTime month) async {
    final monthKey =
        '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';
    final response = await _client
        .from('payslips')
        .select(
          'id, rider_name, external_id, gross_salary, net_salary, status, items, payroll_batches!inner(month, platform)',
        )
        .eq('status', 'finalized')
        .eq('payroll_batches.month', monthKey)
        .order('rider_name', ascending: true);
    return List<Map<String, dynamic>>.from(
      (response as List).map((row) => Map<String, dynamic>.from(row as Map)),
    );
  }

  @override
  void initState() {
    super.initState();
    context.read<ReportBloc>().add(LoadMonthlyReport(DateTime.now()));
  }

  Future<void> _selectMonth(DateTime currentMonth) async {
    final DateTime? picked = await showDatePicker(
      context: this.context,
      initialDate: currentMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: 'Select Report Month',
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null && picked != currentMonth) {
      if (!mounted) return;
      this.context.read<ReportBloc>().add(LoadMonthlyReport(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 700;
          final pad = isNarrow ? 16.0 : 32.0;
          return SingleChildScrollView(
            padding: EdgeInsets.all(pad),
            child: BlocBuilder<ReportBloc, ReportState>(
              builder: (context, state) {
                if (state is ReportLoading) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: 100),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                if (state is ReportLoaded) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(context, isNarrow, state),
                      const SizedBox(height: 32),
                      _buildSummaryCards(context, state.report, isNarrow),
                      const SizedBox(height: 24),
                      _buildExtraEarningsSection(context, state.report),
                      const SizedBox(height: 32),
                      if (isNarrow) ...[
                        _buildExpenseBreakdown(context, state.report),
                        const SizedBox(height: 24),
                        _buildNonRecoverableSection(context, state.report),
                        const SizedBox(height: 24),
                        _buildRecoverySection(context, state.report),
                      ] else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 2,
                              child: _buildExpenseBreakdown(context, state.report),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              flex: 1,
                              child: Column(
                                children: [
                                  _buildNonRecoverableSection(context, state.report),
                                  const SizedBox(height: 24),
                                  _buildRecoverySection(context, state.report),
                                ],
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 32),
                      _buildAgingReport(context, state.report),
                      const SizedBox(height: 32),
                      _buildRecentDeductions(context, state.report),
                    ],
                  );
                }
                if (state is ReportError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 100),
                      child: Column(
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: Colors.red),
                          const SizedBox(height: 16),
                          Text('Error: ${state.message}'),
                          TextButton(
                            onPressed: () => context
                                .read<ReportBloc>()
                                .add(LoadMonthlyReport(DateTime.now())),
                            child: const Text('Try Again'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return const SizedBox();
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isNarrow, ReportLoaded state) {
    final monthStr = DateFormat('MMMM yyyy').format(state.month);
    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Financial Overview",
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _selectMonth(state.month),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "$monthStr • Total Cash Flow",
                  style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF64748B)),
                ),
                const Icon(Icons.arrow_drop_down, color: Color(0xFF64748B)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => _exportDetailedCSV(context, state),
            icon: const Icon(Icons.download, size: 18),
            label: Text(
              "Export CSV",
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF15803D),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Financial Overview",
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                InkWell(
                  onTap: () => _selectMonth(state.month),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      children: [
                        Text(
                          "$monthStr • Total Cash Flow",
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                        const Icon(Icons.calendar_month, size: 16, color: Color(0xFF64748B)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: () => context
                      .read<ReportBloc>()
                      .add(LoadMonthlyReport(state.month)),
                  icon: const Icon(Icons.refresh, size: 20, color: Color(0xFF15803D)),
                  tooltip: 'Refresh Reports',
                ),
              ],
            ),
          ],
        ),
        ElevatedButton.icon(
          onPressed: () => _exportDetailedCSV(context, state),
          icon: const Icon(Icons.download),
          label: Text("Export CSV", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF15803D),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCards(
    BuildContext context,
    FinancialReportModel report,
    bool isNarrow,
  ) {
    final cards = [
      _SummaryCard(
        title: "Total Revenue",
        value: "AED ${NumberFormat('#,##0').format(report.totalRevenue)}",
        color: const Color(0xFF10B981),
        icon: Icons.attach_money,
      ),
      _SummaryCard(
        title: "Total Net Pay",
        value: "AED ${NumberFormat('#,##0').format(report.totalNetPay)}",
        color: const Color(0xFFEF4444),
        icon: Icons.payments,
        isNegative: true,
      ),
      _SummaryCard(
        title: "Company Expenses",
        value: "AED ${NumberFormat('#,##0').format(report.totalCompanyExpense)}",
        color: const Color(0xFFF97316),
        icon: Icons.money_off,
        isNegative: true,
      ),
      _SummaryCard(
        title: "Net Profit",
        value: "AED ${NumberFormat('#,##0').format(report.netProfit)}",
        color: const Color(0xFF1E293B),
        icon: Icons.account_balance_wallet,
        isBold: true,
        helperText: "Rev - Net Pay - Company Exp",
      ),
    ];
    if (isNarrow) {
      return Column(
        children: cards
            .map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(width: double.infinity, child: c),
                ))
            .toList(),
      );
    }
    return Row(
      children: [
        cards[0],
        const SizedBox(width: 16),
        cards[1],
        const SizedBox(width: 16),
        cards[2],
        const SizedBox(width: 16),
        cards[3],
      ],
    );
  }

  Widget _buildExpenseBreakdown(BuildContext context, FinancialReportModel report) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Expense Breakdown by Category",
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 24),
          ...report.expenseBreakdown.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        item.categoryName,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      Text(
                        "AED ${NumberFormat('#,##0').format(item.amount)}",
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: report.totalExpense > 0
                          ? item.amount / report.totalExpense
                          : 0.0,
                      backgroundColor: const Color(0xFFF1F5F9),
                      color: item.color,
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExtraEarningsSection(BuildContext context, FinancialReportModel report) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Earnings Breakdown (All Riders)',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Totals from all finalized non-deduction earning items (bonus, tips, arrears, etc.).',
            style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),
          _metricLine(
            label: 'Total Extra Earnings',
            value: report.extraEarningsTotal,
            color: const Color(0xFF6D28D9),
          ),
          if (report.extraEarningsBreakdown.isNotEmpty) ...[
            const SizedBox(height: 14),
            ...report.extraEarningsBreakdown.map((item) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _metricLine(
                  label: item.categoryName,
                  value: item.amount,
                  color: const Color(0xFF334155),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildRecoverySection(BuildContext context, FinancialReportModel report) {
    final recoverableRatio = report.totalRevenue > 0
        ? (report.recoverableOutstanding / report.totalRevenue * 100)
        : 0.0;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Recoverable Section",
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFDCFCE7)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFF166534)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Fines and receivable expenses are tracked here from posted journals.",
                    style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF14532D)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _metricLine(label: 'Fines', value: report.recoverableFines, color: const Color(0xFFB45309)),
          const SizedBox(height: 10),
          _metricLine(label: 'Expenses', value: report.recoverableJournals, color: const Color(0xFF0EA5E9)),
          const SizedBox(height: 10),
          _metricLine(label: 'Outstanding', value: report.recoverableOutstanding, color: const Color(0xFF1E293B)),
          const SizedBox(height: 10),
          _metricLine(label: 'Collected (This Period)', value: report.recoverableCollected, color: const Color(0xFF15803D)),
          const SizedBox(height: 10),
          _metricLine(label: 'Total Recoverable', value: report.recoverableAmount, color: const Color(0xFF0F766E)),
          const SizedBox(height: 8),
          Text(
            "${recoverableRatio.toStringAsFixed(1)}% of Revenue is currently outstanding recoverable",
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: const Color(0xFF10B981),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNonRecoverableSection(BuildContext context, FinancialReportModel report) {
    final nonRecoverable = report.nonRecoverableExpense;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Non-Recoverable (P&L Impact)',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Vendor and business costs reduce profit immediately.',
            style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),
          _metricLine(
            label: 'Non-Recoverable Expenses',
            value: nonRecoverable,
            color: const Color(0xFFB91C1C),
          ),
        ],
      ),
    );
  }

  Widget _metricLine({
    required String label,
    required double value,
    required Color color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'AED ${NumberFormat('#,##0').format(value)}',
          style: GoogleFonts.poppins(
            fontSize: 16,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildAgingReport(BuildContext context, FinancialReportModel report) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Aging Report",
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),
          const Center(child: Text("No aging data available.")),
        ],
      ),
    );
  }

  Widget _buildRecentDeductions(BuildContext context, FinancialReportModel report) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Real-time Deductions (Last 30 Days)",
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (report.realTimeDeductions.isEmpty)
                const Center(child: Text("No real-time deductions recorded.")),
              if (report.realTimeDeductions.isNotEmpty)
                ...report.realTimeDeductions.map((d) {
                  final label = d['label']?.toString() ?? '';
                  final amount = d['amount'] is num
                      ? (d['amount'] as num).toDouble()
                      : double.tryParse(d['amount']?.toString() ?? '') ?? 0.0;
                  final date = d['date']?.toString() ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Icon(Icons.flash_on, color: Colors.orange.shade400, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label,
                                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                              if (date.isNotEmpty)
                                Text(date,
                                    style: GoogleFonts.poppins(
                                        fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ),
                        Text(
                          "AED ${NumberFormat('#,##0.00').format(amount)}",
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                  );
                }),
              const Divider(height: 32),
              Text(
                "Monthly Deductions Breakdown",
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              ...report.deductions.map((d) {
                final index = report.deductions.indexOf(d);
                return Column(
                  children: [
                    _DeductionRow(
                      label: d.label,
                      amount: d.amount,
                      count: d.count,
                      color: d.color,
                    ),
                    if (index < report.deductions.length - 1) const Divider(height: 24),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _exportDetailedCSV(BuildContext context, ReportLoaded state) async {
    final riderPayslips = await _fetchRiderPayslipsForMonth(state.month);
    final rows = <List<dynamic>>[];

    final earningLabelByKey = <String, String>{};
    final deductionLabelByKey = <String, String>{};

    for (final p in riderPayslips) {
      final rawItems = p['items'];
      if (rawItems is! List) continue;
      for (final rawItem in rawItems) {
        if (rawItem is! Map) continue;
        final item = Map<String, dynamic>.from(rawItem);
        final cleanedLabel = _cleanLabel((item['label'] ?? '').toString());
        if (cleanedLabel.isEmpty) continue;
        final labelKey = _normalizeLabelKey(cleanedLabel);
        final type = (item['type'] ?? '').toString();
        if (_isDeductionType(type)) {
          deductionLabelByKey.putIfAbsent(labelKey, () => cleanedLabel);
        } else {
          earningLabelByKey.putIfAbsent(labelKey, () => cleanedLabel);
        }
      }
    }

    final sortedEarningKeys = earningLabelByKey.keys.toList()
      ..sort((a, b) => _csvDisplayLabel(earningLabelByKey[a] ?? '')
          .compareTo(_csvDisplayLabel(earningLabelByKey[b] ?? '')));
    final sortedDeductionKeys = deductionLabelByKey.keys.toList()
      ..sort((a, b) => _csvDisplayLabel(deductionLabelByKey[a] ?? '')
          .compareTo(_csvDisplayLabel(deductionLabelByKey[b] ?? '')));

    final loanDeductionKeys = sortedDeductionKeys
        .where((key) => _isLoanLabel(deductionLabelByKey[key] ?? ''))
        .toList();
    final expenseDeductionKeys = sortedDeductionKeys
        .where((key) => !loanDeductionKeys.contains(key))
        .toList();

    final payslipHeader = <dynamic>[
      'Sr No',
      'Rider Name',
      'External ID',
      'Platform',
      'Payroll Month',
      'Gross Salary',
      'Total Expense Deductions',
      'Total Loan Deductions',
      'Total Deductions',
      'Net Salary',
      ...sortedEarningKeys
          .map((k) => 'Earning: ${_csvDisplayLabel(earningLabelByKey[k] ?? '')}'),
      ...expenseDeductionKeys
          .map((k) => 'Expense: ${_csvDisplayLabel(deductionLabelByKey[k] ?? '')}'),
      ...loanDeductionKeys
          .map((k) => 'Loan: ${_csvDisplayLabel(deductionLabelByKey[k] ?? '')}'),
    ];
    rows.add(payslipHeader);

    for (var i = 0; i < riderPayslips.length; i++) {
      final p = riderPayslips[i];
      final batch = p['payroll_batches'] is Map
          ? Map<String, dynamic>.from(p['payroll_batches'] as Map)
          : <String, dynamic>{};
      final rawItems = p['items'] is List ? (p['items'] as List) : const [];
      final itemAmountByLabelKey = <String, double>{};

      for (final rawItem in rawItems) {
        if (rawItem is! Map) continue;
        final item = Map<String, dynamic>.from(rawItem);
        final cleanedLabel = _cleanLabel((item['label'] ?? '').toString());
        if (cleanedLabel.isEmpty) continue;
        final labelKey = _normalizeLabelKey(cleanedLabel);
        itemAmountByLabelKey[labelKey] =
            (itemAmountByLabelKey[labelKey] ?? 0.0) + _toDouble(item['amount']);
      }

      final grossSalary = _toDouble(p['gross_salary']);
      final netSalary = _toDouble(p['net_salary']);

      double totalDeductions = 0.0;
      double totalExpenseDeductions = 0.0;
      double totalLoanDeductions = 0.0;

      for (final rawItem in rawItems) {
        if (rawItem is! Map) continue;
        final item = Map<String, dynamic>.from(rawItem);
        final type = (item['type'] ?? '').toString();
        if (_isDeductionType(type)) {
          final amount = _toDouble(item['amount']).abs();
          final label = _cleanLabel((item['label'] ?? '').toString());
          totalDeductions += amount;
          if (_isLoanLabel(label)) {
            totalLoanDeductions += amount;
          } else {
            totalExpenseDeductions += amount;
          }
        }
      }

      if (totalDeductions == 0.0 && grossSalary >= netSalary) {
        totalDeductions = grossSalary - netSalary;
        totalExpenseDeductions = totalDeductions;
        totalLoanDeductions = 0.0;
      }

      rows.add([
        i + 1,
        (p['rider_name'] ?? '').toString(),
        (p['external_id'] ?? '').toString(),
        (batch['platform'] ?? '').toString(),
        (batch['month'] ?? '').toString(),
        grossSalary,
        totalExpenseDeductions,
        totalLoanDeductions,
        totalDeductions,
        netSalary,
        ...sortedEarningKeys.map((k) => itemAmountByLabelKey[k] ?? 0.0),
        ...expenseDeductionKeys.map((k) => itemAmountByLabelKey[k] ?? 0.0),
        ...loanDeductionKeys.map((k) => itemAmountByLabelKey[k] ?? 0.0),
      ]);
    }

    final csvContent = _rowsToCsv(rows);
    final monthStr = DateFormat('yyyy-MM').format(state.month);
    final fileName = 'payroll_report_$monthStr.csv';

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save CSV Report',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result != null) {
      final file = File(result);
      await file.writeAsString(csvContent);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported to $result')),
        );
      }
    }
  }

  String _rowsToCsv(List<List<dynamic>> rows) {
    return rows.map((row) => row.map(_csvEscape).join(',')).join('\n');
  }

  String _csvEscape(dynamic value) {
    final raw = value?.toString() ?? '';
    final escaped = raw.replaceAll('"', '""');
    final needsQuotes = escaped.contains(',') ||
        escaped.contains('"') ||
        escaped.contains('\n') ||
        escaped.contains('\r');
    return needsQuotes ? '"$escaped"' : escaped;
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;
  final bool isNegative;
  final bool isBold;
  final String? helperText;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
    this.isNegative = false,
    this.isBold = false,
    this.helperText,
  });

  @override
  Widget build(BuildContext context) {
    final isInRow = context.findAncestorWidgetOfExactType<Row>() != null;
    final card = Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              isNegative ? "- $value" : "+ $value",
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                color: isBold ? Colors.black : color,
              ),
            ),
          ),
          if (helperText != null && helperText!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              helperText!,
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
    return isInRow ? Expanded(child: card) : card;
  }
}

class _DeductionRow extends StatelessWidget {
  final String label;
  final double amount;
  final int count;
  final Color color;

  const _DeductionRow({
    required this.label,
    required this.amount,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.receipt_long, color: color, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1E293B),
                ),
              ),
              Text(
                "$count transactions",
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
        Text(
          "AED ${NumberFormat('#,##0.00').format(amount)}",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: const Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }
}