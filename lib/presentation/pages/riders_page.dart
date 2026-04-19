import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../../core/app_theme.dart';
import '../../data/models/rider_model.dart';
import '../../logic/riders/riders_bloc.dart';
import '../../logic/auth/auth_bloc.dart';
import '../../data/models/user_model.dart';
import '../../services/api_service.dart';
import '../../utils/user_friendly_error.dart';
import 'rider_form_screen.dart';

class RidersPage extends StatefulWidget {
  const RidersPage({super.key});

  @override
  State<RidersPage> createState() => _RidersPageState();
}

class _RidersPageState extends State<RidersPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (context.read<RidersBloc>().state is! RidersLoaded) {
      context.read<RidersBloc>().add(LoadRiders());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showRiderForm([RiderModel? rider]) {
    final authState = context.read<AuthBloc>().state;
    final isAccountant = authState is AuthAuthenticated && authState.user.role == UserRole.accountant;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => RiderFormScreen(rider: rider, isAccountantCreate: isAccountant),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA), // Light Grey background
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 700;
          final pad = isNarrow ? 16.0 : 28.0;
          return Padding(
            padding: EdgeInsets.all(pad),
            child: Column(
              children: [
                // Header Title & Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        "Rider Management",
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1E293B), // Dark text
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            context.read<RidersBloc>().add(LoadRiders());
                          },
                          icon: const Icon(Icons.refresh),
                          tooltip: "Refresh Riders",
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () async {
                            try {
                              FilePickerResult? result = await FilePicker
                                  .platform
                                  .pickFiles(
                                    type: FileType.custom,
                                    allowedExtensions: ['xlsx', 'xls', 'csv'],
                                  );

                              if (result != null &&
                                  result.files.single.path != null) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Processing Riders...'),
                                    ),
                                  );

                                  final file = File(result.files.single.path!);
                                  // Dispatch upload event to Bloc
                                  context.read<RidersBloc>().add(
                                        UploadRiders(file),
                                      );
                                }
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(toUserFriendlyError(e))),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.upload_file),
                          tooltip: "Upload Riders Excel",
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: () => _showRiderForm(),
                          icon: const Icon(Icons.add),
                          label: const Text("Add Rider"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                AppTheme.primaryColor, // Forest Green
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            textStyle: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Search Bar & Filter Button (Single Row)
                Row(
                  children: [
                    Expanded(
                      child: Container(
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
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText:
                                "Search Riders (Name, Phone, Passport)...",
                            hintStyle: GoogleFonts.poppins(color: Colors.grey),
                            prefixIcon: const Icon(
                              Icons.search,
                              color: AppTheme.primaryColor,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 16,
                            ),
                          ),
                          onChanged: (value) {
                            context.read<RidersBloc>().add(SearchRiders(value));
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
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
                      child: IconButton(
                        onPressed: () => _showFilterBottomSheet(context),
                        icon: const Icon(Icons.filter_list),
                        color: AppTheme.primaryColor,
                        tooltip: "Filter Riders",
                        style: IconButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Riders List
                Expanded(
                  child: BlocListener<RidersBloc, RidersState>(
                    listenWhen: (previous, current) {
                      if (current is! RidersLoaded || current.uploadMessage == null) {
                        return false;
                      }
                      if (previous is RidersLoaded) {
                        return previous.uploadMessage != current.uploadMessage ||
                            previous.isUploadSuccess != current.isUploadSuccess ||
                            previous.uploadLogs.length != current.uploadLogs.length;
                      }
                      return true;
                    },
                    listener: (context, state) {
                      if (state is! RidersLoaded || state.uploadMessage == null) {
                        return;
                      }

                      final hasWarnings = state.uploadLogs.isNotEmpty;
                      final isSuccess = state.isUploadSuccess;
                      final color = isSuccess
                          ? (hasWarnings ? Colors.orange : Colors.green)
                          : Colors.red;
                      final icon = isSuccess
                          ? (hasWarnings ? Icons.warning_amber_rounded : Icons.check_circle)
                          : Icons.error_outline;

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: color,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          content: Row(
                            children: [
                              Icon(icon, color: Colors.white),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  state.uploadMessage!,
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    child: BlocBuilder<RidersBloc, RidersState>(
                      builder: (context, state) {
                        if (state is RidersLoading) {
                          return const Center(
                              child: CircularProgressIndicator());
                        } else if (state is RidersError) {
                          return Center(child: Text(state.message));
                        } else if (state is RidersLoaded) {
                          if (state.riders.isEmpty) {
                            return const Center(child: Text("No riders found."));
                          }
                          return ListView.separated(
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: state.riders.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 16),
                            itemBuilder: (context, index) {
                              final rider = state.riders[index];
                              return _buildRiderCard(context, rider);
                            },
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showFilterBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return BlocBuilder<RidersBloc, RidersState>(
          builder: (context, state) {
            if (state is! RidersLoaded) return const SizedBox.shrink();

            // Extract unique values for filters
            final cities = state.allRiders
                .map((r) => r.city)
                .where((c) => c != null && c.isNotEmpty)
                .toSet()
                .toList()
                .cast<String>();


            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Filter Riders",
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          context.read<RidersBloc>().add(
                            const FilterRiders(
                              city: null,
                              clearCity: true,
                              status: null,
                              clearStatus: true,
                            ),
                          );
                          Navigator.pop(context);
                        },
                        child: const Text("Reset All"),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Status Filter
                  Text(
                    "Status",
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: RiderStatus.values.map((status) {
                      final isSelected = state.filterStatus == status;
                      return ChoiceChip(
                        label: Text(
                          status.toString().split('.').last.toUpperCase(),
                        ),
                        selected: isSelected,
                        onSelected: (selected) {
                          context.read<RidersBloc>().add(
                            FilterRiders(
                              status: selected ? status : null,
                              clearStatus: !selected,
                            ),
                          );
                        },
                        selectedColor: AppTheme.primaryColor.withValues(
                          alpha: 0.2,
                        ),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? AppTheme.primaryColor
                              : Colors.black87,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // City Filter
                  Text(
                    "City",
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: cities.map((city) {
                      final isSelected = state.filterCity == city;
                      return ChoiceChip(
                        label: Text(city),
                        selected: isSelected,
                        onSelected: (selected) {
                          context.read<RidersBloc>().add(
                            FilterRiders(
                              city: selected ? city : null,
                              clearCity: !selected,
                            ),
                          );
                        },
                        selectedColor: AppTheme.primaryColor.withValues(
                          alpha: 0.2,
                        ),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? AppTheme.primaryColor
                              : Colors.black87,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRiderCard(BuildContext context, RiderModel rider) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _showRiderDetails(rider),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppTheme.primaryColor,
                child: Text(
                  rider.name.isNotEmpty ? rider.name[0].toUpperCase() : '?',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rider.name,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.phone, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          rider.phone ?? "-",
                          style: GoogleFonts.poppins(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                        if (rider.city != null) ...[
                          const SizedBox(width: 12),
                          const Icon(
                            Icons.location_on,
                            size: 14,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            rider.city!,
                            style: GoogleFonts.poppins(
                              color: Colors.grey[600],
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if ((rider.talabatId?.isNotEmpty == true) ||
                        (rider.keetaId?.isNotEmpty == true)) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (rider.talabatId?.isNotEmpty == true)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey.shade50,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: Colors.blueGrey.shade100),
                              ),
                              child: Text(
                                'Talabat: ${rider.talabatId}',
                                style: GoogleFonts.poppins(
                                  color: Colors.blueGrey.shade700,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          if (rider.keetaId?.isNotEmpty == true)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: Colors.green.shade100),
                              ),
                              child: Text(
                                'Keeta: ${rider.keetaId}',
                                style: GoogleFonts.poppins(
                                  color: Colors.green.shade700,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(
                  Icons.info_outline,
                  color: AppTheme.primaryColor,
                ),
                onPressed: () => _showRiderDetails(rider),
                tooltip: "View Full Details",
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRiderDetails(RiderModel rider) {
    final authState = context.read<AuthBloc>().state;
    final bool isAccountant =
        authState is AuthAuthenticated &&
        authState.user.role == UserRole.accountant;

    showDialog(
      context: context,
      builder: (context) => _RiderDetailsDialog(
        rider: rider,
        isAccountant: isAccountant,
        onEdit: () {
          Navigator.pop(context);
          _showRiderForm(rider);
        },
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
//  Rider Details Dialog  (with Alias management)
// ──────────────────────────────────────────────────────────

class _RiderDetailsDialog extends StatefulWidget {
  final RiderModel rider;
  final bool isAccountant;
  final VoidCallback onEdit;

  const _RiderDetailsDialog({
    required this.rider,
    required this.isAccountant,
    required this.onEdit,
  });

  @override
  State<_RiderDetailsDialog> createState() => _RiderDetailsDialogState();
}

class _RiderDetailsDialogState extends State<_RiderDetailsDialog> {
  bool _loadingHistory = true;
  List<dynamic> _statusHistory = [];

  @override
  void initState() {
    super.initState();
    _loadStatusHistory();
  }

  Future<void> _loadStatusHistory() async {
    try {
      final data = await ApiService.instance.getRiderStatusHistory(widget.rider.id);
      if (!mounted) return;
      setState(() {
        _statusHistory = data;
        _loadingHistory = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingHistory = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.rider.name),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Rider ID: ${widget.rider.riderCode ?? '-'}'),
              Text('Emirates ID: ${widget.rider.emiratesIdNumber ?? '-'}'),
              Text('Talabat ID: ${widget.rider.talabatId?.isNotEmpty == true ? widget.rider.talabatId : '-'}'),
              Text('Keeta ID: ${widget.rider.keetaId?.isNotEmpty == true ? widget.rider.keetaId : '-'}'),
              Text('Status: ${widget.rider.status.name}'),
              const SizedBox(height: 12),
              const Text(
                'Status History',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (_loadingHistory)
                const SizedBox(
                  height: 40,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (_statusHistory.isEmpty)
                const Text('No status changes yet')
              else
                ..._statusHistory.take(6).map((h) {
                  final oldStatus = h['old_status']?.toString() ?? '-';
                  final newStatus = h['new_status']?.toString() ?? '-';
                  final reason = h['reason']?.toString();
                  final changedAt = h['changed_at']?.toString();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '$oldStatus -> $newStatus'
                      '${reason != null && reason.isNotEmpty ? ' | $reason' : ''}'
                      '${changedAt != null ? ' | $changedAt' : ''}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.isAccountant)
          TextButton(
            onPressed: widget.onEdit,
            child: Text('Edit'),
          ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────
//  Add Alias Dialog
// ──────────────────────────────────────────────────────────

class _AddAliasDialog extends StatefulWidget {
  final String riderId;

  const _AddAliasDialog({required this.riderId});

  @override
  State<_AddAliasDialog> createState() => _AddAliasDialogState();
}

class _AddAliasDialogState extends State<_AddAliasDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add Alias'),
      content: Text('Add alias for rider ID: ${widget.riderId}'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close'),
        ),
      ],
    );
  }
}
