import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/app_theme.dart';
import '../../data/models/fines_model.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../logic/fines/fines_bloc.dart';
import '../../logic/riders/riders_bloc.dart';
import '../widgets/manual_assignment_dialog.dart';
import '../../data/models/rider_model.dart';
import '../../utils/user_friendly_error.dart';
import '../../data/repositories/fines_repository.dart';

class FinesPage extends StatefulWidget {
  final String? focusedFineId;
  const FinesPage({super.key, this.focusedFineId});

  @override
  State<FinesPage> createState() => _FinesPageState();
}

class _FinesPageState extends State<FinesPage> {
  String? _flashingFineId;
  DateTimeRange? _selectedDateRange;
  String _searchQuery = '';
  FineStatus? _filterStatus;
  List<FineModel> _allItems = [];
  List<FineModel> _filteredItems = [];
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalTableScrollController = ScrollController();

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _verticalTableScrollController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    setState(() {
      _filteredItems = _allItems.where((f) {
        if (_filterStatus != null && f.status != _filterStatus) return false;

        if (_selectedDateRange != null) {
          final date = DateUtils.dateOnly(f.violationDate.toLocal());
          final start = DateUtils.dateOnly(_selectedDateRange!.start);
          final end = DateUtils.dateOnly(_selectedDateRange!.end);
          if (date.isBefore(start) || date.isAfter(end)) return false;
        }

        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          if (!f.plateNumber.toLowerCase().contains(q) &&
              !f.ticketNumber.toLowerCase().contains(q) &&
              !(f.riderName?.toLowerCase().contains(q) ?? false)) {
            return false;
          }
        }
        return true;
      }).toList();
    });
  }

  void _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: AppTheme.primaryColor),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      _selectedDateRange = picked;
      _applyFilters();
    }
  }

  void _clearDateRange() {
    _selectedDateRange = null;
    _applyFilters();
  }

  String _getMonth(int m) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[m - 1];
  }

  @override
  void initState() {
    super.initState();
    context.read<FinesBloc>().add(LoadFines());
    if (widget.focusedFineId != null) {
      _flashingFineId = widget.focusedFineId;
    }
  }

  void _handleRefresh() {
    context.read<FinesBloc>().add(LoadFines());
  }


  void _onSearchChanged(String query) {
    _searchQuery = query;
    _applyFilters();
  }

  void _onFilterChanged(FineStatus? status) {
    _filterStatus = status;
    _applyFilters();
  }

  Future<void> _handleUpload({required bool isSalik}) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv', 'txt'],
      );

      if (result != null && result.files.single.path != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isSalik
                    ? 'Processing Salik Sheet...'
                    : 'Processing Fines Sheet...',
              ),
            ),
          );

          final file = File(result.files.single.path!);

          if (isSalik) {
            context.read<FinesBloc>().add(UploadSalikSheet(file));
          } else {
            context.read<FinesBloc>().add(UploadFinesSheet(file));
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isSalik
                      ? 'Salik upload started. This may take a moment...'
                      : 'Fines upload started. This may take a moment...',
                ),
                backgroundColor: Colors.orange,
              ),
            );
            // Wait for FinesBloc to complete parsing and call LoadFines() automatically.
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(toUserFriendlyError(e))));
      }
    }
  }

  Future<void> _showPayFinesDialog(List<String> fineIds) async {
    final drawersData = await Supabase.instance.client.from('drawer').select('id, name, balance');
    if (drawersData.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No bank accounts or drawers found.')));
      }
      return;
    }

    String? selectedDrawerId = drawersData.first['id'].toString();

    if (!mounted) return;

    bool isLoading = false;
    // Get repository from provider
    final finesRepository = RepositoryProvider.of<FinesRepository>(context);
    showDialog(
      context: context,
      barrierDismissible: !isLoading,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text("Pay Fines to Government", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("You are about to officially mark ${fineIds.length} fine(s) as paid to the Dubai Police. This will create an Expense Journal and visually deduct from your Drawer balance.", style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[700])),
                  const SizedBox(height: 16),
                  Text("Select Payment Source:", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedDrawerId,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: drawersData.map((d) {
                      final balance = (d['balance'] as num).toDouble();
                      return DropdownMenuItem<String>(
                        value: d['id'].toString(),
                        child: Text("${d['name']} (Bal: $balance)"),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setDialogState(() {
                        selectedDrawerId = val;
                      });
                    },
                  ),
                  if (isLoading) ...[
                    const SizedBox(height: 20),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(ctx),
                  child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                  onPressed: isLoading
                      ? null
                      : () async {
                          if (selectedDrawerId == null) return;
                          setDialogState(() => isLoading = true);
                          try {
                            await finesRepository.payFinesToGovernment(fineIds, selectedDrawerId!);
                            if (context.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Fines paid successfully!'), backgroundColor: Colors.green),
                              );
                              context.read<FinesBloc>().add(LoadFines());
                            }
                          } catch (e) {
                            setDialogState(() => isLoading = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(toUserFriendlyError(e)), backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                  child: isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text("Confirm Payment"),
                ),
              ],
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 700;
          final pad = isNarrow ? 16.0 : 24.0;
          return Padding(
            padding: EdgeInsets.all(pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                isNarrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Traffic Fines Management",
                            style: GoogleFonts.poppins(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              IconButton(
                                onPressed: _pickDateRange,
                                icon: const Icon(Icons.date_range),
                                color: AppTheme.primaryColor,
                                tooltip: "Filter by Date Range",
                              ),
                              IconButton(
                                onPressed: _handleRefresh,
                                icon: const Icon(Icons.refresh),
                                color: AppTheme.primaryColor,
                                tooltip: "Refresh List",
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'fines') {
                                      _handleUpload(isSalik: false);
                                    } else if (value == 'salik') {
                                      _handleUpload(isSalik: true);
                                    }
                                  },
                                  offset: const Offset(0, 40),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  itemBuilder: (BuildContext context) =>
                                      <PopupMenuEntry<String>>[
                                        PopupMenuItem<String>(
                                          value: 'fines',
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.file_upload,
                                                color: Color(0xFF1E293B),
                                                size: 18,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                "Upload Police Fines",
                                                style: GoogleFonts.poppins(
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem<String>(
                                          value: 'salik',
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.toll,
                                                color: Color(0xFF1E293B),
                                                size: 18,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                "Upload Salik Tolls",
                                                style: GoogleFonts.poppins(
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryColor,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.upload_file,
                                          size: 18,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          "Upload Excel",
                                          style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        const Icon(
                                          Icons.arrow_drop_down,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              "Traffic Fines Management",
                              style: GoogleFonts.poppins(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1E293B),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                onPressed: _pickDateRange,
                                icon: const Icon(Icons.date_range),
                                color: AppTheme.primaryColor,
                                tooltip: "Filter by Date Range",
                              ),
                              IconButton(
                                onPressed: _handleRefresh,
                                icon: const Icon(Icons.refresh),
                                color: AppTheme.primaryColor,
                                tooltip: "Refresh List",
                              ),
                              const SizedBox(width: 16),
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'fines') {
                                    _handleUpload(isSalik: false);
                                  } else if (value == 'salik') {
                                    _handleUpload(isSalik: true);
                                  }
                                },
                                offset: const Offset(0, 40),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                itemBuilder: (BuildContext context) =>
                                    <PopupMenuEntry<String>>[
                                      PopupMenuItem<String>(
                                        value: 'fines',
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.file_upload,
                                              color: Color(0xFF1E293B),
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              "Upload Police Fines",
                                              style: GoogleFonts.poppins(
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem<String>(
                                        value: 'salik',
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.toll,
                                              color: Color(0xFF1E293B),
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              "Upload Salik Tolls",
                                              style: GoogleFonts.poppins(
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.upload_file,
                                        size: 18,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        "Upload Excel",
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.arrow_drop_down,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                if (_selectedDateRange != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.date_range, size: 14, color: AppTheme.primaryColor),
                            const SizedBox(width: 8),
                            Text(
                              '${_selectedDateRange!.start.day} ${_getMonth(_selectedDateRange!.start.month)} ${_selectedDateRange!.start.year} - ${_selectedDateRange!.end.day} ${_getMonth(_selectedDateRange!.end.month)} ${_selectedDateRange!.end.year}',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _clearDateRange,
                              child: const Icon(Icons.close, size: 16, color: AppTheme.primaryColor),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),

                // Search & Filter Row
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
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
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: Colors.grey),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: "Search Ticket, Plate, Rider...",
                            border: InputBorder.none,
                          ),
                          onChanged: _onSearchChanged,
                        ),
                      ),
                      Container(
                        height: 24,
                        width: 1,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(width: 16),
                      BlocBuilder<FinesBloc, FinesState>(
                        builder: (context, state) {
                          return DropdownButton<FineStatus?>(
                            value: _filterStatus,
                            underline: const SizedBox(),
                            hint: Text(
                              "Filter Status",
                              style: GoogleFonts.poppins(fontSize: 14),
                            ),
                            items: [
                              const DropdownMenuItem<FineStatus?>(
                                value: null,
                                child: Text("All Status"),
                              ),
                              ...FineStatus.values
                                  .where((s) => s != FineStatus.fully_recovered)
                                  .map(
                                    (status) => DropdownMenuItem(
                                      value: status,
                                      child: Text(
                                        status.name
                                                .substring(0, 1)
                                                .toUpperCase() +
                                            status.name.substring(1),
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w500,
                                          color: const Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                  ),
                            ],
                            onChanged: _onFilterChanged,
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Table Body
                Expanded(
                  child: BlocListener<FinesBloc, FinesState>(
                    listener: (context, state) {
                      if (state is FinesLoaded) {
                        _allItems = state.fines;
                        _applyFilters();
                      }
                    },
                    child: Builder(
                      builder: (context) {
                        final state = context.watch<FinesBloc>().state;
                        if (state is FinesLoading && state.fines.isEmpty) {
                          return const Center(child: CircularProgressIndicator());
                      } else if (state is FinesError) {
                        return Center(
                          child: Text(
                            "Error loading fines: ${state.message}",
                            style: GoogleFonts.poppins(color: Colors.red),
                          ),
                        );
                      } else if (_filteredItems.isEmpty) {
                        return Center(
                          child: Text(
                            "No fines found.",
                            style: GoogleFonts.poppins(color: Colors.grey),
                          ),
                        );
                      }

                      final fines = _filteredItems;
                      final selectedIds = state.selectedIds;

                      return Stack(
                        children: [
                          Card(
                            elevation: 2,
                            margin: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Scrollbar(
                              controller: _horizontalScrollController,
                              thumbVisibility: false,
                              trackVisibility: false,
                              thickness: 8,
                              radius: const Radius.circular(4),
                              child: SingleChildScrollView(
                                controller: _horizontalScrollController,
                                scrollDirection: Axis.horizontal,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(minWidth: 1200),
                                  child: SingleChildScrollView(
                                    controller: _verticalTableScrollController,
                                    primary: false,
                                    child: DataTable(
                                      headingRowColor: WidgetStateProperty.all(
                                        Colors.grey.shade50,
                                      ),
                                      columnSpacing: 24,
                                      horizontalMargin: 24,
                                      columns: [
                                        DataColumn(
                                          label: Row(
                                            children: [
                                              Checkbox(
                                                value:
                                                    fines.isNotEmpty &&
                                                    fines.every(
                                                      (f) => selectedIds.contains(
                                                        f.id,
                                                      ),
                                                    ),
                                                onChanged: (val) {
                                                  if (val == true) {
                                                    for (final f in fines) {
                                                      if (!selectedIds.contains(
                                                        f.id,
                                                      )) {
                                                        context
                                                            .read<FinesBloc>()
                                                            .add(
                                                              ToggleFineSelection(
                                                                f.id,
                                                              ),
                                                            );
                                                      }
                                                    }
                                                  } else {
                                                    context.read<FinesBloc>().add(
                                                      ClearSelection(),
                                                    );
                                                  }
                                                },
                                              ),
                                              Text(
                                                "Ticket #",
                                                style: GoogleFonts.poppins(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              const Tooltip(
                                                 message: "Green check indicates fine was officially paid to government",
                                                 child: Icon(Icons.info_outline, size: 14, color: Colors.grey),
                                              ),
                                            ],
                                          ),
                                        ),
                                        DataColumn(
                                          label: Text(
                                            "Plate",
                                            style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: Text(
                                            "Date & Time",
                                            style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: Text(
                                            "Rider",
                                            style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: Text(
                                            "Amount",
                                            style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: Text(
                                            "Status",
                                            style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: Text(
                                            "Actions",
                                            style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                      rows: fines.map((fine) {
                                        final isSelected = selectedIds.contains(
                                          fine.id,
                                        );
                                        final riderName = fine.riderName;

                                        return DataRow(
                                          selected: isSelected,
                                          onSelectChanged: (val) {
                                            context.read<FinesBloc>().add(
                                              ToggleFineSelection(fine.id),
                                            );
                                          },
                                          color:
                                              WidgetStateProperty.resolveWith<
                                                Color?
                                              >((Set<WidgetState> states) {
                                                if (fine.id == _flashingFineId) {
                                                  return Colors.red.withValues(alpha: 
                                                    0.15,
                                                  ); // Highlight color
                                                }
                                                if (states.contains(
                                                  WidgetState.selected,
                                                )) {
                                                  return Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                      .withValues(alpha: 0.08);
                                                }
                                                return null;
                                              }),
                                          cells: [
                                            DataCell(
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (fine.paidToGovtDate != null)
                                                    const Padding(
                                                      padding: EdgeInsets.only(right: 6.0),
                                                      child: Tooltip(
                                                        message: "Paid to Government",
                                                        child: Icon(Icons.account_balance, color: Colors.green, size: 16),
                                                      ),
                                                    ),
                                                  Text(
                                                    fine.ticketNumber,
                                                    style: GoogleFonts.poppins(
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                fine.plateNumber,
                                                style: GoogleFonts.poppins(),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                DateFormat('MMM d, HH:mm')
                                                    .format(fine.violationDate),
                                                style: GoogleFonts.poppins(
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              InkWell(
                                                onTap: (riderName != null && riderName.isNotEmpty) 
                                                  ? () => _showRiderVerificationTooltip(fine)
                                                  : null,
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    if (fine.status == FineStatus.matched)
                                                      const Icon(Icons.verified, color: Colors.green, size: 16),
                                                    if (fine.status == FineStatus.partial_match)
                                                      const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
                                                    if (fine.status == FineStatus.assigned)
                                                      const Icon(Icons.person_pin, color: Colors.blue, size: 16),
                                                    if (riderName != null && riderName.isNotEmpty)
                                                      const SizedBox(width: 4),
                                                    Text(
                                                      (riderName != null &&
                                                              riderName.isNotEmpty)
                                                          ? riderName
                                                          : "Unmatched",
                                                      style: GoogleFonts.poppins(
                                                        fontWeight: FontWeight.bold,
                                                        color: fine.status == FineStatus.matched
                                                            ? Colors.green
                                                            : (fine.status == FineStatus.assigned
                                                                ? Colors.blue
                                                                : (fine.status == FineStatus.partial_match ? Colors.orange : Colors.red)),
                                                        decoration: (riderName != null && riderName.isNotEmpty)
                                                            ? TextDecoration.underline
                                                            : null,
                                                        decorationStyle: TextDecorationStyle.dashed,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    "AED ${fine.amount.toStringAsFixed(0)}",
                                                    style: GoogleFonts.poppins(
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  InkWell(
                                                    onTap: () {
                                                      _showEditAmountDialog(fine);
                                                    },
                                                    child: const Padding(
                                                      padding: EdgeInsets.all(
                                                        4.0,
                                                      ),
                                                      child: Icon(
                                                        Icons.edit,
                                                        size: 14,
                                                        color:
                                                            AppTheme.primaryColor,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            DataCell(_buildStatusBadge(fine)),
                                            DataCell(_buildActionButtons(fine)),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (selectedIds.isNotEmpty)
                            Positioned(
                              bottom: 24,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 
                                          0.3,
                                        ),
                                        blurRadius: 20,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          "${selectedIds.length} items selected",
                                          style: GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(width: 24),
                                        ElevatedButton(
                                          onPressed: () {
                                            context.read<FinesBloc>().add(
                                              AutoMatchFines(selectedIds.toList()),
                                            );
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.blueAccent,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 20,
                                              vertical: 12,
                                            ),
                                          ),
                                          child: const Text("Auto Match"),
                                        ),
                                        const SizedBox(width: 12),
                                        ElevatedButton(
                                          onPressed: () {
                                            _showPayFinesDialog(selectedIds.toList());
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppTheme.primaryColor,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 20,
                                              vertical: 12,
                                            ),
                                          ),
                                          child: const Text("Mark as Paid"),
                                        ),
                                        const SizedBox(width: 12),
                                        ElevatedButton(
                                          onPressed: () {
                                            if (selectedIds.length == 1) {
                                              final fId = selectedIds.first;
                                              final fActionBloc = context.read<FinesBloc>();
                                              final rActionBloc = context.read<RidersBloc>();
                                              showDialog(
                                                context: context,
                                                builder: (dialogCtx) => MultiBlocProvider(
                                                  providers: [
                                                    BlocProvider.value(value: fActionBloc),
                                                    BlocProvider.value(value: rActionBloc),
                                                  ],
                                                  child: ManualAssignmentDialog(
                                                    fineId: fId,
                                                    onConfirm: (riderId) {
                                                      fActionBloc.add(ManualAssignFine(fineId: fId, riderId: riderId));
                                                    },
                                                  ),
                                                ),
                                              );
                                            } else {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text("Manual assignment is currently one-by-one. Use Auto Match for multiple.")),
                                              );
                                            }
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.orange,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 20,
                                              vertical: 12,
                                            ),
                                          ),
                                          child: const Text(
                                            "Assign Rider",
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        TextButton(
                                          onPressed: () {
                                            context.read<FinesBloc>().add(
                                              ClearSelection(),
                                            );
                                          },
                                          child: const Text(
                                            "Cancel",
                                            style: TextStyle(
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ),
                                      ],
                                     ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
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

  Widget _buildStatusBadge(FineModel fine) {
    Color color;
    String label;

    switch (fine.status) {
      case FineStatus.matched:
        color = Colors.green;
        label = "Matched";
        break;
      case FineStatus.assigned:
        color = Colors.blue;
        label = "Ready";
        break;
      case FineStatus.partial_match:
        color = Colors.indigo;
        label = "Partial Match";
        break;
      case FineStatus.partially_recovered:
        color = Colors.amber;
        label = "Partial Pay";
        break;
      case FineStatus.fully_recovered:
        color = Colors.cyan;
        label = "Recovered";
        break;
      default:
        color = Colors.red;
        label = "Unmatched";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  void _showEditAmountDialog(FineModel fine) {
    final controller = TextEditingController(text: fine.amount.toString());
    bool isSaving = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: Text(
            "Edit Fine Amount",
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 300, maxWidth: 440),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Fine: ${fine.ticketNumber}",
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: "Amount (AED)",
                      border: OutlineInputBorder(),
                      prefixText: "AED ",
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    autofocus: true,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final val = double.tryParse(controller.text.trim());
                      if (val == null || val < 0) return;
                      setLocalState(() => isSaving = true);
                      final bloc = context.read<FinesBloc>();
                      bloc.add(EditFineAmount(fine.id, val));

                      final nextState = await bloc.stream
                          .firstWhere((s) => s is! FinesLoading)
                          .timeout(
                            const Duration(seconds: 15),
                            onTimeout: () => bloc.state,
                          );

                      if (!mounted) return;
                      Navigator.pop(ctx);
                      if (nextState is FinesError) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Failed to update fine amount: ${nextState.message}',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Fine amount updated to AED $val')),
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: isSaving
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text('Please wait...'),
                      ],
                    )
                  : const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(FineModel fine) {
    if (fine.status == FineStatus.fully_recovered) {
      return const Text("-", style: TextStyle(color: Colors.grey));
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (fine.status == FineStatus.unmatched)
          TextButton.icon(
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => ManualAssignmentDialog(
                  fineId: fine.id,
                  onConfirm: (riderId) {
                    context.read<FinesBloc>().add(ManualAssignFine(fineId: fine.id, riderId: riderId));
                  },
                ),
              );
            },
            icon: const Icon(Icons.person_add, size: 16),
            label: const Text("Assign", style: TextStyle(fontSize: 12)),
          ),
        if (fine.status == FineStatus.partial_match) ...[
          IconButton(
            onPressed: () {
              context.read<FinesBloc>().add(ConfirmPartialMatch(fine.id));
            },
            icon: const Icon(Icons.check_circle, color: Colors.green, size: 22),
            tooltip: "Confirm Match",
          ),
          IconButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => ManualAssignmentDialog(
                  fineId: fine.id,
                  onConfirm: (riderId) {
                    context.read<FinesBloc>().add(ManualAssignFine(fineId: fine.id, riderId: riderId));
                  },
                ),
              );
            },
            icon: const Icon(Icons.edit, color: Colors.grey, size: 20),
            tooltip: "Change Rider",
          ),
          IconButton(
            onPressed: () {
              context.read<FinesBloc>().add(UnlinkRider(fine.id));
            },
            icon: const Icon(Icons.link_off, color: Colors.red, size: 20),
            tooltip: "Unlink Rider",
          ),
        ],
        if (fine.status == FineStatus.matched || fine.status == FineStatus.assigned) ...[
          if (fine.paidToGovtDate == null)
            IconButton(
              onPressed: () => _showPayFinesDialog([fine.id]),
              icon: const Icon(Icons.account_balance_wallet, color: AppTheme.primaryColor),
              tooltip: "Pay to Government",
            ),
          IconButton(
            onPressed: () {
              context.read<FinesBloc>().add(UnlinkRider(fine.id));
            },
            icon: const Icon(Icons.link_off, color: Colors.red, size: 20),
            tooltip: "Unlink Rider",
          ),
        ],
      ],
    );
  }

  void _showRiderVerificationTooltip(FineModel fine) {
    if (fine.riderId == null) return;
    
    final state = context.read<FinesBloc>().state;
    final rider = state.riders.firstWhere(
      (r) => r.id == fine.riderId, 
      orElse: () => RiderModel(id: '', name: 'Unknown', status: RiderStatus.retired),
    );
    
    // Find current bike assignment
    final currentAssignment = state.assignments.firstWhere(
      (a) => a.riderId == fine.riderId && a.returnedAt == null,
      orElse: () => BikeAssignmentModel(id: '', chassisNumber: 'None', riderId: '', assignedAt: DateTime(2000)),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.verified_user, color: Colors.blue),
            const SizedBox(width: 8),
            const Text("Rider Verification"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: CircleAvatar(
                radius: 40,
                backgroundColor: Colors.grey[200],
                child: const Icon(Icons.person, size: 50, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 20),
            _buildInfoRow("Name", rider.name),
            _buildInfoRow("Rider Code", rider.riderCode ?? "N/A"),
            _buildInfoRow("Current Bike", currentAssignment.plateNumber ?? currentAssignment.chassisNumber),
            const Divider(height: 32),
            Text(
              "Comparison:",
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            _buildInfoRow("Fine Plate", fine.plateNumber, color: Colors.orange),
            _buildInfoRow(
              "Status", 
              fine.status == FineStatus.matched ? "System Log Match (Verified)" : 
              (fine.status == FineStatus.assigned ? "Manual Assignment (Check manually)" : "Name Match (Verify carefully)"),
              color: fine.status == FineStatus.matched ? Colors.green : 
                     (fine.status == FineStatus.assigned ? Colors.blue : Colors.orange),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("$label:", style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 12)),
          Text(value, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

