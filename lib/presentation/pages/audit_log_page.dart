import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../utils/user_friendly_error.dart';

class AuditLogPage extends StatefulWidget {
  const AuditLogPage({super.key});

  @override
  State<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends State<AuditLogPage> {
  DateTimeRange? _selectedDateRange;
  String? _selectedTable;
  String? _selectedAction;
  List<Map<String, dynamic>> _allLogs = [];
  List<Map<String, dynamic>> _filteredLogs = [];
  bool _isLoading = false;
  String? _errorMessage;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _setupSubscription();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadData();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  void _setupSubscription() {
    _channel = Supabase.instance.client
        .channel('audit_log_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'audit_log',
          callback: (payload) {
            if (mounted) _loadData();
          },
        )
        .subscribe();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await Supabase.instance.client
          .from('audit_log')
          .select()
          .order('changed_at', ascending: false);

      if (mounted) {
        setState(() {
          _allLogs = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
        _applyFilters();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = toUserFriendlyError(e);
          _isLoading = false;
        });
      }
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredLogs = _allLogs.where((log) {
        final matchesTable = _selectedTable == null || log['table_name'] == _selectedTable;
        final matchesAction = _selectedAction == null || log['action'] == _selectedAction;
        bool matchesDate = true;
        if (_selectedDateRange != null && log['changed_at'] != null) {
          final changedAt = DateTime.parse(log['changed_at']).toLocal();
          matchesDate = changedAt.isAfter(
                _selectedDateRange!.start.subtract(const Duration(days: 1)),
              ) &&
              changedAt.isBefore(
                _selectedDateRange!.end.add(const Duration(days: 1)),
              );
        }
        return matchesTable && matchesAction && matchesDate;
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

  void _clearActionFilter() {
    _selectedAction = null;
    _applyFilters();
  }

  List<String> get _tableNames {
    final set = <String>{};
    for (final log in _allLogs) {
      if (log['table_name'] != null) {
        set.add(log['table_name'].toString());
      }
    }
    final sorted = set.toList()..sort();
    return sorted;
  }

  String _getMonth(int m) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[m - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // â”€â”€ Header â”€â”€
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Audit Log",
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                Row(
                  children: [
                    // Table filter dropdown
                    _buildTableFilter(),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: _pickDateRange,
                      icon: const Icon(Icons.date_range),
                      tooltip: "Filter by Date Range",
                      color: AppTheme.primaryColor,
                    ),
                    IconButton(
                      onPressed: _loadData,
                      icon: const Icon(Icons.refresh),
                      tooltip: "Refresh",
                      color: AppTheme.primaryColor,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Actions Filter
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _selectedAction == null,
                  onSelected: (selected) {
                    if (selected) {
                      _clearActionFilter();
                    }
                  },
                  selectedColor: AppTheme.primaryColor.withValues(alpha: 0.2),
                ),
                ChoiceChip(
                  label: const Text('INSERT'),
                  selected: _selectedAction == 'INSERT',
                  onSelected: (selected) {
                    _selectedAction = selected ? 'INSERT' : null;
                    _applyFilters();
                  },
                  selectedColor: Colors.green.withValues(alpha: 0.2),
                ),
                ChoiceChip(
                  label: const Text('UPDATE'),
                  selected: _selectedAction == 'UPDATE',
                  onSelected: (selected) {
                    _selectedAction = selected ? 'UPDATE' : null;
                    _applyFilters();
                  },
                  selectedColor: Colors.blue.withValues(alpha: 0.2),
                ),
                ChoiceChip(
                  label: const Text('DELETE'),
                  selected: _selectedAction == 'DELETE',
                  onSelected: (selected) {
                    _selectedAction = selected ? 'DELETE' : null;
                    _applyFilters();
                  },
                  selectedColor: Colors.red.withValues(alpha: 0.2),
                ),
              ],
            ),
            if (_selectedDateRange != null) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
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

            // â”€â”€ Content â”€â”€
            Expanded(
              child: Builder(
                builder: (context) {
                  if (_isLoading && _allLogs.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (_errorMessage != null) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage!,
                            style: GoogleFonts.poppins(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _loadData,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }
                  if (_filteredLogs.isEmpty) {
                    if (_allLogs.isEmpty) {
                      return _buildEmptyState();
                    }
                    return Center(
                      child: Text(
                        "No logs match the current filters.",
                        style: GoogleFonts.poppins(color: Colors.grey[600]),
                      ),
                    );
                  }
                  return _buildLogList(_filteredLogs);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // â”€â”€â”€ Widgets â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildTableFilter() {
    final tables = _tableNames;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedTable,
          hint: Text("All Tables", style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[600])),
          icon: const Icon(Icons.filter_list, size: 18),
          items: [
            DropdownMenuItem<String>(
              value: null,
              child: Text("All Tables", style: GoogleFonts.poppins(fontSize: 13)),
            ),
            ...tables.map(
              (t) => DropdownMenuItem<String>(
                value: t,
                child: Text(t, style: GoogleFonts.poppins(fontSize: 13)),
              ),
            ),
          ],
          onChanged: (v) {
            _selectedTable = v;
            _applyFilters();
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            "No audit log entries",
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Changes to database records will appear here automatically.",
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildLogList(List<Map<String, dynamic>> entries) {
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _buildLogCard(entries[index]),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> entry) {
    final action = entry['action']?.toString() ?? 'UNKNOWN';
    final tableName = entry['table_name']?.toString() ?? 'unknown_table';
    final recordId = entry['record_id']?.toString() ?? 'unknown_id';
    final changedAtRaw = entry['changed_at']?.toString() ?? '';
    final changedBy = entry['changed_by_user_id']?.toString();
    final oldData = entry['old_data'] as Map<String, dynamic>?;
    final newData = entry['new_data'] as Map<String, dynamic>?;

    final actionColor = _actionColor(action);
    final actionIcon = _actionIcon(action);

    DateTime? changedDate;
    if (changedAtRaw.isNotEmpty) {
      changedDate = DateTime.tryParse(changedAtRaw)?.toLocal();
    }

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Action icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: actionColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(actionIcon, color: actionColor, size: 20),
            ),
            const SizedBox(width: 14),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Action badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: actionColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          action,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: actionColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Table name chip
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _actionColor(action).withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          tableName,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    recordId,
                    style: GoogleFonts.sourceCodePro(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Changed By: ${changedBy ?? 'System'}",
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey[800],
                    ),
                  ),
                ],
              ),
            ),

            // Timestamp
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (changedDate != null) ...[
                  Text(
                    _fmtDate(changedDate),
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  Text(
                    _fmtTime(changedDate),
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red[100],
                          border: Border.all(color: Colors.red[300]!),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          "Old Data",
                          style: GoogleFonts.poppins(fontSize: 11, color: Colors.red[900], fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 8),
                      oldData == null
                          ? Text("Not Available", style: GoogleFonts.poppins(fontSize: 12, fontStyle: FontStyle.italic))
                          : _jsonSection(oldData),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green[100],
                          border: Border.all(color: Colors.green[300]!),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          "New Data",
                          style: GoogleFonts.poppins(fontSize: 11, color: Colors.green[900], fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 8),
                      newData == null
                          ? Text("Not Available", style: GoogleFonts.poppins(fontSize: 12, fontStyle: FontStyle.italic))
                          : _jsonSection(newData),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _jsonSection(Map<String, dynamic> data) {
    final prettyJson = const JsonEncoder.withIndent('  ').convert(data);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: SelectableText(
        prettyJson,
        style: GoogleFonts.sourceCodePro(fontSize: 12, color: Colors.black87),
      ),
    );
  }

  // â”€â”€â”€ Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Color _actionColor(String action) {
    switch (action.toUpperCase()) {
      case 'INSERT':
        return Colors.green;
      case 'UPDATE':
        return Colors.orange;
      case 'DELETE':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _actionIcon(String action) {
    switch (action.toUpperCase()) {
      case 'INSERT':
        return Icons.add_circle_outline;
      case 'UPDATE':
        return Icons.edit_outlined;
      case 'DELETE':
        return Icons.remove_circle_outline;
      default:
        return Icons.info_outline;
    }
  }

  String _fmtDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
  }

  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

