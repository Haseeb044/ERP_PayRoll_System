import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rider_payroll_erp/core/app_theme.dart';
import 'package:rider_payroll_erp/logic/financial/journal_bloc.dart';
import 'package:rider_payroll_erp/logic/auth/auth_bloc.dart';
import 'package:rider_payroll_erp/logic/financial/expense_bloc.dart' as eb;
import 'package:rider_payroll_erp/data/models/expense_model.dart';
import 'package:rider_payroll_erp/logic/drawers/drawer_bloc.dart';
import 'package:rider_payroll_erp/data/models/drawer_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rider_payroll_erp/data/models/journal_model.dart';
import 'package:rider_payroll_erp/data/models/user_model.dart';
import 'package:rider_payroll_erp/data/models/rider_model.dart';
import 'package:rider_payroll_erp/services/api_service.dart';
import '../../utils/date_utils.dart';
// Post New Journal dialog removed — using Complete Journal bottom sheet only

class JournalsPage extends StatefulWidget {
  final String? highlightExpenseId;
  const JournalsPage({super.key, this.highlightExpenseId});

  @override
  State<JournalsPage> createState() => _JournalsPageState();
}

class _ApproveJournalSheet extends StatefulWidget {
  final Expense expense;
  final VoidCallback onPosted;

  const _ApproveJournalSheet({required this.expense, required this.onPosted});

  @override
  State<_ApproveJournalSheet> createState() => _ApproveJournalSheetState();
}

class _ApproveJournalSheetState extends State<_ApproveJournalSheet> {
  String? _selectedDrawerId;
  String? _paymentMethod;
  bool _isReceivable = false;
  bool _isPayable = false;
  String _paymentTiming = 'pay_now';
  String? _receivableEntityType;
  final TextEditingController _receivableAmountController =
      TextEditingController();
  final TextEditingController _applyCreditAmountController =
      TextEditingController(text: '0');
  bool _applyVendorCredit = false;
  double _openVendorCredit = 0.0;
  bool _manualPartyAmountOverride = false;
  bool _isInternalPartyAmountUpdate = false;
  double _lastAutoSyncedPartyAmount = 0.0;

  double get _expenseTotalAmount {
    final computed = widget.expense.baseAmount + widget.expense.vatAmount;
    if (computed > 0) return computed;
    return widget.expense.amount;
  }

  double get _previewDebitTotal {
    final vat = widget.expense.vatAmount;
    if (vat > 0) {
      return (widget.expense.baseAmount + vat);
    }
    return _expenseTotalAmount;
  }

  double get _previewCreditTotal => _expenseTotalAmount;

  double get _previewTotalBalance => _previewDebitTotal - _previewCreditTotal;

  // Active riders for receivable selection
  List<RiderModel> _activeRiders = [];
  String? _selectedReceivableEntityId;
  List<Map<String, dynamic>> _vendors = [];
  List<Map<String, dynamic>> _suppliers = [];

  // Manual journal line editing removed; totals calculated from templates when posting.
  bool _isPosting = false;

  String get _selectedPartyLabel {
    switch (_receivableEntityType) {
      case 'rider':
        return 'Rider';
      case 'vendor':
        return 'Vendor';
      case 'supplier':
        return 'Supplier';
      default:
        return 'Selected Party';
    }
  }

  bool get _isProExpenseRiderLocked {
    return (widget.expense.createdByRole ?? '').toLowerCase() == 'pro' &&
        widget.expense.riderId.trim().isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _setPartyAmount(_expenseTotalAmount, clearManualOverride: true);
    _receivableAmountController.addListener(_onPartyAmountEdited);
    _loadActiveRiders();
    // Expense approval flow is rider-only per product requirement.
    _isReceivable = true;
    _isPayable = false;
    _paymentTiming = 'pay_now';
    _receivableEntityType = 'rider';
    _selectedReceivableEntityId = widget.expense.riderId;
  }

  @override
  void dispose() {
    _receivableAmountController.removeListener(_onPartyAmountEdited);
    _receivableAmountController.dispose();
    _applyCreditAmountController.dispose();
    super.dispose();
  }

  void _onPartyAmountEdited() {
    if (_isInternalPartyAmountUpdate) return;
    final typed = double.tryParse(_receivableAmountController.text.trim());
    if (typed == null) {
      _manualPartyAmountOverride = _receivableAmountController.text.trim().isNotEmpty;
      return;
    }
    _manualPartyAmountOverride = (typed - _lastAutoSyncedPartyAmount).abs() > 0.009;
  }

  void _setPartyAmount(double amount, {bool clearManualOverride = false}) {
    _isInternalPartyAmountUpdate = true;
    _receivableAmountController.text = amount.toStringAsFixed(2);
    _isInternalPartyAmountUpdate = false;
    _lastAutoSyncedPartyAmount = amount;
    if (clearManualOverride) {
      _manualPartyAmountOverride = false;
    }
  }

  void _syncPartyAmountWithExpenseTotal({bool force = false}) {
    if (!(_isReceivable || _isPayable)) {
      _setPartyAmount(_expenseTotalAmount, clearManualOverride: true);
      return;
    }

    final current = double.tryParse(_receivableAmountController.text.trim());
    final isCurrentAuto =
        current != null && (current - _lastAutoSyncedPartyAmount).abs() <= 0.009;

    if (force || !_manualPartyAmountOverride || _receivableAmountController.text.trim().isEmpty || isCurrentAuto) {
      _setPartyAmount(_expenseTotalAmount, clearManualOverride: force);
    }
  }

  Future<void> _loadVendorOpenCredit() async {
    if (!_isPayable || _receivableEntityType != 'vendor' || _selectedReceivableEntityId == null) {
      setState(() {
        _openVendorCredit = 0;
        _applyVendorCredit = false;
        _applyCreditAmountController.text = '0';
      });
      return;
    }

    try {
      final summary = await ApiService.instance.getVendorOpenCreditSummary(
        _selectedReceivableEntityId!,
      );
      final list = (summary['items'] as List?) ?? [];
      final total = list.fold<double>(
        0,
        (sum, item) => sum + ((item['open_amount'] as num?)?.toDouble() ?? 0),
      );
      setState(() {
        _openVendorCredit = total;
      });
    } catch (_) {
      setState(() {
        _openVendorCredit = 0;
      });
    }
  }

