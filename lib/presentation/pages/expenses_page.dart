import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../logic/financial/expense_bloc.dart';
import '../../core/app_theme.dart';
import '../../data/models/expense_model.dart';
import '../../utils/date_utils.dart';
import '../../utils/user_friendly_error.dart';
import '../../data/models/rider_model.dart';
import '../../data/models/expense_category_model.dart';
import '../../services/api_service.dart';
// Post New Journal dialog removed â€” Add Expense dialog deleted

class ExpensesPage extends StatefulWidget {
  final bool isAccountant;
  final String? focusedExpenseId;

  const ExpensesPage({
    super.key,
    required this.isAccountant,
    this.focusedExpenseId,
  });

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  String _filterStatus = 'All'; // Options: All, Pending, Approved, Rejected
  String _actorFilter = 'All'; // Options: All, PRO, ACCOUNTANT
  String? _flashingExpenseId;

  DateTimeRange? _selectedDateRange;
  String _searchQuery = '';
  List<Expense> _allItems = [];
  List<Expense> _filteredItems = [];

  void _applyFilters() {
    setState(() {
      _filteredItems = _allItems.where((e) {
        if (_filterStatus != 'All' && (e.status ?? 'All') != _filterStatus)
          return false;

        if (_selectedDateRange != null) {
          if (e.expenseDate.isEmpty) return false;
          DateTime? d;
          final String _edRaw = e.expenseDate;
          final String _edPart = _edRaw.length >= 10
              ? _edRaw.substring(0, 10)
              : _edRaw;
          d = parseDateOnly(_edPart);
          if (d != null) {
            final date = DateUtils.dateOnly(DateTime(d.year, d.month, d.day));
            final start = DateUtils.dateOnly(_selectedDateRange!.start);
            final end = DateUtils.dateOnly(_selectedDateRange!.end);
            if (date.isBefore(start) || date.isAfter(end)) return false;
          }
        }

        if (_searchQuery.isNotEmpty) {
          final query = _searchQuery.toLowerCase();
          final typeMatch = e.expenseType.toLowerCase().contains(query);
          final riderMatch = (e.riderName ?? '').toLowerCase().contains(query);
          if (!typeMatch && !riderMatch) return false;
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
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryColor,
            ),
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
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[m - 1];
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    if (widget.focusedExpenseId != null) {
      _filterStatus = 'All';
      _actorFilter = 'All';
      _flashingExpenseId = widget.focusedExpenseId;
    }
  }

  void _loadData() {
    context.read<ExpenseBloc>().add(
      LoadExpenses(createdByRole: _actorFilter == 'All' ? null : _actorFilter),
    );
    context.read<ExpenseBloc>().add(const LoadCategories());
  }

  void _updateStatus(String id, String status) {
    // If rejecting, ask for a reason first
    if (status.toLowerCase() == 'rejected') {
      showDialog<String>(
        context: context,
        builder: (context) {
          final controller = TextEditingController();
          return AlertDialog(
            title: const Text('Reject Expense'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'Enter rejection reason',
              ),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text('Confirm'),
              ),
            ],
          );
        },
      ).then((reason) {
        if (reason == null) return; // cancelled
        context.read<ExpenseBloc>().add(
          UpdateExpenseStatus(id: id, status: status, reason: reason),
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Rejecting: $reason')));
      });
      return;
    }

    context.read<ExpenseBloc>().add(
      UpdateExpenseStatus(id: id, status: status),
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Marking as $status...')));
  }

  Future<void> _deleteExpense(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Expense'),
        content: const Text('Are you sure you want to delete this expense?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (mounted) {
        context.read<ExpenseBloc>().add(DeleteExpense(id));
      }
    }
  }

  void _showAddExpenseBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddExpenseForm(
        onSuccess: () {
          _loadData();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Expense submitted for approval'),
              backgroundColor: Colors.green,
            ),
          );
        },
      ),
    );
  }

  IconData _getIconForType(String type) {
    switch (type.toLowerCase()) {
      case 'bike rent':
        return Icons.motorcycle;
      case 'sim card':
        return Icons.sim_card;
      case 'maintenance':
        return Icons.build;
      case 'fuel':
        return Icons.local_gas_station;
      case 'advance':
        return Icons.money;
      default:
        return Icons.attach_money;
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'Approved':
        return Colors.green;
      case 'Rejected':
        return Colors.red;
      case 'Pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          "Expenses Management",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E293B),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          DropdownButton<String>(
            value: _filterStatus,
            underline: const SizedBox(),
            items: ['All', 'Pending', 'Approved', 'Rejected']
                .map(
                  (status) => DropdownMenuItem(
                    value: status,
                    child: Text(
                      status,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF64748B),
                        fontSize: 13,
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _filterStatus = val;
                  _applyFilters();
                });
              }
            },
          ),
          const SizedBox(width: 8),
          if (widget.isAccountant) ...[
            DropdownButton<String>(
              value: _actorFilter,
              underline: const SizedBox(),
              items: ['All', 'PRO', 'ACCOUNTANT']
                  .map(
                    (role) => DropdownMenuItem(
                      value: role,
                      child: Text(
                        role,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF64748B),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _actorFilter = val;
                    _loadData();
                  });
                }
              },
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            icon: const Icon(Icons.date_range, color: AppTheme.primaryColor),
            onPressed: _pickDateRange,
            tooltip: 'Filter by Date Range',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryColor),
            onPressed: _loadData,
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: !widget.isAccountant
          ? FloatingActionButton(
              onPressed: _showAddExpenseBottomSheet,
              backgroundColor: Colors.green,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_selectedDateRange != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.date_range,
                      size: 14,
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_selectedDateRange!.start.day} ${_getMonth(_selectedDateRange!.start.month)} - ${_selectedDateRange!.end.day} ${_getMonth(_selectedDateRange!.end.month)}',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _clearDateRange,
                      child: const Icon(
                        Icons.close,
                        size: 16,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: BlocListener<ExpenseBloc, ExpenseState>(
              listener: (context, state) {
                if (state is ExpenseLoaded) {
                  setState(() {
                    _allItems = state.expenses;
                    _applyFilters();
                  });
                }
              },
              child: BlocBuilder<ExpenseBloc, ExpenseState>(
                builder: (context, state) {
                  if (state is ExpenseLoading && _allItems.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (state is ExpenseError) {
                    return Center(child: Text('Error: ${state.message}'));
                  }

                  final expenses = _filteredItems;
                  if (expenses.isEmpty) {
                    return const Center(child: Text('No matching expenses.'));
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: expenses.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final expense = expenses[index];
                      final isFocused = expense.id == _flashingExpenseId;

                      return Card(
                        elevation: isFocused ? 8 : 2,
                        shape: RoundedRectangleBorder(
                          side: isFocused
                              ? const BorderSide(color: Colors.red, width: 2)
                              : BorderSide.none,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.primaryColor.withValues(alpha: 
                              0.1,
                            ),
                            child: Icon(
                              _getIconForType(expense.expenseType),
                              color: AppTheme.primaryColor,
                            ),
                          ),
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                expense.riderName ?? "Unknown Rider",
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                "AED ${expense.amount.toStringAsFixed(2)}",
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            "${(expense.description?.trim().isNotEmpty ?? false) ? expense.description!.trim() : expense.expenseType} â€¢ ${expense.expenseDate}",
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _getStatusColor(
                                expense.status,
                              ).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              expense.status ?? "Pending",
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _getStatusColor(expense.status),
                              ),
                            ),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (expense.description != null &&
                                      expense.description!.isNotEmpty) ...[
                                    Text(
                                      "Description:",
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      expense.description!,
                                      style: GoogleFonts.poppins(fontSize: 13),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  if (expense.journalId != null) ...[
                                    Text(
                                      "Related Journal ID:",
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                    Text(
                                      expense.journalId!,
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (widget.isAccountant &&
                                          expense.status?.toLowerCase() ==
                                              'pending') ...[
                                        TextButton(
                                          onPressed: () => _updateStatus(
                                            expense.id!,
                                            'Rejected',
                                          ),
                                          child: const Text(
                                            "Reject",
                                            style: TextStyle(color: Colors.red),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton(
                                          onPressed: () => _updateStatus(
                                            expense.id!,
                                            'Approved',
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                          ),
                                          child: const Text("Approve"),
                                        ),
                                      ],
                                      if (!widget.isAccountant &&
                                          expense.status?.toLowerCase() ==
                                              'pending')
                                        IconButton(
                                          onPressed: () =>
                                              _deleteExpense(expense.id!),
                                          icon: const Icon(
                                            Icons.delete,
                                            color: Colors.grey,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddExpenseForm extends StatefulWidget {
  final VoidCallback onSuccess;
  const _AddExpenseForm({required this.onSuccess});

  @override
  State<_AddExpenseForm> createState() => _AddExpenseFormState();
}

class _AddExpenseFormState extends State<_AddExpenseForm> {
  final _formKey = GlobalKey<FormState>();

  RiderModel? _selectedRider;
  ExpenseCategoryModel? _selectedCategory;
  List<RiderModel> _activeRiders = [];
  bool _isLoadingRiders = true;
  final _descriptionController = TextEditingController();
  final _baseAmountController = TextEditingController();

  double _totalAmount = 0.0;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadActiveRiders();
    context.read<ExpenseBloc>().add(const LoadCategories());

    _baseAmountController.addListener(_calculateTotals);
  }

  Future<void> _loadActiveRiders() async {
    setState(() => _isLoadingRiders = true);
    try {
      final rows = await ApiService.instance.getRiders();
      final list = rows
          .where((r) => r.status == RiderStatus.active)
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _activeRiders = list;
        if (_selectedRider != null &&
            !_activeRiders.any((r) => r.id == _selectedRider!.id)) {
          _selectedRider = null;
        }
        _isLoadingRiders = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _activeRiders = [];
        _isLoadingRiders = false;
      });
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _baseAmountController.dispose();
    super.dispose();
  }

  void _calculateTotals() {
    final base = double.tryParse(_baseAmountController.text) ?? 0.0;
    setState(() {
      _totalAmount = base;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRider == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select Rider")),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final baseAmount = double.tryParse(_baseAmountController.text) ?? 0.0;
      final descriptionText = _descriptionController.text.trim();

      final expense = Expense(
        riderId: _selectedRider!.id,
        riderName: _selectedRider!.name,
        expenseType: _selectedCategory?.name ?? 'Expense',
        amount: _totalAmount,
        baseAmount: baseAmount,
        vatRate: 0.0,
        vatAmount: 0.0,
        expenseDate: DateTime.now().toIso8601String().split('T')[0],
        description: descriptionText,
        status: 'pending',
        categoryId: (_selectedCategory?.id.trim().isEmpty ?? true)
            ? null
            : _selectedCategory!.id,
        createdByRole: 'pro',
        isReceivable: false,
        isPayable: true,
      );

      final actionItem = {
        'type': 'journal_pending_approval',
        'title': 'Expense - AED ${_totalAmount.toStringAsFixed(2)}',
        'subtitle': 'Submitted by PRO, awaiting approval',
        'severity': 'warning',
        'responsible_role': 'accountant',
        'route': '/journals',
        'related_entity': 'journal',
      };

      // Use the newly added BLoC event that handles the two-step insert
      context.read<ExpenseBloc>().add(
        CreateExpenseWithAction(expense: expense, actionItem: actionItem),
      );

      Navigator.pop(context);
      widget.onSuccess();
    } catch (e) {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(toUserFriendlyError(e)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: 20,
        left: 24,
        right: 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "Submit New Expense",
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(height: 24),

              // 1. Rider
              DropdownButtonFormField<RiderModel>(
                value: (_selectedRider != null &&
                        _activeRiders.any((r) => r.id == _selectedRider!.id))
                    ? _activeRiders.firstWhere((r) => r.id == _selectedRider!.id)
                    : null,
                decoration: InputDecoration(
                  labelText: "Rider",
                  prefixIcon: const Icon(Icons.person_outline),
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                hint: Text(_isLoadingRiders ? 'Loading riders...' : 'Select rider'),
                items: _activeRiders
                    .map(
                      (r) => DropdownMenuItem(value: r, child: Text(r.name)),
                    )
                    .toList(),
                onChanged: _isLoadingRiders
                    ? null
                    : (v) => setState(() => _selectedRider = v),
                validator: (v) => v == null ? "Required" : null,
              ),
              const SizedBox(height: 16),

              // 2. Category
              BlocBuilder<ExpenseBloc, ExpenseState>(
                builder: (context, state) {
                  const allowedCategoryNames = {'expense', 'fine'};
                  final allCategories = state is ExpenseLoaded
                      ? state.categories
                      : state is ExpenseLoading
                          ? state.categories
                          : <ExpenseCategoryModel>[];
                  final categories = allCategories
                      .where(
                        (c) =>
                            c.isActive &&
                            allowedCategoryNames.contains(
                              c.name.trim().toLowerCase(),
                            ),
                      )
                      .toList();

                  final selected = (_selectedCategory != null &&
                          categories.any((c) => c.id == _selectedCategory!.id))
                      ? categories.firstWhere(
                          (c) => c.id == _selectedCategory!.id,
                        )
                      : null;

                  return DropdownButtonFormField<ExpenseCategoryModel>(
                    value: selected,
                    decoration: InputDecoration(
                      labelText: "Category",
                      prefixIcon: const Icon(Icons.category_outlined),
                      filled: true,
                      fillColor: Colors.grey[50],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    hint: const Text('Select category'),
                    items: categories
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(c.name),
                          ),
                        )
                        .toList(),
                    onChanged: categories.isEmpty
                        ? null
                        : (v) => setState(() => _selectedCategory = v),
                    validator: (v) => v == null ? "Required" : null,
                  );
                },
              ),
              const SizedBox(height: 16),

              // 3. Description
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: "Description (Required)",
                  prefixIcon: const Icon(Icons.description_outlined),
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                maxLines: 2,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return "Description is required";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 4. Base Amount
              TextFormField(
                controller: _baseAmountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: "Base Amount (Required)",
                  prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty || double.tryParse(v) == null)
                    ? "Invalid Amount"
                    : null,
              ),
              const SizedBox(height: 16),

              // 5. Total Amount (Read Only)
              TextFormField(
                readOnly: true,
                decoration: InputDecoration(
                  labelText: "Total Amount",
                  prefixIcon: const Icon(Icons.summarize_outlined),
                  filled: true,
                  fillColor: Colors.grey[200],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                controller: TextEditingController(
                  text: _totalAmount.toStringAsFixed(2),
                ),
              ),
              const SizedBox(height: 16),

              const SizedBox(height: 16),

              // 6. Receipt (Placeholder for now)
              InkWell(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Image upload feature ready to be linked"),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.camera_alt_outlined, color: Colors.grey),
                      SizedBox(width: 12),
                      Text(
                        "Upload Receipt (Optional)",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSubmitting
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
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
                            Text(
                              "Please wait...",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        )
                      : const Text(
                          "Submit",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

