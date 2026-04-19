import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/app_theme.dart';
import '../../data/repositories/ledger_repository.dart';
import 'package:provider/provider.dart';
import '../../utils/user_friendly_error.dart';

class RiderStatementPage extends StatefulWidget {
  final String riderId;
  final String riderName;

  const RiderStatementPage({
    super.key,
    required this.riderId,
    required this.riderName,
  });

  @override
  State<RiderStatementPage> createState() => _RiderStatementPageState();
}

class _RiderStatementPageState extends State<RiderStatementPage> {
  List<dynamic> _statement = [];
  Map<String, dynamic> _summary = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStatement();
  }

  Future<void> _loadStatement() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final repo = context.read<LedgerRepository>();
      final data = await repo.fetchRiderStatement(widget.riderId);
      final summary = await repo.fetchRiderStatementSummary(widget.riderId);
      if (mounted) {
        setState(() {
          _statement = data;
          _summary = summary;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = toUserFriendlyError(e);
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          "Statement: ${widget.riderName}",
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStatement,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _statement.isEmpty
          ? const Center(child: Text("No transactions found for this rider"))
          : Column(
              children: [
                _buildSummaryHeader(),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: _statement.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = _statement[index];
                      return _buildTransactionRow(item);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSummaryHeader() {
    final totals = _summary['totals'] as Map<String, dynamic>?;

    double totalEarned = (totals?['debit'] as num?)?.toDouble() ?? 0;
    double totalDeducted = (totals?['credit'] as num?)?.toDouble() ?? 0;

    if (totalEarned == 0 && totalDeducted == 0 && _statement.isNotEmpty) {
      for (var item in _statement) {
        final double debit = (item['debit_amount'] as num?)?.toDouble() ?? 0;
        final double credit = (item['credit_amount'] as num?)?.toDouble() ?? 0;
        if (debit > 0) totalEarned += debit;
        if (credit > 0) totalDeducted += credit;
      }
    }

    return Container(
      padding: const EdgeInsets.all(24),
      color: Colors.white,
      child: Row(
        children: [
          _buildSummaryItem("Total Earnings", totalEarned, Colors.green),
          const SizedBox(width: 24),
          _buildSummaryItem("Total Deductions", totalDeducted, Colors.red),
          const SizedBox(width: 24),
          _buildSummaryItem(
            "Net Balance",
            totalEarned - totalDeducted,
            AppTheme.primaryColor,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, double value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "AED ${NumberFormat('#,##0.00').format(value)}",
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionRow(Map<String, dynamic> item) {
    final dateStr = item['entry_date'] as String;
    final date = DateTime.parse(dateStr);
    final description = item['description'] ?? "No description";
    final debit = (item['debit_amount'] as num?)?.toDouble() ?? 0;
    final credit = (item['credit_amount'] as num?)?.toDouble() ?? 0;
    final isEarning = debit > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('MMM dd, yyyy').format(date),
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            isEarning
                ? "+ AED ${NumberFormat('#,##0.00').format(debit)}"
                : "- AED ${NumberFormat('#,##0.00').format(credit)}",
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              color: isEarning ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
    );
  }
}
