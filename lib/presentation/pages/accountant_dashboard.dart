import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../logic/payroll/payroll_bloc.dart';
import '../../data/models/payroll_model.dart';
import '../../data/models/rider_model.dart';
import '../../logic/riders/riders_bloc.dart';
import '../../logic/financial/ledger_bloc.dart';
import 'package:go_router/go_router.dart';
import '../widgets/accountant_pending_approvals_section.dart';

class AccountantDashboard extends StatelessWidget {
  const AccountantDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PayrollBloc, PayrollState>(
      builder: (context, payrollState) {
        // Pull live data from Blocs
        final ridersState = context.watch<RidersBloc>().state;
        final ledgerState = context.watch<LedgerBloc>().state;

        int activeRiders = 0;
        if (ridersState is RidersLoaded) {
          activeRiders = ridersState.riders
              .where((r) => r.status == RiderStatus.active)
              .length;
        }

        double totalDebit = 0;
        double totalCredit = 0;
        if (ledgerState is LedgerLoaded) {
          totalDebit = ledgerState.totalDebit;
          totalCredit = ledgerState.totalCredit;
        }

        final netPosition = totalDebit - totalCredit;
        final pendingBatches = payrollState.history
            .where((b) => b.status != PayrollBatchStatus.finalized)
            .length;

        final metrics = [
          _MetricData(
            title: "Total Debit",
            amount: "AED ${_fmt(totalDebit)}",
            icon: Icons.account_balance_wallet,
            isHighlight: true,
          ),
          _MetricData(
            title: "Active Riders",
            amount: activeRiders.toString(),
            icon: Icons.people,
          ),
          _MetricData(
            title: "Pending Batches",
            amount: pendingBatches.toString(),
            icon: Icons.pending_actions,
          ),
          _MetricData(
            title: "Net Position",
            amount: "AED ${_fmt(netPosition)}",
            icon: Icons.account_balance,
          ),
        ];

        final requests = payrollState.history;

        return Scaffold(
          backgroundColor: AppTheme.scaffoldBackgroundColor,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 700;
              final horizontalPad = isNarrow ? 16.0 : 28.0;

              return SingleChildScrollView(
                padding: EdgeInsets.all(horizontalPad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Bar
                    _buildTopBar(context, isNarrow),
                    const SizedBox(height: 24),

                    // Metrics — responsive grid
                    _buildMetricsGrid(metrics, constraints.maxWidth),
                    const SizedBox(height: 24),

                    const _RiderComplianceSnapshot(),
                    const SizedBox(height: 24),

                    // Recent Payroll Batches
                    _buildPayrollList(requests),
                    const SizedBox(height: 24),

                    // Pending Riders Section
                    const AccountantPendingApprovalsSection(),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  static String _fmt(double v) {
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(1)}K';
    }
    return v.toStringAsFixed(0);
  }

  Widget _buildTopBar(BuildContext context, bool isNarrow) {
    if (isNarrow) {
      return const Text(
        "Financial Overview",
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          "Financial Overview",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        Row(
          children: [
            IconButton(
              onPressed: () {
                context.read<PayrollBloc>().add(LoadPayrollHistory());
                context.read<RidersBloc>().add(LoadRiders());
                context.read<LedgerBloc>().add(const LoadLedger());
              },
              icon: const Icon(Icons.refresh, color: AppTheme.primaryColor),
              tooltip: "Refresh Dashboard",
            ),
            const SizedBox(width: 8),
            const CircleAvatar(
              backgroundColor: AppTheme.primaryColor,
              radius: 18,
              child: Text("A", style: TextStyle(color: Colors.white)),
            ),
            const SizedBox(width: 12),
            const Text("Accountant", style: TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricsGrid(List<_MetricData> metrics, double width) {
    // 2 columns when narrow, 4 when wide
    final crossAxisCount = width < 700 ? 2 : 4;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: crossAxisCount == 2 ? 2.2 : 2.0,
      ),
      itemCount: metrics.length,
      itemBuilder: (context, i) {
        final m = metrics[i];
        return _ResponsiveMetricCard(
          title: m.title,
          amount: m.amount,
          icon: m.icon,
          isHighlight: m.isHighlight,
          onTap: () {
            if (m.title.contains("Debit") || m.title.contains("Position")) {
              context.push('/ledger');
            } else if (m.title.contains("Riders")) {
              context.push('/riders');
            } else if (m.title.contains("Batches")) {
              context.push('/payroll');
            }
          },
        );
      },
    );
  }

  Widget _buildPayrollList(List<PayrollBatchModel> requests) {
    return Container(
      constraints: const BoxConstraints(minHeight: 200),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Recent Payroll Batches",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (requests.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  "No payroll batches yet.",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            ...requests.map((batch) => _buildBatchRow(batch)),
        ],
      ),
    );
  }

  Widget _buildBatchRow(PayrollBatchModel batch) {
    final isFinal = batch.status == PayrollBatchStatus.finalized;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black12)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.grey[200],
            child: Icon(Icons.receipt_long, color: Colors.grey[600]),
          ),
          const SizedBox(width: 16),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          const SizedBox(width: 12),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
    );
  }

}

class _MetricData {
  final String title;
  final String amount;
  final IconData icon;
  final bool isHighlight;
  const _MetricData({
    required this.title,
    required this.amount,
    required this.icon,
    this.isHighlight = false,
  });
}

class _ResponsiveMetricCard extends StatelessWidget {
  final String title;
  final String amount;
  final IconData icon;
  final bool isHighlight;
  final VoidCallback? onTap;

  const _ResponsiveMetricCard({
    required this.title,
    required this.amount,
    required this.icon,
    this.isHighlight = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: isHighlight ? AppTheme.primaryColor : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: isHighlight ? Colors.white70 : Colors.grey[600],
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isHighlight
                          ? Colors.white.withValues(alpha: 0.1)
                          : AppTheme.primaryColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      color: isHighlight ? Colors.white : AppTheme.primaryColor,
                      size: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  amount,
                  style: TextStyle(
                    color: isHighlight ? Colors.white : Colors.black87,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RiderComplianceSnapshot extends StatefulWidget {
  const _RiderComplianceSnapshot();

  @override
  State<_RiderComplianceSnapshot> createState() => _RiderComplianceSnapshotState();
}

class _RiderComplianceSnapshotState extends State<_RiderComplianceSnapshot> {
  bool _loading = true;
  String _latestTransition = 'No transitions yet';
  bool _hasHistoryTransition = false;

  @override
  void initState() {
    super.initState();
    _loadLatestTransition();
  }

  Future<void> _loadLatestTransition() async {
    try {
      final data = await Supabase.instance.client
          .from('rider_status_history')
          .select('new_status, changed_at, rider_id, riders(name)')
          .order('changed_at', ascending: false)
          .limit(1);

      if (!mounted) return;

      if (data.isNotEmpty) {
        final latest = data.first;
        final rider = latest['riders'];
        final riderName = rider is Map<String, dynamic>
            ? (rider['name']?.toString() ?? 'Rider')
            : 'Rider';
        final status = latest['new_status']?.toString() ?? 'unknown';
        final changedAt = latest['changed_at']?.toString();
        final ts = changedAt != null ? DateTime.tryParse(changedAt) : null;
        final when = ts != null
            ? '${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')}'
            : 'unknown date';

        setState(() {
          _latestTransition = '$riderName -> $status ($when)';
          _hasHistoryTransition = true;
          _loading = false;
        });
      } else {
        setState(() {
          _latestTransition = 'No transitions yet';
          _hasHistoryTransition = false;
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _latestTransition = 'Unavailable';
        _hasHistoryTransition = false;
        _loading = false;
      });
    }
  }

  int _daysTo(DateTime? date) {
    if (date == null) return 9999;
    final now = DateTime.now();
    return date.difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  void _openExpiringDetailsDialog(List<Map<String, dynamic>> rows) {
    String filter = 'all';

    List<Map<String, dynamic>> applyFilter() {
      if (filter == 'overdue') {
        return rows.where((r) => (r['days'] as int) < 0).toList();
      }
      if (filter == '7d') {
        return rows.where((r) {
          final d = r['days'] as int;
          return d >= 0 && d <= 7;
        }).toList();
      }
      if (filter == '30d') {
        return rows.where((r) {
          final d = r['days'] as int;
          return d >= 0 && d <= 30;
        }).toList();
      }
      return List<Map<String, dynamic>>.from(rows);
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = applyFilter();
            return AlertDialog(
              title: const Text('Expiring Rider Documents'),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('All'),
                          selected: filter == 'all',
                          onSelected: (_) => setDialogState(() => filter = 'all'),
                        ),
                        ChoiceChip(
                          label: const Text('Overdue'),
                          selected: filter == 'overdue',
                          onSelected: (_) => setDialogState(() => filter = 'overdue'),
                        ),
                        ChoiceChip(
                          label: const Text('Next 7 days'),
                          selected: filter == '7d',
                          onSelected: (_) => setDialogState(() => filter = '7d'),
                        ),
                        ChoiceChip(
                          label: const Text('Next 30 days'),
                          selected: filter == '30d',
                          onSelected: (_) => setDialogState(() => filter = '30d'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (filtered.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No riders in selected filter.'),
                      )
                    else
                      SizedBox(
                        height: 320,
                        child: ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final row = filtered[i];
                            final days = row['days'] as int;
                            final whenText = days < 0 ? '${days.abs()}d overdue' : 'in ${days}d';
                            return ListTile(
                              dense: true,
                              title: Text('${row['riderName']} - ${row['docType']}'),
                              subtitle: Text('Expiry: ${row['expiryDate'] ?? '-'}'),
                              trailing: Text(
                                whenText,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: days < 0 ? Colors.red : Colors.orange,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ridersState = context.watch<RidersBloc>().state;

    int expiringDocs = 0;
    int onHold = 0;
    final expiringDetails = <Map<String, dynamic>>[];
    final nonActiveRiders = <String>[];

    if (ridersState is RidersLoaded) {
      for (final r in ridersState.riders) {
        if (r.status != RiderStatus.active) {
          nonActiveRiders.add('${r.name} (${r.status.name})');
        }

        if ((r.releaseHold ?? '').toLowerCase() == 'hold') {
          onHold += 1;
        }

        final docs = [
          {'type': 'Passport', 'value': r.passportExpiryDate},
          {'type': 'Emirates ID', 'value': r.emiratesIdExpiryDate},
        ];

        for (final d in docs) {
          final raw = d['value']?.toString();
          final dt = raw != null ? DateTime.tryParse(raw) : null;
          final days = _daysTo(dt);
          if (days <= 30) {
            expiringDocs += 1;
            expiringDetails.add({
              'riderName': r.name,
              'docType': d['type'],
              'expiryDate': raw,
              'days': days,
            });
          }
        }
      }
    }

    expiringDetails.sort((a, b) => (a['days'] as int).compareTo(b['days'] as int));
    final displayExpiring = expiringDetails.take(5).toList();

    final latestTransitionText = !_loading && !_hasHistoryTransition && nonActiveRiders.isNotEmpty
        ? 'Current non-active riders: ${nonActiveRiders.take(3).join(', ')}'
        : _latestTransition;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Rider Compliance Snapshot',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _statChip('Passport/EID expiring <=30d', expiringDocs.toString(), Colors.orange),
              _statChip('Riders on hold', onHold.toString(), Colors.red),
            ],
          ),
          if (displayExpiring.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Expiring riders (top 5)',
                  style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                ),
                TextButton(
                  onPressed: () => _openExpiringDetailsDialog(expiringDetails),
                  child: const Text('View all'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...displayExpiring.map((row) {
              final days = row['days'] as int;
              final whenText = days < 0 ? '${days.abs()}d overdue' : 'in ${days}d';
              final date = row['expiryDate']?.toString() ?? '-';
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${row['riderName']} - ${row['docType']} $whenText ($date)',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                ),
              );
            }),
          ],
          const SizedBox(height: 14),
          Text(
            _loading ? 'Loading latest status transition...' : 'Latest status transition: $latestTransitionText',
            style: const TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Color(0xFF0F172A), fontFamily: 'Roboto'),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
            TextSpan(text: value, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
