import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/app_theme.dart';
import '../../logic/riders/riders_bloc.dart';
import '../../logic/payroll/payroll_bloc.dart';
import '../../logic/financial/ledger_bloc.dart';
import '../../data/models/rider_model.dart';
import '../../data/models/payroll_model.dart';
import '../widgets/pro_submitted_riders_section.dart';

class ProDashboard extends StatelessWidget {
  const ProDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 700;
          final pad = isNarrow ? 16.0 : 28.0;

          return BlocBuilder<RidersBloc, RidersState>(
            builder: (context, ridersState) {
              final payrollState = context.watch<PayrollBloc>().state;
              final ledgerState = context.watch<LedgerBloc>().state;

              // Gather stats
              int totalRiders = 0;
              int activeRiders = 0;
              int vacationRiders = 0;
              if (ridersState is RidersLoaded) {
                totalRiders = ridersState.allRiders.length;
                activeRiders = ridersState.allRiders
                    .where((r) => r.status == RiderStatus.active)
                    .length;
                vacationRiders = ridersState.allRiders
                    .where((r) => r.status == RiderStatus.vacation)
                    .length;
              }

              int payrollBatches = payrollState.history.length;
              int pendingBatches = payrollState.history
                  .where((b) => b.status != PayrollBatchStatus.finalized)
                  .length;

              double totalDebit = 0;
              double totalCredit = 0;
              if (ledgerState is LedgerLoaded) {
                totalDebit = ledgerState.totalDebit;
                totalCredit = ledgerState.totalCredit;
              }

              return SingleChildScrollView(
                padding: EdgeInsets.all(pad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "PRO Overview",
                              style: TextStyle(
                                fontSize: isNarrow ? 20 : 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Company-wide operational snapshot",
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () {
                            context.read<RidersBloc>().add(LoadRiders());
                            context.read<PayrollBloc>().add(LoadPayrollHistory());
                            context.read<LedgerBloc>().add(const LoadLedger());
                          },
                          icon: const Icon(Icons.refresh, color: AppTheme.primaryColor),
                          tooltip: 'Refresh Dashboard',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Rider stats strip
                    _buildStatsGrid(
                      isNarrow: isNarrow,
                      items: [
                        _Stat("Total Riders", totalRiders.toString(),
                            Icons.groups, AppTheme.primaryColor),
                        _Stat("Active", activeRiders.toString(),
                            Icons.check_circle, Colors.green),
                        _Stat("On Vacation", vacationRiders.toString(),
                            Icons.beach_access, Colors.orange),
                        _Stat("Payroll Batches", payrollBatches.toString(),
                            Icons.receipt_long, Colors.blue),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Financial cards row
                    _buildFinancialCards(
                      isNarrow: isNarrow,
                      totalDebit: totalDebit,
                      totalCredit: totalCredit,
                      pendingBatches: pendingBatches,
                    ),
                    const SizedBox(height: 24),

                    // Recent payroll batches
                    _buildRecentBatches(payrollState.history),
                    const ProSubmittedRidersSection(),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStatsGrid({
    required bool isNarrow,
    required List<_Stat> items,
  }) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isNarrow ? 2 : 4,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: isNarrow ? 1.8 : 2.2,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final s = items[i];
        return Card(
          elevation: 0,
          color: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: s.color.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(s.icon, size: 18, color: s.color),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        s.label,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    s.value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFinancialCards({
    required bool isNarrow,
    required double totalDebit,
    required double totalCredit,
    required int pendingBatches,
  }) {
    final net = totalDebit - totalCredit;
    final cards = <Widget>[
      _financialTile("Total Debit", totalDebit, Colors.red[700]!),
      _financialTile("Total Credit", totalCredit, Colors.green[700]!),
      _financialTile("Net Position", net, AppTheme.primaryColor),
      _financialTile(
          "Pending Payroll", pendingBatches.toDouble(), Colors.orange),
    ];
    if (isNarrow) {
      return GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 2.2,
        children: cards,
      );
    }
    return Row(
      children: cards
          .map((c) => Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: c,
              )))
          .toList(),
    );
  }

  Widget _financialTile(String label, double value, Color accent) {
    final formatted = value >= 1000
        ? 'AED ${(value / 1000).toStringAsFixed(1)}K'
        : value == value.roundToDouble()
            ? value.toStringAsFixed(0)
            : 'AED ${value.toStringAsFixed(0)}';
    return Card(
      elevation: 0,
      color: accent.withValues(alpha: 0.07),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatted,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentBatches(List<PayrollBatchModel> batches) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Recent Payroll Activity",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (batches.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text("No payroll data yet.",
                    style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ...batches.take(10).map((b) => _batchTile(b)),
        ],
      ),
    );
  }

  Widget _batchTile(PayrollBatchModel batch) {
    final isFinal = batch.status == PayrollBatchStatus.finalized;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black12)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: isFinal
                ? Colors.green.withValues(alpha: 0.1)
                : Colors.orange.withValues(alpha: 0.1),
            child: Icon(
              isFinal ? Icons.check_circle : Icons.hourglass_empty,
              color: isFinal ? Colors.green : Colors.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${batch.platform} - ${batch.month.month}/${batch.month.year}",
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  batch.status.name,
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isFinal
                  ? Colors.green.withValues(alpha: 0.1)
                  : Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              batch.status.name,
              style: TextStyle(
                color: isFinal ? Colors.green : Colors.orange,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _Stat(this.label, this.value, this.icon, this.color);
}
