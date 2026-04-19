import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../logic/drawers/drawer_bloc.dart';
import '../widgets/drawer_card.dart';
import '../widgets/transfer_dialog.dart';
import '../../data/repositories/drawer_repository.dart';
import '../../data/repositories/journal_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/user_friendly_error.dart';

class DrawerPage extends StatelessWidget {
  const DrawerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => DrawerBloc(
        context.read<DrawerRepository>(),
        context.read<JournalRepository>(),
      )..add(const LoadDrawers()),
      child: const DrawerView(),
    );
  }
}

class DrawerView extends StatefulWidget {
  const DrawerView({super.key});

  @override
  State<DrawerView> createState() => _DrawerViewState();
}

class _DrawerViewState extends State<DrawerView>
  with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final state = context.read<DrawerBloc>().state;
          if (state is DrawerLoaded) {
            showDialog(
              context: context,
              builder: (_) => BlocProvider.value(
                value: context.read<DrawerBloc>(),
                child: TransferDialog(drawers: state.drawers),
              ),
            );
          }
        },
        backgroundColor: const Color(0xFF15803D),
        label: Text(
          "New Transfer",
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        icon: const Icon(Icons.compare_arrows),
      ),
      body: Padding(
        padding: const EdgeInsets.all(32),
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
                      "Treasury Management",
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Monitor cash flow and manage drawer balances",
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () {
                    context.read<DrawerBloc>().add(const LoadDrawers());
                  },
                  icon: const Icon(Icons.refresh, color: Color(0xFF15803D)),
                  tooltip: 'Refresh Treasury',
                ),
              ],
            ),
            const SizedBox(height: 24),
            TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF15803D),
              unselectedLabelColor: const Color(0xFF64748B),
              indicatorColor: const Color(0xFF15803D),
              labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              unselectedLabelStyle: GoogleFonts.poppins(
                fontWeight: FontWeight.w400,
              ),
              tabs: const [
                Tab(text: "Drawers & Transactions"),
                Tab(text: "Transaction History"),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_DrawersTab(), const _TransactionHistoryTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Drawers & Transactions Tab ─────────────────────────────────────────────

class _DrawersTab extends StatefulWidget {
  @override
  State<_DrawersTab> createState() => _DrawersTabState();
}

class _DrawersTabState extends State<_DrawersTab> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 200,
          child: BlocBuilder<DrawerBloc, DrawerState>(
            builder: (context, state) {
              if (state is DrawerLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state is DrawerLoaded) {
                return Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: false,
                  child: ListView.builder(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(right: 16),
                    itemCount: state.drawers.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        final isSelected = state.selectedDrawerId == null;
                        return _buildAllCard(context, isSelected);
                      }
                      final drawer = state.drawers[index - 1];
                      return DrawerCard(
                        drawer: drawer,
                        isSelected: state.selectedDrawerId == drawer.id,
                        onTap: () {
                          context.read<DrawerBloc>().add(
                            LoadDrawers(filterDrawerId: drawer.id),
                          );
                        },
                      );
                    },
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
        const SizedBox(height: 24),
        Text(
          "Recent Transactions",
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: BlocBuilder<DrawerBloc, DrawerState>(
            builder: (context, state) {
              if (state is DrawerLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state is DrawerLoaded) {
                if (state.transactions.isEmpty) {
                  return Center(
                    child: Text(
                      "No transactions found",
                      style: GoogleFonts.poppins(color: Colors.grey),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: state.transactions.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final tx = state.transactions[index];
                    final isCredit = tx.isCredit;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: isCredit
                            ? Colors.green[50]
                            : Colors.red[50],
                        child: Icon(
                          isCredit ? Icons.arrow_downward : Icons.arrow_upward,
                          color: isCredit ? Colors.green : Colors.red,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        tx.description,
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        DateFormat('MMM dd, yyyy - hh:mm a').format(tx.date),
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      trailing: Text(
                        "${isCredit ? '+' : '-'} AED ${NumberFormat.compact().format(tx.amount)}",
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          color: isCredit ? Colors.green[700] : Colors.red[700],
                        ),
                      ),
                    );
                  },
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAllCard(BuildContext context, bool isSelected) {
    return GestureDetector(
      onTap: () {
        context.read<DrawerBloc>().add(const LoadDrawers(filterDrawerId: null));
      },
      child: Container(
        width: 150,
        margin: const EdgeInsets.only(right: 16, bottom: 16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey[800] : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.dashboard,
              size: 32,
              color: isSelected ? Colors.white : Colors.grey[600],
            ),
            const SizedBox(height: 8),
            Text(
              "All Accounts",
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : Colors.grey[800],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Transaction History Tab ──────────────────────────────────────────────────

class _TransactionHistoryTab extends StatefulWidget {
  const _TransactionHistoryTab();

  @override
  State<_TransactionHistoryTab> createState() => _TransactionHistoryTabState();
}

class _TransactionHistoryTabState extends State<_TransactionHistoryTab> {
  List<Map<String, dynamic>> _allItems = [];
  List<Map<String, dynamic>> _filteredItems = [];
  bool _loading = true;
  String? _error;
  
  String _searchQuery = '';
  DateTimeRange? _selectedDateRange;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await Supabase.instance.client
          .from('ledger')
          .select('*, journals(*)')
          .order('posted_at', ascending: false)
          .limit(50);
      
      if (mounted) {
        setState(() {
          _allItems = (response as List).cast<Map<String, dynamic>>();
          _applyFilters();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = toUserFriendlyError(e);
          _loading = false;
        });
      }
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredItems = _allItems.where((item) {
        final journal = item['journals'] as Map<String, dynamic>?;
        final desc = (journal?['description']?.toString() ?? '').toLowerCase();
        final acc = (item['account_id']?.toString() ?? '').toLowerCase();
        
        // Search
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          if (!desc.contains(q) && !acc.contains(q)) {
            return false;
          }
        }
        
        // Date range
        if (_selectedDateRange != null) {
          final postedStr = item['posted_at']?.toString() ?? '';
          final postedDt = DateTime.tryParse(postedStr);
          if (postedDt != null) {
            final dtDateOnly = DateUtils.dateOnly(postedDt);
            final start = DateUtils.dateOnly(_selectedDateRange!.start);
            final end = DateUtils.dateOnly(_selectedDateRange!.end);
            if (dtDateOnly.isBefore(start) || dtDateOnly.isAfter(end)) {
              return false;
            }
          }
        }
        
        return true;
      }).toList();
    });
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF15803D), // matching Treasury brand color
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
        _applyFilters();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _allItems.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _allItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red[300], size: 48),
            const SizedBox(height: 12),
            Text(
              "Failed to load transactions",
              style: GoogleFonts.poppins(color: Colors.red),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _fetchHistory,
              icon: const Icon(Icons.refresh),
              label: const Text("Retry"),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search description or account...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onChanged: (val) {
                  _searchQuery = val;
                  _applyFilters();
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.date_range, color: Color(0xFF15803D)),
              onPressed: _pickDateRange,
              tooltip: 'Filter by Date Range',
            ),
            if (_selectedDateRange != null)
              IconButton(
                icon: const Icon(Icons.clear, color: Colors.red),
                onPressed: () {
                  setState(() {
                    _selectedDateRange = null;
                    _applyFilters();
                  });
                },
                tooltip: 'Clear Date Filter',
              ),
            IconButton(
              onPressed: _fetchHistory,
              icon: const Icon(Icons.refresh, color: Color(0xFF15803D)),
              tooltip: "Refresh Ledger",
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
                  color: const Color(0xFF15803D).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.filter_alt, size: 14, color: Color(0xFF15803D)),
                    const SizedBox(width: 4),
                    Text(
                      '${DateFormat('MMM dd').format(_selectedDateRange!.start)} - ${DateFormat('MMM dd').format(_selectedDateRange!.end)}',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF15803D),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        if (_filteredItems.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long, color: Colors.grey[300], size: 64),
                  const SizedBox(height: 12),
                  Text(
                    "No transactions found matching filters.",
                    style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: _filteredItems.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final tx = _filteredItems[index];
                final journal = tx['journals'] as Map<String, dynamic>?;
                
                final debitAmount = (tx['debit_amount'] as num?)?.toDouble() ?? 0.0;
                final creditAmount = (tx['credit_amount'] as num?)?.toDouble() ?? 0.0;
                final desc = journal?['description']?.toString() ?? 'No description';
                final accountId = tx['account_id']?.toString() ?? 'Unknown Account';
                final postedAt = DateTime.tryParse(tx['posted_at']?.toString() ?? '') ?? DateTime.now();

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  title: Text(
                    desc,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: Text(
                    "$accountId  |  ${DateFormat('dd MMM yyyy').format(postedAt)}",
                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (debitAmount > 0)
                        Text(
                          "AED ${NumberFormat('#,##0.00').format(debitAmount)}",
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            color: Colors.green[700],
                            fontSize: 14,
                          ),
                        ),
                      if (creditAmount > 0)
                        Text(
                          "AED ${NumberFormat('#,##0.00').format(creditAmount)}",
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            color: Colors.red[700],
                            fontSize: 14,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
