import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/models/drawer_model.dart';
import '../../logic/drawers/drawer_bloc.dart';
import 'package:intl/intl.dart';

class DrawerCard extends StatelessWidget {
  final DrawerModel drawer;
  final bool isSelected;
  final VoidCallback onTap;

  const DrawerCard({
    super.key,
    required this.drawer,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(
      symbol: 'AED ',
      decimalDigits: 2,
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 300,
        margin: const EdgeInsets.only(
          right: 16,
          bottom: 16,
        ), // Adjusted for list view
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(drawer.colorCode),
              Color(drawer.colorCode).withValues(alpha: 0.7),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Color(drawer.colorCode).withValues(alpha: 0.4),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
          border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  drawer.name,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(
                  _getIconForType(drawer.type),
                  color: Colors.white70,
                  size: 28,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Available Balance",
                            style: GoogleFonts.poppins(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            currencyFormat.format(drawer.balance),
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize:
                                  18, // Reduced font size to help with overflow
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        _ActionButton(
                          icon: Icons.add,
                          onPressed: () =>
                              _showTransactionDialog(context, isAdd: true),
                          tooltip: "Add Funds",
                        ),
                        const SizedBox(width: 8),
                        _ActionButton(
                          icon: Icons.remove,
                          onPressed: () =>
                              _showTransactionDialog(context, isAdd: false),
                          tooltip: "Deduct Funds",
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showTransactionDialog(BuildContext context, {required bool isAdd}) {
    final amountController = TextEditingController();
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isAdd ? "Add Funds" : "Deduct Funds"),
        content: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 300),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountController,
                  decoration: const InputDecoration(
                    labelText: "Amount (AED)",
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: "Reason",
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountController.text) ?? 0;
              if (amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Enter a valid amount greater than 0"),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              final bloc = context.read<DrawerBloc>();
              final signedAmount = isAdd ? amount : -amount;
              final description = reasonController.text.isEmpty
                  ? (isAdd ? "Manual Addition" : "Manual Deduction")
                  : reasonController.text;

              bloc.add(
                ProcessTransaction(
                  drawerId: drawer.id,
                  amount: signedAmount,
                  description: description,
                ),
              );
              Navigator.pop(dialogContext);

              final nextState = await bloc.stream
                  .firstWhere((s) => s is! DrawerLoading)
                  .timeout(const Duration(seconds: 20), onTimeout: () => bloc.state);

              if (!context.mounted) return;

              if (nextState is DrawerError) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(nextState.message),
                    backgroundColor: Colors.red,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(isAdd ? "Funds added successfully" : "Funds deducted successfully"),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: Text(isAdd ? "Add" : "Deduct"),
          ),
        ],
      ),
    );
  }

  IconData _getIconForType(DrawerType type) {
    switch (type) {
      case DrawerType.cash:
        return Icons.lock_outline;
      case DrawerType.bank:
        return Icons.account_balance;
      case DrawerType.wallet:
        return Icons.account_balance_wallet;
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  const _ActionButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: Colors.white, size: 20),
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.2),
        padding: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

