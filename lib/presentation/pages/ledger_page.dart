import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/app_theme.dart';
import '../../logic/financial/ledger_bloc.dart';
import '../../data/models/ledger_entry_model.dart';
import '../../data/models/journal_model.dart';
import '../../data/repositories/journal_repository.dart';
import '../../data/models/user_model.dart';
import 'package:provider/provider.dart';
import '../../logic/riders/riders_bloc.dart';
import '../../data/models/rider_model.dart';
import '../../utils/user_friendly_error.dart';

class LedgerPage extends StatefulWidget {
  const LedgerPage({super.key});

  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  DateTimeRange? _selectedDateRange;
  String _searchQuery = '';
  String _counterpartyQuery = '';
  String? _selectedCounterpartyType;
  List<LedgerEntryModel> _allItems = [];
  List<LedgerEntryModel> _filteredItems = [];
  final ScrollController _entriesVerticalController = ScrollController();
  final ScrollController _entriesHorizontalController = ScrollController();

  void _applyFilters() {
    setState(() {
      _filteredItems = _allItems.where((e) {
        if (_selectedDateRange != null) {
          final start = DateUtils.dateOnly(_selectedDateRange!.start);
          final end = DateUtils.dateOnly(_selectedDateRange!.end);
          // Use e.postedAt
          final dt = DateUtils.dateOnly(e.postedAt.toLocal());
          if (dt.isBefore(start) || dt.isAfter(end)) return false;
        }
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          if (!(e.accountName.toLowerCase().contains(q)) &&
              !(e.journalDescription?.toLowerCase().contains(q) ?? false) &&
              !(e.counterpartyName?.toLowerCase().contains(q) ?? false)) {
            return false;
          }
        }
        if (_selectedCounterpartyType != null &&
            _selectedCounterpartyType!.isNotEmpty) {
          final entryType = (e.counterpartyType ?? '').toLowerCase();
          if (entryType != _selectedCounterpartyType) {
            return false;
          }
        }
        if (_counterpartyQuery.isNotEmpty) {
          final q = _counterpartyQuery.toLowerCase();
          final name = (e.counterpartyName ?? '').toLowerCase();
          final id = (e.counterpartyId ?? '').toLowerCase();
          if (!name.contains(q) && !id.contains(q)) {
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
    _tabController = TabController(length: 3, vsync: this);
    context.read<LedgerBloc>().add(const LoadLedger());
  }

  @override
  void dispose() {
    _entriesVerticalController.dispose();
    _entriesHorizontalController.dispose();
    _tabController.dispose();
    super.dispose();
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'General Ledger',
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.date_range, color: AppTheme.primaryColor),
                      onPressed: _pickDateRange,
                      tooltip: 'Filter by Date Range',
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: AppTheme.primaryColor),
                      onPressed: () => context.read<LedgerBloc>().add(const LoadLedger()),
                      tooltip: 'Refresh',
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _showSuspenseEntryDialog(context),
                      icon: const Icon(Icons.help_outline),
                      label: Text(
                        'New Suspense',
                        style: GoogleFonts.poppins(),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange[700],
                        foregroundColor: Colors.white,
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
            const SizedBox(height: 8),
            Text(
              'Read-only ledger â€” auto-populated when journals are posted.',
              style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),

            // Tabs
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: "Ledger Entries"),
                Tab(text: "Trial Balance"),
                Tab(text: "Rider Statement"),
              ],
              labelColor: AppTheme.primaryColor,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppTheme.primaryColor,
              labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Filters
            _buildFilters(),
            const SizedBox(height: 16),

            // Content
            Expanded(
              child: BlocListener<LedgerBloc, LedgerState>(
                listener: (context, state) {
                  if (state is LedgerLoaded) {
                    _allItems = state.entries;
                    _applyFilters();
                  }
                },
                child: Builder(
                  builder: (context) {
                    final state = context.watch<LedgerBloc>().state;
                    if (state is LedgerLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (state is LedgerError) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 48,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              state.message,
                              style: GoogleFonts.poppins(color: Colors.grey),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () => context.read<LedgerBloc>().add(
                                const LoadLedger(),
                              ),
                              child: const Text("Retry"),
                            ),
                          ],
                        ),
                      );
                    }
                    if (state is LedgerLoaded) {
                      return TabBarView(
                        controller: _tabController,
                        children: [
                          _buildEntriesTab(state),
                          _buildTrialBalanceTab(),
                          _buildRiderStatementTab(state),
                        ],
                      );
                    }
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return BlocBuilder<LedgerBloc, LedgerState>(
      builder: (context, state) {
        final accounts = state is LedgerLoaded ? state.accounts : <Map<String, String>>[];
        final selected = state is LedgerLoaded ? state.selectedAccount : null;
        // Deduplicate accounts by id to avoid duplicate DropdownMenuItems which cause Flutter assertions
        final Map<String, String> uniqueAccounts = {};
        for (final a in accounts) {
          final id = (a['id'] ?? '').toString();
          final name = (a['name'] ?? id).toString();
          if (id.isEmpty) continue;
          uniqueAccounts[id] = name;
        }
        final dedupedAccounts = uniqueAccounts.entries.map((e) => {'id': e.key, 'name': e.value}).toList(growable: false);
        // Ensure the dropdown value exists in the items to avoid Flutter assertion
        final safeSelected = (selected != null && uniqueAccounts.containsKey(selected)) ? selected : null;

        return LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 550;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.start,
              children: [
                // Account filter
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isNarrow ? constraints.maxWidth : 250,
                  ),
                  child: DropdownButtonFormField<String>(
                    value: safeSelected,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Account',
                      labelStyle: GoogleFonts.poppins(fontSize: 14),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        value: null,
                        child: Text(
                          'All Accounts',
                          style: GoogleFonts.poppins(fontSize: 14),
                        ),
                      ),
                      ...dedupedAccounts.map(
                        (a) => DropdownMenuItem<String>(
                          value: a['id'],
                          child: Text(
                            a['name'] ?? a['id'] ?? '',
                            style: GoogleFonts.poppins(fontSize: 14),
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      context.read<LedgerBloc>().add(
                        FilterLedgerByAccount(value),
                      );
                    },
                  ),
                ),
                // Counterparty type filter
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isNarrow ? constraints.maxWidth : 200,
                  ),
                  child: DropdownButtonFormField<String>(
                    value: _selectedCounterpartyType,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Counterparty Type',
                      labelStyle: GoogleFonts.poppins(fontSize: 14),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        value: null,
                        child: Text(
                          'All Types',
                          style: GoogleFonts.poppins(fontSize: 14),
                        ),
                      ),
                      DropdownMenuItem<String>(
                        value: 'rider',
                        child: Text('Rider', style: GoogleFonts.poppins(fontSize: 14)),
                      ),
                      DropdownMenuItem<String>(
                        value: 'vendor',
                        child: Text('Vendor', style: GoogleFonts.poppins(fontSize: 14)),
                      ),
                      DropdownMenuItem<String>(
                        value: 'supplier',
                        child: Text('Supplier', style: GoogleFonts.poppins(fontSize: 14)),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedCounterpartyType = value;
                      });
                      _applyFilters();
                    },
                  ),
                ),
                // Counterparty name/id filter
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isNarrow ? constraints.maxWidth : 280,
                  ),
                  child: TextFormField(
                    decoration: InputDecoration(
                      labelText: 'Counterparty Name / ID',
                      labelStyle: GoogleFonts.poppins(fontSize: 14),
                      prefixIcon: const Icon(Icons.person_search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (value) {
                      _counterpartyQuery = value.trim();
                      _applyFilters();
                    },
                  ),
                ),
                // General entry search
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isNarrow ? constraints.maxWidth : 260,
                  ),
                  child: TextFormField(
                    decoration: InputDecoration(
                      labelText: 'Search Entry',
                      labelStyle: GoogleFonts.poppins(fontSize: 14),
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (value) {
                      _searchQuery = value.trim();
                      _applyFilters();
                    },
                  ),
                ),
                // Removed Date Range
              ],
            );
          },
        );
      },
    );
  }

  // â”€â”€ Ledger Entries Tab â”€â”€

  Widget _buildEntriesTab(LedgerLoaded state) {
    final entries = _filteredItems;
    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.book_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No ledger entries.',
              style: GoogleFonts.poppins(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    // Recalculate summary from local filtered entries
    final filteredTotalDebit = entries.fold<double>(0, (s, e) => s + e.debit);
    final filteredTotalCredit = entries.fold<double>(0, (s, e) => s + e.credit);

    return Column(
      children: [
        // Summary bar
        Row(
          children: [
            _buildStatCard('Filtered Entries', entries.length.toString(), Icons.receipt_long, AppTheme.primaryColor),
            const SizedBox(width: 16),
            _buildStatCard('Filtered Debit', 'AED ${filteredTotalDebit.toStringAsFixed(2)}', Icons.arrow_upward, Colors.green[700]!),
            const SizedBox(width: 16),
            _buildStatCard('Filtered Credit', 'AED ${filteredTotalCredit.toStringAsFixed(2)}', Icons.arrow_downward, Colors.red[700]!),
            const SizedBox(width: 16),
            _buildStatCard('Total Balance', 'AED ${(filteredTotalDebit - filteredTotalCredit).toStringAsFixed(2)}', Icons.balance, Colors.blue[700]!),
          ],
        ),
        const SizedBox(height: 16),
        // Statement-style entries table
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Scrollbar(
                controller: _entriesVerticalController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _entriesVerticalController,
                  scrollDirection: Axis.vertical,
                  child: Scrollbar(
                    controller: _entriesHorizontalController,
                    thumbVisibility: true,
                    notificationPredicate: (notification) => notification.metrics.axis == Axis.horizontal,
                    child: SingleChildScrollView(
                      controller: _entriesHorizontalController,
                      scrollDirection: Axis.horizontal,
                  child: Builder(
                    builder: (context) {
                      final sortedEntries = [...entries]
                        ..sort((a, b) {
                          final byDate = a.postedAt.compareTo(b.postedAt);
                          if (byDate != 0) return byDate;
                          return a.id.compareTo(b.id);
                        });

                      double runningBalance = 0.0;
                      final rows = sortedEntries.map((entry) {
                        final debit = entry.debit;
                        final credit = entry.credit;
                        final accountId = entry.accountName;
                        final description = entry.journalDescription ?? accountId;
                        final counterpartyName = entry.counterpartyName?.trim();
                        final counterpartyType = entry.counterpartyType?.trim();
                        final counterpartyLabel =
                            (counterpartyName != null && counterpartyName.isNotEmpty)
                                ? (counterpartyType != null && counterpartyType.isNotEmpty
                                    ? '${_formatCounterpartyType(counterpartyType)}: $counterpartyName'
                                    : counterpartyName)
                                : '-';
                        final isSuspense = accountId.contains('706') || entry.journalType == 'suspense';
                        final side = debit > 0 && credit == 0
                            ? 'Dr'
                            : (credit > 0 && debit == 0 ? 'Cr' : (debit > credit ? 'Dr' : 'Cr'));
                        runningBalance += (debit - credit);
                        final balanceColor = runningBalance >= 0 ? Colors.green[700] : Colors.red[700];

                        return DataRow(
                          cells: [
                            DataCell(Text(DateFormat('dd/MM/yyyy').format(entry.postedAt.toLocal()), style: _cellStyle())),
                            DataCell(
                              SizedBox(
                                width: 180,
                                child: Text(
                                  _friendlyAccountName(accountId),
                                  style: _cellStyle().copyWith(fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 180,
                                child: Text(counterpartyLabel, style: _cellStyle(), overflow: TextOverflow.ellipsis),
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 240,
                                child: Text(description, style: _cellStyle(), overflow: TextOverflow.ellipsis),
                              ),
                            ),
                            DataCell(Text(debit == 0 ? '-' : debit.toStringAsFixed(2), style: _cellStyle().copyWith(color: Colors.green[700]))),
                            DataCell(Text(credit == 0 ? '-' : credit.toStringAsFixed(2), style: _cellStyle().copyWith(color: Colors.red[700]))),
                            DataCell(
                              Text(
                                side,
                                style: _cellStyle().copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: side == 'Dr' ? Colors.green[700] : Colors.red[700],
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                runningBalance.toStringAsFixed(2),
                                style: _cellStyle().copyWith(fontWeight: FontWeight.w600, color: balanceColor),
                              ),
                            ),
                            DataCell(
                              isSuspense
                                  ? TextButton(
                                      onPressed: () => _showClearSuspenseDialog(context, entry),
                                      child: const Text('Clear'),
                                    )
                                  : Text('-', style: _cellStyle()),
                            ),
                          ],
                        );
                      }).toList();

                      return DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          AppTheme.primaryColor.withValues(alpha: 0.06),
                        ),
                        columnSpacing: 24,
                        horizontalMargin: 16,
                        columns: [
                          DataColumn(label: Text('Date', style: _headerStyle())),
                          DataColumn(label: Text('Particulars', style: _headerStyle())),
                          DataColumn(label: Text('Counterparty', style: _headerStyle())),
                          DataColumn(label: Text('Description', style: _headerStyle())),
                          DataColumn(label: Text('Debit', style: _headerStyle()), numeric: true),
                          DataColumn(label: Text('Credit', style: _headerStyle()), numeric: true),
                          DataColumn(label: Text('Side', style: _headerStyle())),
                          DataColumn(label: Text('Balance', style: _headerStyle()), numeric: true),
                          DataColumn(label: Text('Action', style: _headerStyle())),
                        ],
                        rows: [
                          ...rows,
                          DataRow(
                            color: WidgetStateProperty.all(
                              AppTheme.primaryColor.withValues(alpha: 0.04),
                            ),
                            cells: [
                              DataCell(Text('Total', style: _headerStyle())),
                              const DataCell(Text('')),
                              const DataCell(Text('')),
                              const DataCell(Text('')),
                              DataCell(Text(filteredTotalDebit.toStringAsFixed(2), style: _headerStyle().copyWith(color: Colors.green[700]))),
                              DataCell(Text(filteredTotalCredit.toStringAsFixed(2), style: _headerStyle().copyWith(color: Colors.red[700]))),
                              const DataCell(Text('')),
                              DataCell(
                                Text(
                                  (filteredTotalDebit - filteredTotalCredit).toStringAsFixed(2),
                                  style: _headerStyle().copyWith(
                                    color: (filteredTotalDebit - filteredTotalCredit) >= 0 ? Colors.green[700] : Colors.red[700],
                                  ),
                                ),
                              ),
                              const DataCell(Text('')),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ), // SingleChildScrollView (horizontal)
              ), // Scrollbar (horizontal)
            ), // SingleChildScrollView (vertical)
          ), // Scrollbar (vertical)
        ), // ClipRRect
      ), // Container
    ), // Expanded
      ],
    );
    
  }

  String _formatCounterpartyType(String raw) {
    final normalized = raw.toLowerCase();
    if (normalized == 'rider') return 'Rider';
    if (normalized == 'vendor') return 'Vendor';
    if (normalized == 'supplier') return 'Supplier';
    return raw.isEmpty ? '' : '${raw[0].toUpperCase()}${raw.substring(1)}';
  }



  void _showClearSuspenseDialog(BuildContext pContext, LedgerEntryModel entry) {
    showDialog(
      context: pContext,
      builder: (ctx) {
        return BlocProvider.value(
          value: pContext.read<LedgerBloc>(),
          child: Provider.value(
            value: pContext.read<JournalRepository>(),
            child: _ClearSuspenseDialog(entry: entry),
          ),
        );
      },
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _friendlyAccountName(String accountId) {
    // Convert snake_case to Title Case words
    // e.g. expense_receivable â†’ Expense Receivable
    // e.g. drawer_payment â†’ Drawer Payment
    // e.g. suspense_holding â†’ Suspense Holding
    // e.g. vat_payable â†’ VAT Payable
    if (accountId.isEmpty) return accountId;

    // Handle special cases
    const friendly = <String, String>{
      'vat_payable': 'VAT',
      'expense_receivable': 'Expense',
      'drawer_payment': 'Cash/Bank',
      'vendor_payable': 'Vendor Payable',
      'supplier_payable': 'Supplier Payable',
      'rider_payable': 'Rider Payable',
      'salary_payable': 'Salary Payable',
      'salary_expense': 'Salary Expense',
      'fine_payable': 'Fine',
      'loan_receivable': 'Loan',
      'cash_account': 'Cash',
      'bank_account': 'Bank',
      'noqodi_wallet': 'Noqodi Wallet',
      'capital_equity': 'Capital',
      'general_expense': 'General Expense',
      'general_revenue': 'General Revenue',
    };
    if (friendly.containsKey(accountId)) return friendly[accountId]!;

    // General snake_case to Title Case conversion
    return accountId
        .split('_')
        .map((word) => word.isEmpty
            ? ''
            : word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }


  // â”€â”€ Trial Balance Tab â”€â”€

  Widget _buildTrialBalanceTab() {
    final entries = _filteredItems;
    if (entries.isEmpty) {
      return Center(
        child: Text(
          'No posted journals yet â€” trial balance will appear here.',
          style: GoogleFonts.poppins(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    final accountSummary = <String, Map<String, double>>{};
    for (final e in entries) {
      if (!accountSummary.containsKey(e.accountName)) {
        accountSummary[e.accountName] = {'debit': 0.0, 'credit': 0.0};
      }
      accountSummary[e.accountName]!['debit'] = accountSummary[e.accountName]!['debit']! + e.debit;
      accountSummary[e.accountName]!['credit'] = accountSummary[e.accountName]!['credit']! + e.credit;
    }

    final summaryList = accountSummary.entries.map((e) {
      final debit = e.value['debit']!;
      final credit = e.value['credit']!;
      return {
        'account': e.key,
        'total_debit': debit,
        'total_credit': credit,
        'balance': debit - credit,
      };
    }).toList();
    summaryList.sort((a, b) => (a['account'] as String).compareTo(b['account'] as String));

    final totalDebit = summaryList.fold<double>(
      0.0,
      (s, e) => s + (e['total_debit'] as num).toDouble(),
    );
    final totalCredit = summaryList.fold<double>(
      0.0,
      (s, e) => s + (e['total_credit'] as num).toDouble(),
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  AppTheme.primaryColor.withValues(alpha: 0.05),
                ),
                columnSpacing: 32,
                columns: [
                  DataColumn(label: Text('Account', style: _headerStyle())),
                  DataColumn(
                    label: Text('Total Debit (AED)', style: _headerStyle()),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text('Total Credit (AED)', style: _headerStyle()),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text('Balance (AED)', style: _headerStyle()),
                    numeric: true,
                  ),
                ],
                rows: [
                  ...summaryList.map((row) {
                    final debit = (row['total_debit'] as num).toDouble();
                    final credit = (row['total_credit'] as num).toDouble();
                    final balance = (row['balance'] as num).toDouble();

                    return DataRow(
                      cells: [
                        DataCell(
                          Text(
                            _friendlyAccountName(row['account']?.toString() ?? ''),
                            style: _cellStyle().copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(debit.toStringAsFixed(2), style: _cellStyle()),
                        ),
                        DataCell(
                          Text(credit.toStringAsFixed(2), style: _cellStyle()),
                        ),
                        DataCell(
                          Text(
                            balance.toStringAsFixed(2),
                            style: _cellStyle().copyWith(
                              color: balance >= 0
                                  ? Colors.green[700]
                                  : Colors.red[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                  // Totals row
                  DataRow(
                    color: WidgetStateProperty.all(
                      AppTheme.primaryColor.withValues(alpha: 0.04),
                    ),
                    cells: [
                      DataCell(
                        Text(
                          'TOTAL',
                          style: _headerStyle().copyWith(fontSize: 14),
                        ),
                      ),
                      DataCell(
                        Text(
                          totalDebit.toStringAsFixed(2),
                          style: _headerStyle().copyWith(fontSize: 14),
                        ),
                      ),
                      DataCell(
                        Text(
                          totalCredit.toStringAsFixed(2),
                          style: _headerStyle().copyWith(fontSize: 14),
                        ),
                      ),
                      DataCell(
                        Text(
                          (totalDebit - totalCredit).toStringAsFixed(2),
                          style: _headerStyle().copyWith(
                            fontSize: 14,
                            color: (totalDebit - totalCredit) >= 0
                                ? Colors.green[700]
                                : Colors.red[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ), // DataTable
            ), // SingleChildScrollView (horizontal)
          ), // SingleChildScrollView (vertical)
        ), // ClipRRect
    ); // Container
  }

  // â”€â”€ Helpers â”€â”€

  TextStyle _headerStyle() => GoogleFonts.poppins(
    fontWeight: FontWeight.bold,
    fontSize: 13,
    color: const Color(0xFF1E293B),
  );

  TextStyle _cellStyle() => GoogleFonts.poppins(fontSize: 13);

  // â”€â”€ Rider Statement Tab â”€â”€

  Widget _buildRiderStatementTab(LedgerLoaded state) {
    return Column(
      children: [
        _buildRiderSelector(state),
        const SizedBox(height: 20),
        if (state.selectedRiderId == null)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_search, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'Select a rider to view their statement',
                    style: GoogleFonts.poppins(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(child: _buildRiderDetails(state)),
      ],
    );
  }

  Widget _buildRiderSelector(LedgerLoaded state) {
    return BlocBuilder<RidersBloc, RidersState>(
      builder: (context, ridersState) {
        final riders = ridersState is RidersLoaded ? ridersState.riders : <RiderModel>[];
        final selectedRider = state.selectedRiderId != null 
          ? riders.where((r) => r.id == state.selectedRiderId).firstOrNull 
          : null;
        
        return InkWell(
          onTap: () => _showRiderSearchDialog(context, riders),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_search, color: AppTheme.primaryColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    selectedRider != null 
                      ? '${selectedRider.name} (${selectedRider.riderCode ?? "NO CODE"})'
                      : 'Search or Select Rider...',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: selectedRider != null ? Colors.black : Colors.grey,
                    ),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, color: Colors.grey),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRiderSearchDialog(BuildContext context, List<RiderModel> allRiders) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = allRiders.where((r) {
              final q = query.toLowerCase();
              return r.name.toLowerCase().contains(q) || 
                     (r.riderCode?.toLowerCase().contains(q) ?? false);
            }).toList();

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: 500,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Search Rider',
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Type name or rider code...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onChanged: (val) {
                        setDialogState(() => query = val);
                      },
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 400),
                      child: filtered.isEmpty 
                        ? Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Text('No matching riders found', style: GoogleFonts.poppins(color: Colors.grey)),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            separatorBuilder: (c, i) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final r = filtered[index];
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                title: Text(r.name, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500)),
                                subtitle: Text(r.riderCode ?? 'NO CODE', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
                                onTap: () {
                                  context.read<LedgerBloc>().add(LoadRiderStatement(r.id));
                                  Navigator.pop(dialogContext);
                                },
                              );
                            },
                          ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRiderDetails(LedgerLoaded state) {
    final entries = state.riderEntries;
    final selectedRiderName = () {
      final ridersState = context.read<RidersBloc>().state;
      if (ridersState is RidersLoaded) {
        final rider = ridersState.riders.where((r) => r.id == state.selectedRiderId).firstOrNull;
        return rider?.name ?? 'Rider';
      }
      return 'Rider';
    }();

    final sorted = [...entries]
      ..sort((a, b) => a.postedAt.compareTo(b.postedAt));

    final totalDebit = sorted.fold<double>(0, (s, e) => s + e.debit);
    final totalCredit = sorted.fold<double>(0, (s, e) => s + e.credit);
    final totalBalance = totalDebit - totalCredit;

    return Column(
      children: [
        Row(
          children: [
            _buildStatCard('Total Debit', 'AED ${totalDebit.toStringAsFixed(2)}', Icons.payments_outlined, Colors.green),
            const SizedBox(width: 16),
            _buildStatCard('Total Credit', 'AED ${totalCredit.toStringAsFixed(2)}', Icons.money_off_outlined, Colors.red),
            const SizedBox(width: 16),
            _buildStatCard('Total Balance', 'AED ${totalBalance.toStringAsFixed(2)}', Icons.account_balance_outlined, AppTheme.primaryColor),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(width: 95, child: Text('Date', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700))),
                      Expanded(flex: 2, child: Text('Name', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700))),
                      const SizedBox(width: 8),
                      Expanded(flex: 4, child: Text('Description', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700))),
                      const SizedBox(width: 8),
                      SizedBox(width: 90, child: Text('Debit', textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700))),
                      const SizedBox(width: 8),
                      SizedBox(width: 90, child: Text('Credit', textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700))),
                      const SizedBox(width: 8),
                      SizedBox(width: 100, child: Text('Balance', textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700))),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: sorted.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final e = sorted[index];
                      final runningBalance = sorted
                          .take(index + 1)
                          .fold<double>(0, (sum, row) => sum + row.debit - row.credit);

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 95,
                              child: Text(
                                DateFormat('dd/MM/yyyy').format(e.postedAt),
                                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                selectedRiderName,
                                style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 4,
                              child: Text(
                                e.journalDescription ?? '-',
                                style: GoogleFonts.poppins(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 90,
                              child: Text(
                                e.debit > 0 ? e.debit.toStringAsFixed(2) : '0.00',
                                textAlign: TextAlign.right,
                                style: GoogleFonts.poppins(fontSize: 12, color: Colors.green.shade700),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 90,
                              child: Text(
                                e.credit > 0 ? e.credit.toStringAsFixed(2) : '0.00',
                                textAlign: TextAlign.right,
                                style: GoogleFonts.poppins(fontSize: 12, color: Colors.red.shade700),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 100,
                              child: Text(
                                runningBalance.toStringAsFixed(2),
                                textAlign: TextAlign.right,
                                style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
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
          ),
        ),
      ],
    );
  }
}


// â”€â”€ Suspense Entry Logic â”€â”€
void _showSuspenseEntryDialog(BuildContext parentContext) {
  showDialog(
    context: parentContext,
    builder: (ctx) {
      return BlocProvider.value(
        value: parentContext.read<LedgerBloc>(),
        child: const _SuspenseDialog(),
      );
    },
  );
}

class _SuspenseDialog extends StatefulWidget {
  const _SuspenseDialog();

  @override
  State<_SuspenseDialog> createState() => _SuspenseDialogState();
}

class _SuspenseDialogState extends State<_SuspenseDialog> {
  final _amountController = TextEditingController();
  final _descController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String _type = 'deposit'; // 'deposit' or 'withdrawal'
  String? _suspenseType;
  Map<String, dynamic>? _selectedDrawer;
  List<Map<String, dynamic>> _drawers = [];
  bool _isLoadingDrawers = true;

  bool _isConverting = false;

  @override
  void initState() {
    super.initState();
    _fetchDrawers();
  }

  Future<void> _fetchDrawers() async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('drawer')
          .select('id, name, type')
          .eq('is_active', true);
      if (mounted) {
        setState(() {
          _drawers = List<Map<String, dynamic>>.from(response);
          if (_drawers.isNotEmpty) {
            _selectedDrawer = _drawers.first;
          }
          _isLoadingDrawers = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingDrawers = false);
    }
  }

  void _submit() async {
    if (!_formKey.currentState!.validate() || _selectedDrawer == null) return;
    setState(() => _isConverting = true);

    try {
      final amt = double.parse(_amountController.text);
      final isDeposit = _type == 'deposit';

      final drawerId = _selectedDrawer!['id'] as String;
      final dType = _selectedDrawer!['type']?.toString().toLowerCase();
      String paymentMethod = 'cash';
      String drawerAccountId = 'cash_account';
      
      if (dType == 'wallet') {
        paymentMethod = 'wallet';
        drawerAccountId = 'noqodi_wallet';
      } else if (dType == 'bank') {
        paymentMethod = 'bank_transfer';
        drawerAccountId = 'bank_account';
      } else {
        paymentMethod = 'cash';
        drawerAccountId = 'cash_account';
      }

      // If Deposit: Debit Bank, Credit Suspense
      // If Withdrawal: Credit Bank, Debit Suspense

      final entry1 = isDeposit
          ? {'account_id': drawerAccountId, 'debitAmount': amt, 'creditAmount': 0.0}
          : {'account_id': drawerAccountId, 'creditAmount': amt, 'debitAmount': 0.0};

      final entry2 = isDeposit
          ? {
              'account_id': 'suspense_holding',
              'creditAmount': amt,
              'debitAmount': 0.0,
            }
          : {
              'account_id': 'suspense_holding',
              'debitAmount': amt,
              'creditAmount': 0.0,
            };

      final journal = JournalModel(
        id: '',
        date: DateTime.now(),
        description: 'Suspense Entry [$_suspenseType]: ${_descController.text}',
        amount: amt,
        status: JournalStatus.draft,
        type: JournalType.suspense,
        drawerId: drawerId,
        paymentMethod: paymentMethod,
        createdByRole: UserRole.accountant,
        entries: [
          JournalEntryModel(
            accountId: entry1['account_id'] as String,
            debitAmount: (entry1['debitAmount'] as double?) ?? 0.0,
            creditAmount: (entry1['creditAmount'] as double?) ?? 0.0,
          ),
          JournalEntryModel(
            accountId: entry2['account_id'] as String,
            debitAmount: (entry2['debitAmount'] as double?) ?? 0.0,
            creditAmount: (entry2['creditAmount'] as double?) ?? 0.0,
          ),
        ],
      );

      final res = await context.read<JournalRepository>().createJournal(journal);
      if (res['journalId'] != null) {
        await Supabase.instance.client
            .from('journals')
            .update({'status': 'posted'})
            .eq('id', res['journalId']!);
      }

      if (mounted) {
        context.read<LedgerBloc>().add(const LoadLedger());
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Suspense transaction logged successfully"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(toUserFriendlyError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isConverting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        "Park Unclear Transaction",
        style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 300, maxWidth: 520),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Use this to record money movements where the matching source is not yet identified.",
              style: GoogleFonts.poppins(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('Deposit'),
                    value: 'deposit',
                    groupValue: _type,
                    onChanged: (v) => setState(() => _type = v!),
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('Withdrawal'),
                    value: 'withdrawal',
                    groupValue: _type,
                    onChanged: (v) => setState(() => _type = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Suspense Type',
                border: OutlineInputBorder(),
              ),
              value: _suspenseType,
              items: const [
                DropdownMenuItem(value: 'Fine Suspense', child: Text('Fine Suspense')),
                DropdownMenuItem(value: 'Salary Suspense', child: Text('Salary Suspense')),
                DropdownMenuItem(value: 'Unknown Deposit', child: Text('Unknown Deposit')),
                DropdownMenuItem(value: 'Advance Suspense', child: Text('Advance Suspense')),
                DropdownMenuItem(value: 'Other', child: Text('Other')),
              ],
              onChanged: (v) => setState(() => _suspenseType = v),
              validator: (v) => v == null || v.isEmpty ? "Required" : null,
            ),
            const SizedBox(height: 12),
            if (_isLoadingDrawers)
              const Center(child: CircularProgressIndicator())
            else if (_drawers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text('No active drawers available', style: GoogleFonts.poppins(color: Colors.red)),
              )
            else
              DropdownButtonFormField<Map<String, dynamic>>(
                decoration: const InputDecoration(
                  labelText: 'Affected Drawer',
                  border: OutlineInputBorder(),
                ),
                value: _selectedDrawer,
                items: _drawers.map((d) {
                  return DropdownMenuItem<Map<String, dynamic>>(
                    value: d,
                    child: Text('${d['name']} (${d['type']})'),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _selectedDrawer = v),
                validator: (v) => v == null ? "Required" : null,
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.isEmpty) ? "Required" : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Description / References',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.isEmpty) ? "Required" : null,
            ),
          ],
        ),
      ),
      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: _isConverting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange[700],
            foregroundColor: Colors.white,
          ),
          child: _isConverting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text("Save to Suspense"),
        ),
      ],
    );
  }
}

class _ClearSuspenseDialog extends StatefulWidget {
  final LedgerEntryModel entry;
  const _ClearSuspenseDialog({required this.entry});

  @override
  State<_ClearSuspenseDialog> createState() => _ClearSuspenseDialogState();
}

class _ClearSuspenseDialogState extends State<_ClearSuspenseDialog> {
  late final TextEditingController _descController;
  String? _selectedAccount;
  final _formKey = GlobalKey<FormState>();
  bool _isClearing = false;

  final List<Map<String, String>> _resolutionAccounts = const [
    {'label': 'Rider Receivable', 'value': 'expense_receivable'},
    {'label': 'Salary Expense', 'value': 'salary_expense'},
    {'label': 'Fine Receivable', 'value': 'fine_receivable'},
    {'label': 'Bank Account', 'value': 'bank_account'},
    {'label': 'Cash Account', 'value': 'cash_account'},
    {'label': 'Noqodi Wallet', 'value': 'noqodi_wallet'},
    {'label': 'Capital Equity', 'value': 'capital_equity'},
    {'label': 'Other', 'value': 'other_account'},
  ];

  @override
  void initState() {
    super.initState();
    _descController =
        TextEditingController(text: "Clearing: ${widget.entry.journalDescription ?? ''}");
    _descController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  String _getHelperText(String? accountId) {
    if (accountId == 'expense_receivable') return 'Use this when a rider owes the company money';
    if (accountId == 'salary_expense') return 'Use this when the amount was a salary payment';
    if (accountId == 'fine_receivable') return 'Use this when the amount was a traffic fine payment';
    if (['bank_account', 'cash_account', 'noqodi_wallet'].contains(accountId)) {
      return 'Use this when money was transferred between drawers';
    }
    if (accountId == 'capital_equity')
      return 'Use this when the owner put money in or withdrew money';
    return '';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isClearing = true);

    try {
      final amt = widget.entry.debit > 0 ? widget.entry.debit : widget.entry.credit;
      
      final journal = JournalModel(
        id: '',
        date: DateTime.now(),
        description: _descController.text,
        amount: amt,
        status: JournalStatus.draft,
        type: JournalType.manualAdjustment,
        createdByRole: UserRole.accountant,
        entries: [
          JournalEntryModel(
            accountId: _selectedAccount!,
            debitAmount: amt,
            creditAmount: 0.0,
          ),
          JournalEntryModel(
            accountId: 'suspense_holding',
            debitAmount: 0.0,
            creditAmount: amt,
          ),
        ],
      );

      final res = await context.read<JournalRepository>().createJournal(journal);
      if (res['journalId'] != null) {
        await Supabase.instance.client
            .from('journals')
            .update({'status': 'posted'})
            .eq('id', res['journalId']!);
      }

      if (mounted) {
        context.read<LedgerBloc>().add(const LoadLedger());
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Suspense cleared successfully"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(toUserFriendlyError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Clear Suspense", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(
                  labelText: 'Resolution Description',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedAccount,
                decoration: const InputDecoration(
                  labelText: 'Resolution Account',
                  border: OutlineInputBorder(),
                  hintText: 'Select resolution account',
                ),
                items: _resolutionAccounts
                    .map((acc) => DropdownMenuItem(
                          value: acc['value'],
                          child: Text(acc['label']!),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedAccount = v),
                validator: (v) => v == null ? "Required" : null,
              ),
              if (_selectedAccount != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _getHelperText(_selectedAccount),
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.blue[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        ElevatedButton(
          onPressed: (_isClearing || _selectedAccount == null || _descController.text.isEmpty)
              ? null
              : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber[700],
            foregroundColor: Colors.white,
          ),
          child: _isClearing
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text("Clear Suspense"),
        ),
      ],
    );
  }
}

