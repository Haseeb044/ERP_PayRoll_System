import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/payroll_model.dart';
import '../../data/models/payslip_item_model.dart';
import '../../logic/payroll/payroll_bloc.dart';
import '../../logic/drawers/drawer_bloc.dart';
import '../../services/api_service.dart';
import '../../utils/user_friendly_error.dart';

class PayslipPreviewScreen extends StatefulWidget {
  final PayslipDraftModel payslip;
  const PayslipPreviewScreen({super.key, required this.payslip});

  @override
  State<PayslipPreviewScreen> createState() => _PayslipPreviewScreenState();
}

class _PayslipPreviewScreenState extends State<PayslipPreviewScreen> {
  late List<PayslipItemModel> _items;
  late double _netSalary;
  final TextEditingController _labelController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  PayslipItemType _selectedType = PayslipItemType.fine;
  bool _isApplyingCarryForward = false;
  bool _isSavingAdjustments = false;

  @override
  void initState() {
    super.initState();
    _items = widget.payslip.items.map(_normalizeItemAmount).toList();
    _netSalary = widget.payslip.netSalary;
    _calculateNet();
  }

  PayslipItemModel _normalizeItemAmount(PayslipItemModel item) {
    final normalized = item.type == PayslipItemType.earning
        ? item.amount.abs()
        : -item.amount.abs();
    return item.copyWith(amount: normalized);
  }

  double _calculateTotalDeductions() {
    return _items
        .where((i) => i.type != PayslipItemType.earning)
        .fold(0.0, (sum, i) => sum + i.amount.abs());
  }

  void _calculateNet() {
    double earnings = _items
        .where((i) => i.type == PayslipItemType.earning)
        .fold(0.0, (sum, i) => sum + i.amount.abs());
    double deductions = _calculateTotalDeductions();

    _netSalary = earnings - deductions;
  }

  void _addItem() {
    final label = _labelController.text.trim();
    final amount = double.tryParse(_amountController.text) ?? 0.0;
    if (label.isEmpty || amount <= 0) return;

    setState(() {
      _items.add(
        PayslipItemModel(label: label, amount: -amount, type: _selectedType),
      );
      _labelController.clear();
      _amountController.clear();
      _calculateNet();
    });
  }

  void _updateItemAmount(int index, double amount) {
    final current = _items[index];
    final normalized = current.type == PayslipItemType.earning
        ? amount.abs()
        : -amount.abs();
    setState(() {
      _items[index] = current.copyWith(amount: normalized);
      _calculateNet();
    });
  }