  Future<void> _loadActiveRiders() async {
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('riders')
          .select()
          .eq('status', 'active')
          .order('name');
      setState(() {
        _activeRiders = rows
            .map(
              (r) => RiderModel.fromJson(Map<String, dynamic>.from(r as Map)),
            )
            .toList();
        // ensure pre-selection from expense
        _selectedReceivableEntityId = widget.expense.riderId;
      });
    } catch (e) {
      // debugPrint('Error loading active riders: $e');
    }
  }

  Future<void> _loadPartyProfiles() async {
    try {
      if (_receivableEntityType == 'vendor') {
        final rows = await ApiService.instance.getVendors(status: 'active');
        setState(() {
          _vendors = rows;
        });
      } else if (_receivableEntityType == 'supplier') {
        final rows = await ApiService.instance.getSuppliers(status: 'active');
        setState(() {
          _suppliers = rows;
        });
      }
    } catch (e) {
      // ignore until migration is applied
    }
  }

  Future<void> _createPartyInline(String partyType) async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final addressController = TextEditingController();
    final vatNoController = TextEditingController();
    String? duplicateWarning;

    Future<void> checkDuplicateName(StateSetter setModalState) async {
      final typedName = nameController.text.trim();
      if (typedName.isEmpty) {
        setModalState(() => duplicateWarning = null);
        return;
      }

      try {
        final matches = partyType == 'vendor'
          ? await ApiService.instance.getVendors(search: typedName, status: 'active')
          : await ApiService.instance.getSuppliers(search: typedName, status: 'active');
        if (matches.isNotEmpty) {
          final existingName = matches.first['name']?.toString() ?? typedName;
          setModalState(() {
            duplicateWarning =
                'Warning: similar name already exists ($existingName). You can still save.';
          });
        } else {
          setModalState(() => duplicateWarning = null);
        }
      } catch (_) {
        setModalState(() => duplicateWarning = null);
      }
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(
                partyType == 'vendor' ? 'Create New Vendor' : 'Create New Supplier',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Name *',
                        suffixIcon: duplicateWarning != null
                            ? const Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.orange,
                              )
                            : null,
                      ),
                      onChanged: (_) => checkDuplicateName(setModalState),
                    ),
                    if (duplicateWarning != null) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          duplicateWarning!,
                          style: const TextStyle(color: Colors.orange, fontSize: 12),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: phoneController,
                      decoration: const InputDecoration(labelText: 'Phone'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: addressController,
                      decoration: const InputDecoration(labelText: 'Address'),
                    ),
                    if (partyType == 'vendor') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: vatNoController,
                        decoration: const InputDecoration(
                          labelText: 'VAT No (optional)',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (nameController.text.trim().isEmpty) return;
                    Navigator.pop(context, {
                      'name': nameController.text.trim(),
                      'phone': phoneController.text.trim().isEmpty
                          ? null
                          : phoneController.text.trim(),
                      'email': emailController.text.trim().isEmpty
                          ? null
                          : emailController.text.trim(),
                      'address': addressController.text.trim().isEmpty
                          ? null
                          : addressController.text.trim(),
                      'vat_no': vatNoController.text.trim().isEmpty
                          ? null
                          : vatNoController.text.trim(),
                    });
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;

    try {
      final created = partyType == 'vendor'
          ? await ApiService.instance.createVendor(
              name: result['name']?.toString() ?? '',
              phone: result['phone']?.toString(),
              email: result['email']?.toString(),
              address: result['address']?.toString(),
              vatNo: result['vat_no']?.toString(),
              vatApplicable: true,
            )
          : await ApiService.instance.createSupplier(
              name: result['name']?.toString() ?? '',
              phone: result['phone']?.toString(),
              email: result['email']?.toString(),
              address: result['address']?.toString(),
            );
      final createdId = (created['vendor']?['id'] ?? created['supplier']?['id'])?.toString();
      await _loadPartyProfiles();
      if (createdId != null) {
        setState(() => _selectedReceivableEntityId = createdId);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to create $partyType: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _postJournal() async {
    if (_isPosting) return; // prevent duplicate submissions
    setState(() => _isPosting = true);
    // Manual line validation removed; journal lines are generated automatically.
    try {
      final client = Supabase.instance.client;
      final currentUserId = client.auth.currentUser?.id;
      final now = DateTime.now();
      final entryDate =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final expenseDescription = (widget.expense.description?.trim().isNotEmpty ?? false)
          ? widget.expense.description!.trim()
          : widget.expense.expenseType;

      final journalPayload = {
        'entry_date': entryDate,
        'description': expenseDescription,
        'total_amount': _expenseTotalAmount, // Ledger Total (Base + VAT)
        'base_amount': widget.expense.baseAmount,
        'vat_rate': widget.expense.vatRate,
        'vat_amount': widget.expense.vatAmount,
        'status': 'posted',
        'type': 'expense',
        'created_by_user_id': currentUserId,
        'created_by_role': 'accountant',
        'approved_by': currentUserId,
        'approved_at': now.toIso8601String(),
        if (!_isPayable || _paymentTiming == 'pay_now')
          'payment_method': _paymentMethod,
        if (!_isPayable || _paymentTiming == 'pay_now')
          'drawer_id': _selectedDrawerId,
        'is_receivable': _isReceivable,
        'is_payable': _isPayable,
        'payment_timing': _isPayable ? _paymentTiming : 'pay_now',
        if ((_isReceivable || _isPayable) && _receivableEntityType != null)
          'receivable_entity_type': _receivableEntityType,
        if ((_isReceivable || _isPayable) && _selectedReceivableEntityId != null)
          'receivable_entity_id': _selectedReceivableEntityId,
        if ((_isReceivable || _isPayable) && _receivableEntityType != null)
          'party_type': _receivableEntityType,
        if ((_isReceivable || _isPayable) && _selectedReceivableEntityId != null)
          'party_id': _selectedReceivableEntityId,
        if (_isPayable && _applyVendorCredit)
          'apply_credit_amount': double.tryParse(_applyCreditAmountController.text) ?? 0,
        // CRITICAL: receivable_amount is the actual cut from salary, total_amount is the ledger cost.
        if (_isReceivable)
          'receivable_amount':
              double.tryParse(_receivableAmountController.text) ??
              _expenseTotalAmount,
        // Link to rider for statement visibility
        if (_isReceivable && _receivableEntityType == 'rider')
          'rider_id': _selectedReceivableEntityId,
        if (_isPayable && _receivableEntityType == 'rider')
          'rider_id': _selectedReceivableEntityId,
        // Fallback: If not explicitly receivable but expense has a rider_id, link it anyway for tracking
        if (!_isReceivable && !_isPayable) 'rider_id': widget.expense.riderId,
        'receipt_url': widget.expense.receiptUrl,
      };

      // Step 2: Insert journal lines
      // Auto-generate journal lines from template or fall back to two default lines
      List<Map<String, dynamic>> entries = [];
      try {
        final categoryId = widget.expense.categoryId;
        if (categoryId != null) {
          final tplRows = await client
              .from('journal_templates')
              .select('default_accounts')
              .eq('category_id', categoryId)
              .limit(1);
          if (tplRows.isNotEmpty) {
            final defAccounts =
                tplRows[0]['default_accounts'] as List<dynamic>?;
            if (defAccounts != null && defAccounts.isNotEmpty) {
              for (var a in defAccounts) {
                final Map<String, dynamic> acct = Map<String, dynamic>.from(
                  a as Map,
                );
                final acctId =
                    acct['account_id'] ??
                    acct['account'] ??
                    acct['accountId'] ??
                    '';
                final debit =
                    (acct['debit_amount'] ?? acct['debit'] ?? 0) as num? ?? 0;
                final credit =
                    (acct['credit_amount'] ?? acct['credit'] ?? 0) as num? ?? 0;
                entries.add({
                  'account_id': acctId.toString(),
                  'debit_amount': (debit).toDouble(),
                  'credit_amount': (credit).toDouble(),
                });
              }
            }
          }
        }
      } catch (e) {
        // ignore template errors and fall back to defaults
      }

      // If template didn't produce balanced lines, fall back to two default lines
      if (_isPayable && _receivableEntityType != null) {
        final payableAccount = _receivableEntityType == 'vendor'
            ? 'vendor_payable'
            : _receivableEntityType == 'supplier'
                ? 'supplier_payable'
                : 'rider_payable';
        if ((widget.expense.vatAmount) > 0) {
          entries = [
            {
              'account_id': 'expense_receivable',
              'debit_amount': widget.expense.baseAmount,
              'credit_amount': 0.0,
            },
            {
              'account_id': 'vat_payable',
              'debit_amount': widget.expense.vatAmount,
              'credit_amount': 0.0,
            },
            {
              'account_id': payableAccount,
              'debit_amount': 0.0,
              'credit_amount': _expenseTotalAmount,
            },
          ];
        } else {
          entries = [
            {
              'account_id': 'expense_receivable',
              'debit_amount': _expenseTotalAmount,
              'credit_amount': 0.0,
            },
            {
              'account_id': payableAccount,
              'debit_amount': 0.0,
              'credit_amount': _expenseTotalAmount,
            },
          ];
        }
      }

      double totalDeb = entries.fold(
        0.0,
        (s, e) => s + (e['debit_amount'] as double? ?? 0.0),
      );
      double totalCre = entries.fold(
        0.0,
        (s, e) => s + (e['credit_amount'] as double? ?? 0.0),
      );
      if (entries.isEmpty || (totalDeb - totalCre).abs() > 0.001) {
        if ((widget.expense.vatAmount) > 0) {
          entries = [
            {
              'account_id': 'expense_receivable',
              'debit_amount': widget.expense.baseAmount,
              'credit_amount': 0.0,
            },
            {
              'account_id': 'vat_payable',
              'debit_amount': widget.expense.vatAmount,
              'credit_amount': 0.0,
            },
            {
              'account_id': 'drawer_payment',
              'debit_amount': 0.0,
              'credit_amount': _expenseTotalAmount,
              'drawer_id': _selectedDrawerId,
            },
          ];
        } else {
          entries = [
            {
              'account_id': 'expense_receivable',
              'debit_amount': _expenseTotalAmount,
              'credit_amount': 0.0,
            },
            {
              'account_id': 'drawer_payment',
              'debit_amount': 0.0,
              'credit_amount': _expenseTotalAmount,
              'drawer_id': _selectedDrawerId,
            },
          ];
        }
      }

      journalPayload['lines'] = entries
          .map(
            (e) => <String, dynamic>{
              'account_id': e['account_id'],
              'debit_amount': e['debit_amount'],
              'credit_amount': e['credit_amount'],
              if (e['drawer_id'] != null) 'drawer_id': e['drawer_id'],
            },
          )
          .toList();

      final created = await ApiService.instance.createJournalRaw(journalPayload);
      final journalId = (created['journal']?['id'] ?? '').toString();
      if (journalId.isEmpty) {
        throw Exception('Backend did not return created journal id');
      }

        // Step 4: Update expense
      await client
          .from('expenses')
          .update({'status': 'approved', 'journal_id': journalId})
          .eq('id', widget.expense.id!);

      // Step 5: Update action item
      await client
          .from('action_items')
          .update({
            'resolved_by': currentUserId,
            'resolved_at': now.toIso8601String(),
            'resolution_notes': 'Approved and posted by accountant',
          })
          .eq('reference_id', widget.expense.id!);

      if (!mounted) return;
      widget.onPosted();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error posting journal: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Text(
                'Complete Journal for ${widget.expense.expenseType}',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              // Drawer dropdown (deduplicated)
              BlocBuilder<DrawerBloc, DrawerState>(
                builder: (context, state) {
                  List<DrawerModel> drawers = [];
                  if (state is DrawerLoaded)
                    drawers = state.drawers.where((d) => d.isActive).toList();
                  final Map<String, DrawerModel> unique = {};
                  for (final d in drawers) {
                    unique[d.id] = d;
                  }
                  final deduped = unique.values.toList();
                  final safeSelectedDrawer =
                      (_selectedDrawerId != null &&
                          unique.containsKey(_selectedDrawerId))
                      ? _selectedDrawerId
                      : null;
                  return DropdownButtonFormField<String>(
                    value: safeSelectedDrawer,
                    decoration: const InputDecoration(
                      labelText: 'Paid From Drawer',
                    ),
                    items: deduped
                        .map(
                          (d) => DropdownMenuItem(
                            value: d.id,
                            child: Text(d.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedDrawerId = v),
                  );
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _paymentMethod,
                decoration: const InputDecoration(labelText: 'Payment Method'),
                items: ['cash', 'bank_transfer', 'wallet']
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => setState(() => _paymentMethod = v),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: _isReceivable,
                    onChanged: (v) => setState(() {
                      _isReceivable = v ?? false;
                      if (_isReceivable) {
                        _isPayable = false;
                        _paymentTiming = 'pay_now';
                        _receivableEntityType = 'rider';
                      }
                      _syncPartyAmountWithExpenseTotal(force: true);
                    }),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Is Receivable (Recover from $_selectedPartyLabel)',
                    style: GoogleFonts.poppins(),
                  ),
                ],
              ),
              if (_isReceivable) ...[
                if (_receivableEntityType == 'rider') ...[
                  // Deduplicate active riders to avoid duplicate Dropdown values
                  (() {
                    final Map<String, RiderModel> u = {};
                    for (final r in _activeRiders) {
                      u[r.id] = r;
                    }
                    final dedupedRiders = u.values.toList();
                    final safeSelectedRider =
                      (_selectedReceivableEntityId != null &&
                        u.containsKey(_selectedReceivableEntityId))
                      ? _selectedReceivableEntityId
                        : null;
                    return Column(
                      children: [
                        DropdownButtonFormField<String>(
                          value: safeSelectedRider,
                          decoration: const InputDecoration(
                            labelText: 'Select Rider',
                          ),
                          items: dedupedRiders
                              .map(
                                (r) => DropdownMenuItem(
                                  value: r.id,
                                  child: Text(r.name),
                                ),
                              )
                              .toList(),
                          onChanged: _isProExpenseRiderLocked
                              ? null
                              : (v) =>
                                  setState(() => _selectedReceivableEntityId = v),
                        ),
                        const SizedBox(height: 8),
                      ],
                    );
                  })(),
                ],
                const SizedBox(height: 8),
                TextFormField(
                  controller: _receivableAmountController,
                  decoration: InputDecoration(
                    labelText: _isReceivable
                        ? 'Receivable Amount ($_selectedPartyLabel)'
                        : 'Payable Amount ($_selectedPartyLabel)',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // Journal lines are auto-generated from templates or defaults when posting.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Total Debit: AED ${_previewDebitTotal.toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Total Credit: AED ${_previewCreditTotal.toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Total Balance: AED ${_previewTotalBalance.toStringAsFixed(2)}',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _previewTotalBalance.abs() < 0.001
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isPosting
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (_isPosting || _previewTotalBalance.abs() > 0.009)
                          ? null
                          : _postJournal,
                      child: _isPosting
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
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
                          : const Text('Post Journal'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostNewJournalSheet extends StatefulWidget {
  final VoidCallback onPosted;
  const _PostNewJournalSheet({required this.onPosted});

  @override
  State<_PostNewJournalSheet> createState() => _PostNewJournalSheetState();
}

class _PostNewJournalSheetState extends State<_PostNewJournalSheet> {
  final _formKey = GlobalKey<FormState>();
  final _client = Supabase.instance.client;

  // Fields
  final TextEditingController _entryDateController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String? _journalType = 'expense';
  String? _drawerId;
  String? _paymentMethod;
  final TextEditingController _baseAmountController = TextEditingController();
  final TextEditingController _vatRateController = TextEditingController(
    text: '0',
  );
  double _vatAmount = 0.0;
  double _totalAmount = 0.0;
  bool _isReceivable = false;
  bool _isPayable = false;
    String _paymentTiming = 'pay_now';
  String? _receivableEntityType;
  String? _receivableEntityId;
  final TextEditingController _receivableAmountController =
      TextEditingController();
    final TextEditingController _applyCreditAmountController =
      TextEditingController(text: '0');
    bool _applyVendorCredit = false;
    double _openVendorCredit = 0.0;
  bool _manualPartyAmountOverride = false;
  bool _isInternalPartyAmountUpdate = false;
  double _lastAutoSyncedPartyAmount = 0.0;

  bool get _showVatFields => _receivableEntityType == 'vendor';

  String get _selectedPartyLabel {
    switch (_receivableEntityType) {
      case 'rider':
        return 'Rider';
      case 'vendor':
        return 'Vendor';
      case 'supplier':
        return 'Supplier';
      default:
        return 'Selected Party';
    }
  }

  // Active riders for receivable selection
  List<RiderModel> _activeRiders = [];
  List<Map<String, dynamic>> _vendors = [];
  List<Map<String, dynamic>> _suppliers = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _entryDateController.text =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _vatRateController.addListener(_recalcVat);
    _baseAmountController.addListener(_recalcVat);
    _receivableAmountController.addListener(_onPartyAmountEdited);
    _recalcVat();
    _loadActiveRiders();
    _loadPartyProfiles();
    _recalcVat();
  }

  bool _isPosting = false;

  @override
  void dispose() {
    _entryDateController.dispose();
    _descriptionController.dispose();
    _baseAmountController.dispose();
    _vatRateController.dispose();
    _receivableAmountController.removeListener(_onPartyAmountEdited);
    _receivableAmountController.dispose();
    _applyCreditAmountController.dispose();
    super.dispose();
  }

  void _onPartyAmountEdited() {
    if (_isInternalPartyAmountUpdate) return;
    final typed = double.tryParse(_receivableAmountController.text.trim());
    if (typed == null) {
      _manualPartyAmountOverride = _receivableAmountController.text.trim().isNotEmpty;
      return;
    }
    _manualPartyAmountOverride = (typed - _lastAutoSyncedPartyAmount).abs() > 0.009;
  }

  void _setPartyAmount(double amount, {bool clearManualOverride = false}) {
    _isInternalPartyAmountUpdate = true;
    _receivableAmountController.text = amount.toStringAsFixed(2);
    _isInternalPartyAmountUpdate = false;
    _lastAutoSyncedPartyAmount = amount;
    if (clearManualOverride) {
      _manualPartyAmountOverride = false;
    }
  }

  void _syncPartyAmountWithTotal({bool force = false}) {
    if (!(_isReceivable || _isPayable)) {
      _setPartyAmount(_totalAmount, clearManualOverride: true);
      return;
    }

    final current = double.tryParse(_receivableAmountController.text.trim());
    final isCurrentAuto =
        current != null && (current - _lastAutoSyncedPartyAmount).abs() <= 0.009;

    if (force || !_manualPartyAmountOverride || _receivableAmountController.text.trim().isEmpty || isCurrentAuto) {
      _setPartyAmount(_totalAmount, clearManualOverride: force);
    }
  }

  double get _previewDebitTotal {
    if (_showVatFields && _vatAmount > 0) {
      final baseAmount = double.tryParse(_baseAmountController.text) ?? 0.0;
      return baseAmount + _vatAmount;
    }
    return _totalAmount;
  }

  double get _previewCreditTotal => _totalAmount;

  double get _previewTotalBalance => _previewDebitTotal - _previewCreditTotal;

  void _recalcVat() {
    final base = double.tryParse(_baseAmountController.text) ?? 0.0;
    final rate = _showVatFields
        ? (double.tryParse(_vatRateController.text) ?? 0.0)
        : 0.0;
    setState(() {
      _vatAmount = (base * rate) / 100.0;
      _totalAmount = base + _vatAmount;
      _syncPartyAmountWithTotal();
    });
  }

  Future<void> _loadVendorOpenCredit() async {
    if (!_isPayable || _receivableEntityType != 'vendor' || _receivableEntityId == null) {
      setState(() {
        _openVendorCredit = 0;
        _applyVendorCredit = false;
        _applyCreditAmountController.text = '0';
      });
      return;
    }

    try {
      final summary = await ApiService.instance.getVendorOpenCreditSummary(
        _receivableEntityId!,
      );
      final list = (summary['items'] as List?) ?? [];
      final total = list.fold<double>(
        0,
        (sum, item) => sum + ((item['open_amount'] as num?)?.toDouble() ?? 0),
      );
      setState(() {
        _openVendorCredit = total;
        if (_applyVendorCredit) {
          final capped = total > _totalAmount ? _totalAmount : total;
          _applyCreditAmountController.text = capped.toStringAsFixed(2);
        }
      });
    } catch (_) {
      setState(() {
        _openVendorCredit = 0;
        _applyVendorCredit = false;
        _applyCreditAmountController.text = '0';
      });
    }
  }

  Future<void> _loadActiveRiders() async {
    try {
      final rows = await _client
          .from('riders')
          .select()
          .eq('status', 'active')
          .order('name');
      setState(() {
        _activeRiders = (rows as List)
            .map(
              (r) => RiderModel.fromJson(Map<String, dynamic>.from(r as Map)),
            )
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _loadPartyProfiles() async {
    try {
      if (_receivableEntityType == 'vendor') {
        final rows = await ApiService.instance.getVendors(status: 'active');
        setState(() {
          _vendors = rows;
        });
      } else if (_receivableEntityType == 'supplier') {
        final rows = await ApiService.instance.getSuppliers(status: 'active');
        setState(() {
          _suppliers = rows;
        });
      }
    } catch (_) {
      // Keep UI usable even if profile tables are not migrated yet.
    }
  }

  Future<void> _createPartyInline(String partyType) async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final addressController = TextEditingController();
    final vatNoController = TextEditingController();
    String? duplicateWarning;

    Future<void> checkDuplicateName(StateSetter setModalState) async {
      final typedName = nameController.text.trim();
      if (typedName.isEmpty) {
        setModalState(() => duplicateWarning = null);
        return;
      }

      try {
        final matches = partyType == 'vendor'
          ? await ApiService.instance.getVendors(search: typedName, status: 'active')
          : await ApiService.instance.getSuppliers(search: typedName, status: 'active');
        if (matches.isNotEmpty) {
          final existingName = matches.first['name']?.toString() ?? typedName;
          setModalState(() {
            duplicateWarning =
                'Warning: similar name already exists ($existingName). You can still save.';
          });
        } else {
          setModalState(() => duplicateWarning = null);
        }
      } catch (_) {
        setModalState(() => duplicateWarning = null);
      }
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(partyType == 'vendor' ? 'Create New Vendor' : 'Create New Supplier'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Name *',
                        suffixIcon: duplicateWarning != null
                            ? const Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.orange,
                              )
                            : null,
                      ),
                      onChanged: (_) => checkDuplicateName(setModalState),
                    ),
                    if (duplicateWarning != null) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          duplicateWarning!,
                          style: const TextStyle(color: Colors.orange, fontSize: 12),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: phoneController,
                      decoration: const InputDecoration(labelText: 'Phone'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: addressController,
                      decoration: const InputDecoration(labelText: 'Address'),
                    ),
                    if (partyType == 'vendor') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: vatNoController,
                        decoration: const InputDecoration(labelText: 'VAT No (optional)'),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (nameController.text.trim().isEmpty) return;
                    Navigator.pop(context, {
                      'name': nameController.text.trim(),
                      'phone': phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
                      'email': emailController.text.trim().isEmpty ? null : emailController.text.trim(),
                      'address': addressController.text.trim().isEmpty ? null : addressController.text.trim(),
                      'vat_no': vatNoController.text.trim().isEmpty ? null : vatNoController.text.trim(),
                    });
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;

    try {
      final created = partyType == 'vendor'
          ? await ApiService.instance.createVendor(
              name: result['name']?.toString() ?? '',
              phone: result['phone']?.toString(),
              email: result['email']?.toString(),
              address: result['address']?.toString(),
              vatNo: result['vat_no']?.toString(),
              vatApplicable: true,
            )
          : await ApiService.instance.createSupplier(
              name: result['name']?.toString() ?? '',
              phone: result['phone']?.toString(),
              email: result['email']?.toString(),
              address: result['address']?.toString(),
            );
      final createdId = (created['vendor']?['id'] ?? created['supplier']?['id'])?.toString();
      await _loadPartyProfiles();
      if (createdId != null) {
        setState(() => _receivableEntityId = createdId);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to create $partyType: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _postJournal() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isPosting) return;
    setState(() => _isPosting = true);
    try {
      final currentUserId = _client.auth.currentUser?.id;
      final baseAmount = double.tryParse(_baseAmountController.text) ?? 0.0;
      final vatRate = _showVatFields
          ? (double.tryParse(_vatRateController.text) ?? 0.0)
          : 0.0;
      final vatAmount = _showVatFields ? _vatAmount : 0.0;
      final totalAmount = baseAmount + vatAmount;
        final applyCreditAmount = _applyVendorCredit
          ? (double.tryParse(_applyCreditAmountController.text) ?? 0.0)
          : 0.0;
        final normalizedCredit = applyCreditAmount > totalAmount
          ? totalAmount
          : applyCreditAmount;

      final journalPayload = {
        'entry_date': _entryDateController.text,
        'description': _descriptionController.text.trim(),
        'total_amount': totalAmount, // Ledger Total (Base + VAT)
        'base_amount': baseAmount,
        'vat_rate': vatRate,
        'vat_amount': vatAmount,
        'status': 'posted',
        'type': _journalType,
        'created_by_user_id': currentUserId,
        'created_by_role': 'accountant',
        if (!_isPayable || _paymentTiming == 'pay_now')
          'payment_method': _paymentMethod,
        if (!_isPayable || _paymentTiming == 'pay_now') 'drawer_id': _drawerId,
        'is_receivable': _isReceivable,
        'is_payable': _isPayable,
        'payment_timing': _isPayable ? _paymentTiming : 'pay_now',
        if (_isPayable && normalizedCredit > 0)
          'apply_credit_amount': normalizedCredit,
        if ((_isReceivable || _isPayable) && _receivableEntityType != null)
          'receivable_entity_type': _receivableEntityType,
        if ((_isReceivable || _isPayable) && _receivableEntityId != null)
          'receivable_entity_id': _receivableEntityId,
        if ((_isReceivable || _isPayable) && _receivableEntityType != null)
          'party_type': _receivableEntityType,
        if ((_isReceivable || _isPayable) && _receivableEntityId != null)
          'party_id': _receivableEntityId,
        // CRITICAL: receivable_amount is the actual cut from salary, total_amount is the ledger cost.
        if (_isReceivable)
          'receivable_amount':
              double.tryParse(_receivableAmountController.text) ?? totalAmount,
        // Link to rider for statement visibility
        if (_isReceivable && _receivableEntityType == 'rider')
          'rider_id': _receivableEntityId,
        if (_isPayable && _receivableEntityType == 'rider')
          'rider_id': _receivableEntityId,
      };

      // Auto-generate journal lines from template when available, otherwise fall back
      List<Map<String, dynamic>> entries = [];
      try {
        // No category in this form to query templates by, so skip template lookup.
      } catch (e) {
        // ignore
      }

      // Fallback default lines (balanced)
      if (_isPayable && _receivableEntityType != null) {
        final payableAccount = _receivableEntityType == 'vendor'
            ? 'vendor_payable'
            : _receivableEntityType == 'supplier'
                ? 'supplier_payable'
                : 'rider_payable';
        if (vatAmount > 0) {
          entries = [
            {
              'account_id': 'expense_receivable',
              'debit_amount': baseAmount,
              'credit_amount': 0.0,
            },
            {
              'account_id': 'vat_payable',
              'debit_amount': vatAmount,
              'credit_amount': 0.0,
            },
            {
              'account_id': payableAccount,
              'debit_amount': 0.0,
              'credit_amount': totalAmount,
            },
          ];
        } else {
          entries = [
            {
              'account_id': 'expense_receivable',
              'debit_amount': totalAmount,
              'credit_amount': 0.0,
            },
            {
              'account_id': payableAccount,
              'debit_amount': 0.0,
              'credit_amount': totalAmount,
            },
          ];
        }
      } else {
        if (vatAmount > 0) {
          entries = [
            {
              'account_id': 'expense_receivable',
              'debit_amount': baseAmount,
              'credit_amount': 0.0,
            },
            {
              'account_id': 'vat_payable',
              'debit_amount': vatAmount,
              'credit_amount': 0.0,
            },
            {
              'account_id': 'drawer_payment',
              'debit_amount': 0.0,
              'credit_amount': totalAmount,
              if (_drawerId != null) 'drawer_id': _drawerId,
            },
          ];
        } else {
          entries = [
            {
              'account_id': 'expense_receivable',
              'debit_amount': totalAmount,
              'credit_amount': 0.0,
            },
            {
              'account_id': 'drawer_payment',
              'debit_amount': 0.0,
              'credit_amount': totalAmount,
              if (_drawerId != null) 'drawer_id': _drawerId,
            },
          ];
        }
      }

      journalPayload['lines'] = entries
          .map(
            (e) => <String, dynamic>{
              'account_id': e['account_id'],
              'debit_amount': e['debit_amount'],
              'credit_amount': e['credit_amount'],
              if (e['drawer_id'] != null) 'drawer_id': e['drawer_id'],
            },
          )
          .toList();

      final created = await ApiService.instance.createJournalRaw(journalPayload);
      final journalId = (created['journal']?['id'] ?? '').toString();
      if (journalId.isEmpty) {
        throw Exception('Backend did not return created journal id');
      }

      if (!mounted) return;
      // Navigator.pop(context); // REMOVED redundant pop; onPosted caller handles this
      widget.onPosted();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error posting journal: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
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
              const SizedBox(height: 12),
              Text(
                'Post New Journal',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              // Entry date
              TextFormField(
                controller: _entryDateController,
                decoration: const InputDecoration(
                  labelText: 'Entry Date (yyyy-MM-dd)',
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 8),

              // Description required
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 8),

              // Journal Type
              DropdownButtonFormField<String>(
                value: _journalType,
                decoration: const InputDecoration(labelText: 'Journal Type'),
                items: const [
                  DropdownMenuItem(value: 'expense', child: Text('Expense')),
                  DropdownMenuItem(value: 'salary', child: Text('Salary')),
                  DropdownMenuItem(value: 'fine', child: Text('Fine')),
                  DropdownMenuItem(value: 'loan', child: Text('Loan')),
                  DropdownMenuItem(
                    value: 'manual_adjustment',
                    child: Text('Manual Adjustment'),
                  ),
                ],
                onChanged: (v) => setState(() => _journalType = v),
              ),
              const SizedBox(height: 8),

              // Drawer dropdown (active only, deduped)
              BlocBuilder<DrawerBloc, DrawerState>(
                builder: (context, state) {
                  List<DrawerModel> drawers = [];
                  if (state is DrawerLoaded)
                    drawers = state.drawers.where((d) => d.isActive).toList();
                  final Map<String, DrawerModel> unique = {};
                  for (final d in drawers) {
                    unique[d.id] = d;
                  }
                  final deduped = unique.values.toList();
                  final safeSelected =
                      (_drawerId != null && unique.containsKey(_drawerId))
                      ? _drawerId
                      : null;
                  return DropdownButtonFormField<String>(
                    value: safeSelected,
                    decoration: const InputDecoration(labelText: 'Drawer'),
                    items: deduped
                        .map(
                          (d) => DropdownMenuItem(
                            value: d.id,
                            child: Text(
                              '${d.name} • ${d.balance.toStringAsFixed(2)}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _drawerId = v),
                  );
                },
              ),
              const SizedBox(height: 8),

              // Payment method
              DropdownButtonFormField<String>(
                value: _paymentMethod,
                decoration: const InputDecoration(labelText: 'Payment Method'),
                items: ['cash', 'bank_transfer', 'wallet']
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => setState(() => _paymentMethod = v),
              ),
              const SizedBox(height: 8),

              // Base amount
              TextFormField(
                controller: _baseAmountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Base Amount'),
                validator: (v) =>
                    (v == null || v.isEmpty || double.tryParse(v) == null)
                    ? 'Invalid'
                    : null,
              ),
              const SizedBox(height: 8),

              if (_showVatFields) ...[
                // VAT rate
                TextFormField(
                  controller: _vatRateController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'VAT Rate (%)'),
                ),
                const SizedBox(height: 8),

                // VAT amount (read only)
                TextFormField(
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'VAT Amount'),
                  controller: TextEditingController(
                    text: _vatAmount.toStringAsFixed(2),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Total amount (read only)
              TextFormField(
                readOnly: true,
                decoration: const InputDecoration(labelText: 'Total Amount'),
                controller: TextEditingController(
                  text: _totalAmount.toStringAsFixed(2),
                ),
              ),
              const SizedBox(height: 8),

              // Checkboxes with mutual exclusivity
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: _isReceivable,
                        onChanged: (v) => setState(() {
                          _isReceivable = v ?? false;
                          if (_isReceivable) {
                            _isPayable = false;
                            _paymentTiming = 'pay_now';
                          }
                          _syncPartyAmountWithTotal(force: true);
                        }),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Is Receivable (Recover from $_selectedPartyLabel)',
                        style: GoogleFonts.poppins(),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Checkbox(
                        value: _isPayable,
                        onChanged: (v) => setState(() {
                          _isPayable = v ?? false;
                          if (_isPayable) {
                            _isReceivable = false;
                            _paymentTiming = 'pay_now';
                          }
                          _syncPartyAmountWithTotal(force: true);
                          _loadVendorOpenCredit();
                        }),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Is Payable (Pay to $_selectedPartyLabel)',
                        style: GoogleFonts.poppins(),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Unified Entity Selection (Visible if either is checked)
              if (_isReceivable || _isPayable) ...[
                if (_isPayable) ...[
                  DropdownButtonFormField<String>(
                    value: _paymentTiming,
                    decoration: InputDecoration(
                      labelText: 'Payment Timing',
                      prefixIcon: const Icon(Icons.schedule_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'pay_now', child: Text('Pay Now')),
                      DropdownMenuItem(value: 'pay_later', child: Text('Pay Later')),
                    ],
                    onChanged: (v) => setState(() => _paymentTiming = v ?? 'pay_now'),
                  ),
                  const SizedBox(height: 12),
                ],
                DropdownButtonFormField<String>(
                  value: _receivableEntityType,
                  decoration: InputDecoration(
                    labelText: _isReceivable
                        ? 'Deduction Recipient Type'
                        : 'Payment Recipient Type',
                    prefixIcon: const Icon(Icons.people_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'rider', child: Text('Rider')),
                    DropdownMenuItem(value: 'vendor', child: Text('Vendor')),
                    DropdownMenuItem(
                      value: 'supplier',
                      child: Text('Supplier'),
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    _receivableEntityType = v;
                    _receivableEntityId = null;
                    if (_receivableEntityType != 'vendor') {
                      _vatRateController.text = '0';
                    }
                    _recalcVat();
                    _loadPartyProfiles();
                    _loadVendorOpenCredit();
                  }),
                ),
                const SizedBox(height: 12),
                if (_receivableEntityType == 'rider') ...[
                  DropdownButtonFormField<String>(
                    value: _receivableEntityId,
                    decoration: InputDecoration(
                      labelText: 'Select Rider',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    items: _activeRiders
                        .map(
                          (r) => DropdownMenuItem(
                            value: r.id,
                            child: Text(r.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _receivableEntityId = v),
                    validator: (v) =>
                        (v == null) ? 'Rider selection is required' : null,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_receivableEntityType == 'vendor') ...[
                  DropdownButtonFormField<String>(
                    value: _receivableEntityId,
                    decoration: InputDecoration(
                      labelText: 'Select Vendor',
                      prefixIcon: const Icon(Icons.storefront_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    items: _vendors
                        .map(
                          (v) => DropdownMenuItem(
                            value: v['id']?.toString(),
                            child: Text(
                              '${v['name'] ?? ''} (${v['vendor_code'] ?? 'vendor'})',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _receivableEntityId = v),
                    onSaved: (_) => _loadVendorOpenCredit(),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Vendor selection is required' : null,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _createPartyInline('vendor'),
                      icon: const Icon(Icons.add_business_outlined),
                      label: const Text('Create New Vendor'),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_receivableEntityType == 'supplier') ...[
                  DropdownButtonFormField<String>(
                    value: _receivableEntityId,
                    decoration: InputDecoration(
                      labelText: 'Select Supplier',
                      prefixIcon: const Icon(Icons.local_shipping_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    items: _suppliers
                        .map(
                          (s) => DropdownMenuItem(
                            value: s['id']?.toString(),
                            child: Text(
                              '${s['name'] ?? ''} (${s['supplier_code'] ?? 'supplier'})',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _receivableEntityId = v),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Supplier selection is required' : null,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _createPartyInline('supplier'),
                      icon: const Icon(Icons.add_business_outlined),
                      label: const Text('Create New Supplier'),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_isPayable && _receivableEntityType == 'vendor' && _openVendorCredit > 0) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      border: Border.all(color: Colors.orange.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Previous vendor credit available: AED ${_openVendorCredit.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.orange),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                        value: _applyVendorCredit,
                        onChanged: (v) => setState(() {
                          _applyVendorCredit = v ?? false;
                          if (_applyVendorCredit) {
                            final suggested = _openVendorCredit > _totalAmount
                                ? _totalAmount
                                : _openVendorCredit;
                            _applyCreditAmountController.text =
                                suggested.toStringAsFixed(2);
                          } else {
                            _applyCreditAmountController.text = '0';
                          }
                        }),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Apply previous vendor credit now')),
                    ],
                  ),
                  if (_applyVendorCredit) ...[
                    TextFormField(
                      controller: _applyCreditAmountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Apply Credit Amount',
                        prefixIcon: const Icon(Icons.discount_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
                TextFormField(
                  controller: _receivableAmountController,
                  decoration: InputDecoration(
                    labelText: _isReceivable
                        ? 'Receivable Amount ($_selectedPartyLabel)'
                        : 'Payable Amount ($_selectedPartyLabel)',
                    prefixIcon: const Icon(Icons.attach_money),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 12),
              ],

              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Total Debit: AED ${_previewDebitTotal.toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Total Credit: AED ${_previewCreditTotal.toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Total Balance: AED ${_previewTotalBalance.toStringAsFixed(2)}',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _previewTotalBalance.abs() < 0.001
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (_isPosting || _previewTotalBalance.abs() > 0.009)
                          ? null
                          : () {
                              if (_formKey.currentState!.validate())
                                _postJournal();
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                      child: _isPosting
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
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
                          : const Text('Post Journal'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _JournalsPageState extends State<JournalsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Map<String, GlobalKey> _pendingKeys = {};
  String? _highlightExpenseId;

  DateTimeRange? _selectedDateRange;
  String _searchQuery = '';

  List<Expense> _allPendingItems = [];
  List<Expense> _filteredPendingItems = [];

  List<JournalModel> _allHistoryItems = [];
  List<JournalModel> _filteredHistoryItems = [];
  bool _isLoadingHistory = true;

  List<Map<String, dynamic>> _allPayableItems = [];
  List<Map<String, dynamic>> _filteredPayableItems = [];
  bool _isLoadingPayables = true;
  final Map<String, bool> _isPayingByJournalId = {};

  void _applyFilters() {
    setState(() {
      _filteredPendingItems = _allPendingItems.where((e) {
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

      _filteredHistoryItems = _allHistoryItems.where((j) {
        if (_selectedDateRange != null) {
          final date = DateUtils.dateOnly(j.date);
          final start = DateUtils.dateOnly(_selectedDateRange!.start);
          final end = DateUtils.dateOnly(_selectedDateRange!.end);
          if (date.isBefore(start) || date.isAfter(end)) return false;
        }
        if (_searchQuery.isNotEmpty) {
          final query = _searchQuery.toLowerCase();
          if (!j.description.toLowerCase().contains(query)) return false;
        }
        return true;
      }).toList();

      _filteredPayableItems = _allPayableItems.where((p) {
        if (_selectedDateRange != null) {
          final raw = p['entry_date']?.toString() ?? '';
          final part = raw.length >= 10 ? raw.substring(0, 10) : raw;
          final d = parseDateOnly(part);
          if (d != null) {
            final date = DateUtils.dateOnly(DateTime(d.year, d.month, d.day));
            final start = DateUtils.dateOnly(_selectedDateRange!.start);
            final end = DateUtils.dateOnly(_selectedDateRange!.end);
            if (date.isBefore(start) || date.isAfter(end)) return false;
          }
        }
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          final desc = (p['description']?.toString() ?? '').toLowerCase();
          final vendor = (p['vendor_name']?.toString() ?? '').toLowerCase();
          final status = (p['settlement_status']?.toString() ?? '').toLowerCase();
          if (!desc.contains(q) && !vendor.contains(q) && !status.contains(q)) {
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadJournals();
    _loadVendorPayables();
    _highlightExpenseId = widget.highlightExpenseId;
    // Load expenses for pending approval list when accountant
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated &&
        authState.user.role == UserRole.accountant) {
      context.read<eb.ExpenseBloc>().add(const eb.LoadExpenses());
      context.read<DrawerBloc>().add(const LoadDrawers());
    }
  }

  Future<void> _loadJournals() async {
    setState(() => _isLoadingHistory = true);
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('journals')
          .select('*, expenses(expense_type)')
          .inFilter('status', ['posted', 'reversed'])
          .order('entry_date', ascending: false);

      if (!mounted) return;

      final journals = (response as List)
          .map(
            (j) => JournalModel.fromJson(Map<String, dynamic>.from(j as Map)),
          )
          .toList();

      setState(() {
        _allHistoryItems = journals;
        _isLoadingHistory = false;
        _applyFilters();
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _loadVendorPayables() async {
    setState(() => _isLoadingPayables = true);
    try {
      final supabase = Supabase.instance.client;
      final rows = await supabase
          .from('journals')
          .select(
            'id, entry_date, description, party_id, total_amount, original_payable_amount, settled_amount, outstanding_amount, settlement_status, payment_timing, status, created_at, party_type, receivable_entity_type',
          )
          .eq('status', 'posted')
          .eq('is_payable', true)
          .or('party_type.eq.vendor,receivable_entity_type.eq.vendor')
          .order('entry_date', ascending: false);

      final journals = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((j) {
            final timing = (j['payment_timing']?.toString() ?? '').trim().toLowerCase();
            final settlement =
                (j['settlement_status']?.toString() ?? '').trim().toLowerCase();
            final total = (j['total_amount'] as num?)?.toDouble() ?? 0.0;
            final settled = (j['settled_amount'] as num?)?.toDouble() ?? 0.0;
            final outstandingRaw = (j['outstanding_amount'] as num?)?.toDouble();
            final outstanding = outstandingRaw ?? (total - settled);

            // Keep Vendor Payables focused on unsettled pay-later liabilities,
            // while still supporting legacy rows where payment_timing is missing.
            final isPayLaterLike = timing == 'pay_later' || timing.isEmpty;
            final isUnsettled =
                outstanding > 0.009 || settlement == 'open' || settlement == 'partially_settled';
            return isPayLaterLike && isUnsettled;
          })
          .toList();

      final vendorIds = journals
          .map((j) => j['party_id']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toSet()
          .toList();

      final vendorNameById = <String, String>{};
      if (vendorIds.isNotEmpty) {
        final vendors = await supabase
            .from('vendors')
            .select('id, name, vendor_code')
            .inFilter('id', vendorIds);
        for (final v in (vendors as List)) {
          final row = Map<String, dynamic>.from(v as Map);
          final id = row['id']?.toString();
          if (id == null || id.isEmpty) continue;
          final code = row['vendor_code']?.toString();
          final name = row['name']?.toString() ?? 'Unknown Vendor';
          vendorNameById[id] = (code != null && code.isNotEmpty)
              ? '$name ($code)'
              : name;
        }
      }

      for (final j in journals) {
        final vendorId = j['party_id']?.toString();
        j['vendor_name'] = vendorId != null ? (vendorNameById[vendorId] ?? 'Unknown Vendor') : 'Unknown Vendor';
      }

      if (!mounted) return;
      setState(() {
        _allPayableItems = journals;
        _isLoadingPayables = false;
        _applyFilters();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingPayables = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Add Expense dialog removed — no bottom sheet to show

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final bool isAccountant =
        authState is AuthAuthenticated &&
        authState.user.role == UserRole.accountant;

    return BlocListener<JournalBloc, JournalState>(
      listener: (context, state) {
        if (state is JournalLoaded || state is JournalSuccess) {
          _loadJournals();
          _loadVendorPayables();
          // Also refresh expenses and drawers so the 'Pending' tab and balances update instantly
          context.read<eb.ExpenseBloc>().add(const eb.LoadExpenses());
          context.read<DrawerBloc>().add(const LoadDrawers());
        }
      },
      child: Scaffold(
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
                    'Journals & Expenses',
                    style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  Row(
                    children: [
                      if (isAccountant)
                        IconButton(
                          icon: const Icon(Icons.add, color: Colors.green),
                          onPressed: _showPostNewJournalSheet,
                          tooltip: 'Post New Journal',
                        ),
                      IconButton(
                        icon: const Icon(
                          Icons.date_range,
                          color: AppTheme.primaryColor,
                        ),
                        onPressed: _pickDateRange,
                        tooltip: 'Filter by Date Range',
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.refresh,
                          color: AppTheme.primaryColor,
                        ),
                        onPressed: () {
                          _loadJournals();
                          _loadVendorPayables();
                        },
                        tooltip: 'Refresh Journals',
                      ),
                      const SizedBox(width: 16),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppTheme.primaryColor.withOpacity(0.3),
                        ),
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
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              if (isAccountant)
                TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: "Pending Approval"),
                    Tab(text: "Journal History"),
                    Tab(text: "Vendor Payables"),
                  ],
                  labelColor: AppTheme.primaryColor,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: AppTheme.primaryColor,
                  labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                )
              else
                Text(
                  "My Transactions",
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
              const SizedBox(height: 24),
              Expanded(
                child: isAccountant
                    ? TabBarView(
                        controller: _tabController,
                        children: [
                          _buildPendingApprovalSection(),
                          _buildJournalHistorySection(isAccountant: true),
                          _buildVendorPayablesSection(),
                        ],
                      )
                    : _buildJournalHistorySection(isAccountant: false),
              ),
            ],
          ),
        ),
      ),
    );
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

  Widget _buildPendingApprovalSection() {
    return BlocListener<eb.ExpenseBloc, eb.ExpenseState>(
      listener: (context, state) {
        if (state is eb.ExpenseLoaded) {
          final allDocs = state.expenses;
          final filteredDocs = allDocs
              .where(
                (e) =>
                    (e.status?.toLowerCase() == 'pending') &&
                    (e.journalId == null),
              )
              .toList();
          final Map<String, Expense> _unique = {};
          for (var e in filteredDocs) {
            if (e.id != null) _unique[e.id!] = e;
          }
          _allPendingItems = _unique.values.toList();
          _applyFilters();
        }
      },
      child: Builder(
        builder: (context) {
          final expenseState = context.watch<eb.ExpenseBloc>().state;
          if (expenseState is eb.ExpenseLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final pending = _filteredPendingItems;
          if (pending.isEmpty) {
            return Center(
              child: Text(
                "No pending approvals",
                style: GoogleFonts.poppins(color: Colors.grey),
              ),
            );
          }

          for (var e in pending) {
            _pendingKeys.putIfAbsent(e.id ?? '', () => GlobalKey());
          }

          if (_highlightExpenseId != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final key = _pendingKeys[_highlightExpenseId!];
              if (key != null && key.currentContext != null) {
                try {
                  Scrollable.ensureVisible(
                    key.currentContext!,
                    duration: const Duration(milliseconds: 300),
                  );
                } catch (_) {}
              }
              setState(() => _highlightExpenseId = null);
            });
          }

          return ListView.separated(
            itemCount: pending.length,
            separatorBuilder: (context, index) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final exp = pending[index];
              final isHighlighted =
                  _highlightExpenseId != null && exp.id == _highlightExpenseId;

              String dateFormatted = "Unknown Date";
              if (exp.expenseDate.isNotEmpty) {
                final String _edRaw = exp.expenseDate;
                final String _edPart = _edRaw.length >= 10
                    ? _edRaw.substring(0, 10)
                    : _edRaw;
                final d = parseDateOnly(_edPart);
                if (d != null) {
                  dateFormatted = "${d.day}/${d.month}/${d.year}";
                }
              }
              final roleText = exp.createdByRole?.toUpperCase() ?? 'NONE';

              return Container(
                key: _pendingKeys[exp.id ?? ''],
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isHighlighted
                      ? Colors.yellow.withValues(alpha: 0.2)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.hourglass_empty,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (exp.description?.trim().isNotEmpty ?? false)
                                ? exp.description!.trim()
                                : exp.expenseType,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$dateFormatted • Created by $roleText',
                            style: GoogleFonts.poppins(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '⏱ Pending expense • needs drawer & approval',
                            style: GoogleFonts.poppins(
                              color: Colors.orange,
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'AED ${exp.amount.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade400,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'DRAFT',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OutlinedButton(
                              onPressed: () => _rejectExpense(exp),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('Reject'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () => _showApproveDialog(exp),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('Approve'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildJournalHistorySection({required bool isAccountant}) {
    if (_isLoadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }

    final journals = _filteredHistoryItems;

    if (journals.isEmpty) {
      return Center(
        child: Text(
          "No records found",
          style: GoogleFonts.poppins(color: Colors.grey),
        ),
      );
    }

    return ListView.separated(
      itemCount: journals.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final journal = journals[index];
        return _buildJournalCard(context, journal, isAccountant);
      },
    );
  }

  Widget _buildVendorPayablesSection() {
    if (_isLoadingPayables) {
      return const Center(child: CircularProgressIndicator());
    }

    final payables = _filteredPayableItems;
    if (payables.isEmpty) {
      return Center(
        child: Text(
          'No vendor payables found',
          style: GoogleFonts.poppins(color: Colors.grey),
        ),
      );
    }

    return ListView.separated(
      itemCount: payables.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final item = payables[index];
        final journalId = item['id']?.toString() ?? '';
        final total = (item['total_amount'] as num?)?.toDouble() ?? 0;
        final original = (item['original_payable_amount'] as num?)?.toDouble() ?? total;
        final settled = (item['settled_amount'] as num?)?.toDouble() ?? 0;
        final outstanding = (item['outstanding_amount'] as num?)?.toDouble() ?? 0;
        final status = (item['settlement_status']?.toString() ?? 'open').toLowerCase();
        final canPay = outstanding > 0.009 && status != 'settled';
        final isPaying = _isPayingByJournalId[journalId] == true;

        final statusColor = status == 'settled'
            ? Colors.green
            : status == 'partially_settled'
                ? Colors.orange
                : Colors.red;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item['vendor_name']?.toString() ?? 'Unknown Vendor',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status.replaceAll('_', ' ').toUpperCase(),
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                item['description']?.toString() ?? '-',
                style: GoogleFonts.poppins(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  Text('Original: AED ${original.toStringAsFixed(2)}', style: GoogleFonts.poppins(fontSize: 12)),
                  Text('Settled: AED ${settled.toStringAsFixed(2)}', style: GoogleFonts.poppins(fontSize: 12)),
                  Text('Outstanding: AED ${outstanding.toStringAsFixed(2)}', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: (!canPay || isPaying)
                      ? null
                      : () => _showPayVendorDialog(item),
                  icon: isPaying
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.payments_outlined, size: 18),
                  label: Text(isPaying ? 'Please wait...' : 'Pay Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showPayVendorDialog(Map<String, dynamic> payable) async {
    final journalId = payable['id']?.toString() ?? '';
    final outstanding = (payable['outstanding_amount'] as num?)?.toDouble() ?? 0;
    if (journalId.isEmpty || outstanding <= 0) return;

    final amountController = TextEditingController(
      text: outstanding.toStringAsFixed(2),
    );
    final noteController = TextEditingController(
      text: 'Vendor payment settlement for $journalId',
    );
    final formKey = GlobalKey<FormState>();

    String paymentMethod = 'bank_transfer';
    String? selectedDrawerId;
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            final drawerState = context.read<DrawerBloc>().state;
            final drawers = drawerState is DrawerLoaded
                ? drawerState.drawers.where((d) => d.isActive).toList()
                : <DrawerModel>[];

            selectedDrawerId ??= drawers.isNotEmpty ? drawers.first.id : null;

            return AlertDialog(
              title: Text(
                'Pay Vendor Payable',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
              ),
              content: Form(
                key: formKey,
                child: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Outstanding: AED ${outstanding.toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Payment Amount'),
                        validator: (v) {
                          final value = double.tryParse((v ?? '').trim());
                          if (value == null || value <= 0) {
                            return 'Enter a valid amount';
                          }
                          if (value > outstanding) {
                            return 'Amount cannot exceed outstanding';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: paymentMethod,
                        decoration: const InputDecoration(labelText: 'Payment Method'),
                        items: const [
                          DropdownMenuItem(value: 'cash', child: Text('cash')),
                          DropdownMenuItem(value: 'bank_transfer', child: Text('bank_transfer')),
                          DropdownMenuItem(value: 'wallet', child: Text('wallet')),
                        ],
                        onChanged: (v) => setLocalState(() => paymentMethod = v ?? 'bank_transfer'),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: selectedDrawerId,
                        decoration: const InputDecoration(labelText: 'Drawer'),
                        items: drawers
                            .map((d) => DropdownMenuItem(value: d.id, child: Text(d.name)))
                            .toList(),
                        onChanged: (v) => setLocalState(() => selectedDrawerId = v),
                        validator: (v) => (v == null || v.isEmpty) ? 'Drawer is required' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: noteController,
                        decoration: const InputDecoration(labelText: 'Description (optional)'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          final amount = double.tryParse(amountController.text.trim()) ?? 0;
                          if (selectedDrawerId == null || selectedDrawerId!.isEmpty) return;

                          setLocalState(() => isSubmitting = true);
                          if (mounted) {
                            setState(() => _isPayingByJournalId[journalId] = true);
                          }

                          try {
                            await ApiService.instance.payVendorJournal(
                              journalId: journalId,
                              amount: amount,
                              drawerId: selectedDrawerId!,
                              paymentMethod: paymentMethod,
                              description: noteController.text.trim(),
                            );

                            if (!mounted) return;
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Vendor payment posted successfully'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            await _loadVendorPayables();
                            await _loadJournals();
                            context.read<DrawerBloc>().add(const LoadDrawers());
                          } catch (e) {
                            if (!mounted) return;
                            setLocalState(() => isSubmitting = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Payment failed: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          } finally {
                            if (mounted) {
                              setState(() => _isPayingByJournalId[journalId] = false);
                            }
                          }
                        },
                  child: isSubmitting
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
                      : const Text('Pay'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildJournalCard(
    BuildContext context,
    JournalModel journal,
    bool isAccountant,
  ) {
    final bool isPosted = journal.status == JournalStatus.posted;
    final bool isReversed = journal.status == JournalStatus.reversed;

    Color statusColor;
    if (isReversed) {
      statusColor = Colors.red.shade400;
    } else {
      statusColor = journal.type == JournalType.expense
          ? Colors.red
          : Colors.green;
    }

    final String rawDescription = journal.description.trim();
    final String normalized = rawDescription.toLowerCase();
    final bool isGenericFineText =
        normalized == 'fine' ||
        normalized == 'for fine' ||
        normalized == 'for_fine' ||
        normalized == 'for fines';
    final String displayTitle =
        isGenericFineText && (journal.expenseType?.trim().isNotEmpty ?? false)
        ? journal.expenseType!.trim()
        : rawDescription;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isReversed ? Colors.grey.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(16),
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
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isReversed
                  ? Icons.undo
                  : (journal.amount < 0
                        ? Icons.arrow_downward
                        : Icons.arrow_upward),
              color: statusColor,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayTitle,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    decoration: isReversed ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "${journal.date.day}/${journal.date.month}/${journal.date.year} • Created by ${journal.createdByRole.name.toUpperCase()}",
                  style: GoogleFonts.poppins(color: Colors.grey, fontSize: 12),
                ),
                if (journal.reversalOfJournalId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      "Reversal of: ${journal.reversalOfJournalId}",
                      style: GoogleFonts.poppins(
                        color: Colors.red.shade300,
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "AED ${journal.amount.toStringAsFixed(2)}",
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isReversed
                      ? Colors.grey
                      : (journal.type == JournalType.expense
                            ? Colors.red
                            : Colors.green),
                ),
              ),
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isReversed
                      ? Colors.red.withValues(alpha: 0.1)
                      : Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  journal.status.name.toUpperCase(),
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isReversed ? Colors.red : Colors.green,
                  ),
                ),
              ),
            ],
          ),
          // Reverse button for posted journals
          if (isAccountant && isPosted) ...[
            const SizedBox(width: 16),
            OutlinedButton(
              onPressed: () => _confirmReversal(context, journal),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              child: const Text("Reverse"),
            ),
          ],
        ],
      ),
    );
  }

  void _confirmReversal(BuildContext context, JournalModel journal) {
    final TextEditingController reasonController = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          "Reverse Journal?",
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "This will create a mirror entry that cancels out:\n\n"
                "\"${journal.description}\"\n"
                "AED ${journal.amount.toStringAsFixed(2)}\n",
                style: GoogleFonts.poppins(fontSize: 14),
              ),
              const SizedBox(height: 16),
              Text(
                "Reason for Reversal:",
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: reasonController,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: InputDecoration(
                  hintText: "Enter a brief reason...",
                  hintStyle: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Reason is required";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Text(
                "This action cannot be undone.",
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.red.shade400,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                context.read<JournalBloc>().add(
                  ReverseJournal(
                    journal.id,
                    reason: reasonController.text.trim(),
                  ),
                );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Journal reversal initiated'),
                    backgroundColor: Colors.black87,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("Confirm Reversal"),
          ),
        ],
      ),
    );
  }

  void _rejectExpense(Expense exp) {
    final TextEditingController reasonController = TextEditingController();
    bool isSubmitting = false;
    showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: Text(
            'Reject Expense',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: reasonController,
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final reason = reasonController.text.trim();
                      if (reason.isEmpty) return;
                      setLocalState(() => isSubmitting = true);
                      try {
                        final client = Supabase.instance.client;
                        final currentUserId = client.auth.currentUser?.id;
                        await client
                            .from('expenses')
                            .update({'status': 'rejected'})
                            .eq('id', exp.id!);
                        await client
                            .from('action_items')
                            .update({
                              'resolved_by': currentUserId,
                              'resolved_at': DateTime.now().toIso8601String(),
                              'resolution_notes': reason,
                            })
                            .eq('reference_id', exp.id!);

                        if (!mounted) return;
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Expense rejected'),
                            backgroundColor: Colors.black87,
                          ),
                        );
                        _loadJournals();
                        context.read<eb.ExpenseBloc>().add(
                          const eb.LoadExpenses(),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        setLocalState(() => isSubmitting = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error rejecting expense: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
              child: isSubmitting
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
                  : const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }

  void _showApproveDialog(Expense exp) {
    showDialog(
      context: context,
      builder: (ctx) {
        return _ApproveJournalSheet(
          expense: exp,
          onPosted: () {
            if (!mounted) return;
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Journal posted successfully'),
                backgroundColor: Colors.green,
              ),
            );
            _loadJournals();
            _loadVendorPayables();
            context.read<eb.ExpenseBloc>().add(const eb.LoadExpenses());
            context.read<DrawerBloc>().add(const LoadDrawers());
          },
        );
      },
    );
  }

  void _showPostNewJournalSheet() {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (ctx, animation, secondaryAnimation) {
          return Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            body: SafeArea(
              child: _PostNewJournalSheet(
                onPosted: () {
                  if (!mounted) return;
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Journal posted successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  _loadJournals();
                  _loadVendorPayables();
                  context.read<eb.ExpenseBloc>().add(const eb.LoadExpenses());
                  context.read<DrawerBloc>().add(const LoadDrawers());
                },
              ),
            ),
          );
        },
        transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
          final tween = Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic));
          return SlideTransition(position: animation.drive(tween), child: child);
        },
      ),
    );
  }
}
