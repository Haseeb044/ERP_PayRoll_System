import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../logic/actions/action_bloc.dart';
import '../../data/models/action_item_model.dart';
import '../../core/app_theme.dart';
import '../widgets/action_card.dart';

class ActionsPage extends StatelessWidget {
  const ActionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ActionsView();
  }
}

class ActionsView extends StatefulWidget {
  const ActionsView({super.key});

  @override
  State<ActionsView> createState() => _ActionsViewState();
}

class _ActionsViewState extends State<ActionsView> {
  DateTimeRange? _selectedDateRange;
  String _searchQuery = '';
  List<ActionItemModel> _allItems = [];
  List<ActionItemModel> _filteredItems = [];

  void _applyFilters() {
    setState(() {
      _filteredItems = _allItems.where((a) {
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          if (!a.title.toLowerCase().contains(q)) {
            return false;
          }
        }
        if (_selectedDateRange != null) {
          if (a.createdAt == null) return false;
          final dt = DateUtils.dateOnly(a.createdAt!.toLocal());
          final start = DateUtils.dateOnly(_selectedDateRange!.start);
          final end = DateUtils.dateOnly(_selectedDateRange!.end);
          if (dt.isBefore(start) || dt.isAfter(end)) {
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
      lastDate: DateTime.now().add(const Duration(days: 365)),
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh when navigated back to this screen
    context.read<ActionBloc>().add(ScanSystem());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 32),
            Expanded(
              child: BlocListener<ActionBloc, ActionState>(
                listener: (context, state) {
                  if (state is ActionLoaded) {
                    _allItems = state.actions;
                    _applyFilters();
                  }
                },
                child: Builder(
                  builder: (context) {
                    final state = context.watch<ActionBloc>().state;
                    if (state is ActionLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (state is ActionLoaded) {
                      if (_filteredItems.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.check_circle_outline,
                                size: 64,
                                color: Colors.green,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                "All Caught Up!",
                                style: GoogleFonts.poppins(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "No pending actions required.",
                                style: GoogleFonts.poppins(color: Colors.grey),
                              ),
                            ],
                          ),
                        );
                    }
                    return ListView.builder(
                      itemCount: _filteredItems.length,
                      itemBuilder: (context, index) {
                        final action = _filteredItems[index];
                        return ActionCard(
                          key: ValueKey(action.id),
                          action: action,
                          onDismiss: () {},
                        );
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
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    int count = _filteredItems.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  "Pending Actions",
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "$count Urgent",
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
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
                  onPressed: () => context.read<ActionBloc>().add(ScanSystem()),
                  icon: const Icon(Icons.refresh),
                  color: AppTheme.primaryColor,
                  tooltip: "Refresh Actions",
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
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
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
      ],
    );
  }
}