  void _showEditAmountDialog(int index) {
    final item = _items[index];
    final controller = TextEditingController(
      text: item.amount.abs().toStringAsFixed(2),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Amount'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: item.label, suffixText: 'AED'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final parsed = double.tryParse(controller.text.trim());
              if (parsed == null || parsed < 0) {
                return;
              }
              _updateItemAmount(index, parsed);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveChanges() async {
    if (_isSavingAdjustments) return;
    setState(() => _isSavingAdjustments = true);

    final bloc = context.read<PayrollBloc>();
    bloc.add(
      UpdatePayslipAdjustments(
        payslipId: widget.payslip.id,
        items: _items,
        netSalary: _netSalary,
      ),
    );

    final nextState = await bloc.stream
        .firstWhere((s) => s is! PayrollLoading)
        .timeout(const Duration(seconds: 20), onTimeout: () => bloc.state);

    if (!mounted) return;
    setState(() => _isSavingAdjustments = false);

    if (nextState is PayrollError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save adjustments: ${nextState.message}'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Adjustments saved successfully')),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchCarryForwardOptions() async {
    final riderId = widget.payslip.riderId;
    if (riderId == null || riderId.isEmpty) return const [];

    final result = await ApiService.instance.getCarryForwardOptions(riderId);
    return (result['options'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> _applyCarryForwardSelections(
    List<Map<String, dynamic>> selections,
  ) async {
    if (selections.isEmpty || _isApplyingCarryForward) return;

    setState(() => _isApplyingCarryForward = true);
    try {
      final result = await ApiService.instance.applyCarryForwardSelections(
        widget.payslip.id,
        selections,
      );

      final payslip = result['payslip'];
      if (payslip is Map) {
        final updatedItems = (payslip['items'] as List<dynamic>? ?? const [])
            .map(
              (e) => PayslipItemModel.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .map(_normalizeItemAmount)
            .toList();
        final updatedNet = (payslip['net_salary'] as num?)?.toDouble();
        if (mounted) {
          setState(() {
            _items = updatedItems;
            if (updatedNet != null) {
              _netSalary = updatedNet;
            } else {
              _calculateNet();
            }
          });
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Carry-forward decisions applied')),
      );

      final batchId = widget.payslip.batchId;
      if (batchId != null && batchId.isNotEmpty) {
        context.read<PayrollBloc>().add(LoadBatchDetails(batchId));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(toUserFriendlyError(e))),
      );
    } finally {
      if (mounted) {
        setState(() => _isApplyingCarryForward = false);
      }
    }
  }

  Future<void> _showCarryForwardDialog() async {
    try {
      final options = await _fetchCarryForwardOptions();
      if (!mounted) return;

      if (options.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No carry-forward options found')),
        );
        return;
      }

      final selectedIds = <String>{
        ...options
            .map((opt) => (opt['entry_id'] ?? '').toString())
            .where((id) => id.isNotEmpty),
      };
      final amountControllers = <String, TextEditingController>{
        for (final opt in options)
          (opt['entry_id'] ?? '').toString(): TextEditingController(
            text: ((opt['reduced_amount'] as num? ?? 0).toDouble())
                .toStringAsFixed(2),
          ),
      };
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setLocalState) {
              return AlertDialog(
                title: const Text('Carry Forward Deductions'),
                content: SizedBox(
                  width: 560,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: options.map((opt) {
                        final entryId = (opt['entry_id'] ?? '').toString();
                        final reduced = (opt['reduced_amount'] as num? ?? 0)
                            .toDouble();
                        final label = (opt['label'] ?? 'Adjustment').toString();
                        final reason = (opt['reason'] ?? '').toString();
                        final checked = selectedIds.contains(entryId);
                        final amountController = amountControllers[entryId]!;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(
                                value: checked,
                                onChanged: (v) {
                                  setLocalState(() {
                                    if (v == true) {
                                      selectedIds.add(entryId);
                                    } else {
                                      selectedIds.remove(entryId);
                                    }
                                  });
                                },
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      reason.isEmpty
                                          ? 'Max reduced: ${reduced.toStringAsFixed(2)} AED'
                                          : '$reason\nMax reduced: ${reduced.toStringAsFixed(2)} AED',
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: amountController,
                                      enabled: checked,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: const InputDecoration(
                                        labelText: 'Apply amount',
                                        suffixText: 'AED',
                                        isDense: true,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: _isApplyingCarryForward
                        ? null
                        : () async {
                            final selections = options
                                .map(
                                  (opt) => {
                                    'entry_id': (opt['entry_id'] ?? '')
                                        .toString(),
                                    'decision': 'none',
                                    'apply_amount': 0.0,
                                  },
                                )
                                .toList();
                            Navigator.pop(dialogContext);
                            await _applyCarryForwardSelections(selections);
                          },
                    child: const Text('Apply None'),
                  ),
                  TextButton(
                    onPressed: _isApplyingCarryForward
                        ? null
                        : () async {
                            final selections = options
                                .map(
                                  (opt) => {
                                    'entry_id': (opt['entry_id'] ?? '')
                                        .toString(),
                                    'decision': 'all',
                                    'apply_amount':
                                        (opt['reduced_amount'] as num? ?? 0)
                                            .toDouble(),
                                  },
                                )
                                .toList();
                            Navigator.pop(dialogContext);
                            await _applyCarryForwardSelections(selections);
                          },
                    child: const Text('Apply All'),
                  ),
                  ElevatedButton(
                    onPressed: _isApplyingCarryForward
                        ? null
                        : () async {
                            final selections = <Map<String, dynamic>>[];
                            for (final opt in options) {
                              final entryId = (opt['entry_id'] ?? '')
                                  .toString();
                              final isSelected = selectedIds.contains(entryId);
                              final reduced =
                                  (opt['reduced_amount'] as num? ?? 0)
                                      .toDouble();

                              if (!isSelected) {
                                selections.add({
                                  'entry_id': entryId,
                                  'decision': 'none',
                                  'apply_amount': 0.0,
                                });
                                continue;
                              }

                              final raw =
                                  amountControllers[entryId]?.text.trim() ?? '';
                              final parsed = double.tryParse(raw);
                              if (parsed == null || parsed <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Invalid apply amount for $entryId',
                                    ),
                                  ),
                                );
                                return;
                              }
                              if (parsed > reduced) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Apply amount cannot exceed reduced amount for $entryId',
                                    ),
                                  ),
                                );
                                return;
                              }

                              selections.add({
                                'entry_id': entryId,
                                'decision': 'some',
                                'apply_amount': parsed,
                              });
                            }

                            Navigator.pop(dialogContext);
                            await _applyCarryForwardSelections(selections);
                          },
                    child: const Text('Apply Selected'),
                  ),
                ],
              );
            },
          );
        },
      );
      for (final c in amountControllers.values) {
        c.dispose();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(toUserFriendlyError(e))),
      );
    }
  }

  void _showGenerateDialog() {
    showDialog(
      context: context,
      builder: (context) => BlocBuilder<DrawerBloc, DrawerState>(
        builder: (context, state) {
          if (state is! DrawerLoaded) {
            return const Center(child: CircularProgressIndicator());
          }
          return AlertDialog(
            title: const Text('Select Payment Drawer'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: state.drawers.length,
                itemBuilder: (context, index) {
                  final d = state.drawers[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Color(d.colorCode),
                      child: const Icon(
                        Icons.account_balance_wallet,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    title: Text(d.name),
                    subtitle: Text(
                      'Balance: ${d.balance.toStringAsFixed(2)} ${d.currency}',
                    ),
                    onTap: d.balance < _netSalary
                        ? null
                        : () {
                            context.read<PayrollBloc>().add(
                              GenerateIndividualPayslip(
                                payslipId: widget.payslip.id,
                                drawerId: d.id,
                              ),
                            );
                            Navigator.pop(context); // Close dialog
                            context.pop(); // Go back to draft list
                          },
                    enabled: d.balance >= _netSalary,
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Payslip Preview',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              widget.payslip.riderName,
              style: TextStyle(
                fontSize: 12,
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
              ),
            ),
          ],
        ),
        actions: [
          if (widget.payslip.status != PayslipDraftStatus.finalized)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: ElevatedButton.icon(
                onPressed: _netSalary < 0 ? null : _showGenerateDialog,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Generate'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Glassmorphic Payslip Card
            _buildGlassCard(
              context,
              child: Column(
                children: [
                  _buildHeaderRow(widget.payslip),
                  const Divider(height: 40),
                  _buildSectionTitle('Earnings'),
                  ..._items
                      .where((i) => i.type == PayslipItemType.earning)
                      .map(
                        (item) =>
                            _buildRemovableItemRow(item, _items.indexOf(item)),
                      ),
                  if (_items
                      .where((i) => i.type == PayslipItemType.earning)
                      .isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'No earnings data.',
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
                      ),
                    ),

                  const SizedBox(height: 20),
                  _buildSectionTitle('Deductions'),
                  const SizedBox(height: 8),
                  _buildSectionTitle('Fine'),
                  ..._fineItems().map(
                    (item) =>
                        _buildRemovableItemRow(item, _items.indexOf(item)),
                  ),
                  if (_fineItems().isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'No fines.',
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  _buildSectionTitle('Expense'),
                  ..._expenseItems().map(
                    (item) =>
                        _buildRemovableItemRow(item, _items.indexOf(item)),
                  ),
                  if (_expenseItems().isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'No expenses.',
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  _buildSectionTitle('Loan'),
                  ..._loanItems().map(
                    (item) =>
                        _buildRemovableItemRow(item, _items.indexOf(item)),
                  ),
                  if (_loanItems().isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'No loans.',
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  const Divider(height: 40),
                  _buildSummaryRow('Total Fines', _fineTotal()),
                  _buildSummaryRow('Total Expenses', _expenseTotal()),
                  _buildSummaryRow('Total Loans', _loanTotal()),
                  _buildSummaryRow(
                    'Total Deductions',
                    _calculateTotalDeductions(),
                  ),
                  _buildSummaryRow('Net Salary', _netSalary, isHighlight: true),
                ],
              ),
            ),
            const SizedBox(height: 30),

            // Adjustment Tools
            if (widget.payslip.status != PayslipDraftStatus.finalized)
              _buildAdjustmentSection(theme),
          ],
        ),
      ),
      bottomNavigationBar: widget.payslip.status == PayslipDraftStatus.finalized
          ? null
          : Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                border: Border(
                  top: BorderSide(color: theme.dividerColor.withOpacity(0.1)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSavingAdjustments ? null : _saveChanges,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSavingAdjustments
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text('Please wait...'),
                              ],
                            )
                          : const Text('Save Adjustments'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isApplyingCarryForward
                          ? null
                          : _showCarryForwardDialog,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isApplyingCarryForward
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Carry Forward'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildGlassCard(BuildContext context, {required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildHeaderRow(PayslipDraftModel payslip) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PAYSLIP',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Colors.blue.shade600,
                letterSpacing: 1.2,
              ),
            ),
            Text(
              'ID: ${payslip.externalId}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.withOpacity(0.6),
              ),
            ),
            if ((payslip.platform ?? '').isNotEmpty)
              Text(
                'Company: ${payslip.platform!.toUpperCase()}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.withOpacity(0.8),
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: payslip.status == PayslipDraftStatus.finalized
                ? Colors.green.withOpacity(0.1)
                : Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            payslip.status.name.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: payslip.status == PayslipDraftStatus.finalized
                  ? Colors.green
                  : Colors.orange,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  List<PayslipItemModel> _fineItems() {
    return _items.where((i) => i.type == PayslipItemType.fine).toList();
  }

  List<PayslipItemModel> _expenseItems() {
    return _items
        .where(
          (i) =>
              i.type == PayslipItemType.deduction ||
              i.type == PayslipItemType.platformDeduction,
        )
        .where((i) => !_isLoanItem(i))
        .toList();
  }

  bool _isLoanItem(PayslipItemModel item) {
    if (item.type == PayslipItemType.loan) return true;
    final label = item.label.toLowerCase();
    return label.contains('loan') || label.contains('advance');
  }

  List<PayslipItemModel> _loanItems() {
    return _items
        .where(
          (i) =>
              (i.type == PayslipItemType.deduction ||
                i.type == PayslipItemType.platformDeduction ||
                i.type == PayslipItemType.loan) &&
              _isLoanItem(i),
        )
        .toList();
  }

  double _fineTotal() {
    return _fineItems().fold(0.0, (sum, i) => sum + i.amount.abs());
  }

  double _expenseTotal() {
    return _expenseItems().fold(0.0, (sum, i) => sum + i.amount.abs());
  }

  double _loanTotal() {
    return _loanItems().fold(0.0, (sum, i) => sum + i.amount.abs());
  }

  Widget _buildRemovableItemRow(PayslipItemModel item, int index) {
    final canEdit =
        widget.payslip.status != PayslipDraftStatus.finalized &&
        item.type != PayslipItemType.earning;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Text(item.label, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                if (canEdit)
                  IconButton(
                    icon: const Icon(
                      Icons.edit_outlined,
                      size: 16,
                      color: Colors.blueGrey,
                    ),
                    onPressed: () => _showEditAmountDialog(index),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),
          Text(
            '${item.amount.toStringAsFixed(2)} AED',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: item.amount >= 0 ? Colors.green : Colors.redAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    double amount, {
    bool isHighlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isHighlight ? 18 : 14,
              fontWeight: isHighlight ? FontWeight.bold : FontWeight.w600,
            ),
          ),
          Text(
            '${amount.toStringAsFixed(2)} AED',
            style: TextStyle(
              fontSize: isHighlight ? 20 : 16,
              fontWeight: FontWeight.bold,
              color: isHighlight ? Colors.blue.shade600 : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdjustmentSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Adjustments',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _labelController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        hintText: 'e.g. Broken Mirror Fine',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        suffixText: 'AED',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<PayslipItemType>(
                      value: _selectedType,
                      items: const [
                        DropdownMenuItem(
                          value: PayslipItemType.fine,
                          child: Text('Fine'),
                        ),
                        DropdownMenuItem(
                          value: PayslipItemType.deduction,
                          child: Text('Expense'),
                        ),
                        DropdownMenuItem(
                          value: PayslipItemType.loan,
                          child: Text('Loan'),
                        ),
                      ],
                      onChanged: (val) => setState(() => _selectedType = val!),
                      decoration: const InputDecoration(labelText: 'Category'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _addItem,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Add Item'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
