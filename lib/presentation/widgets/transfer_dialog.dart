import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/models/drawer_model.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../logic/drawers/drawer_bloc.dart';
import 'package:intl/intl.dart';

class TransferDialog extends StatefulWidget {
  final List<DrawerModel> drawers;

  const TransferDialog({super.key, required this.drawers});

  @override
  State<TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<TransferDialog> {
  String? sourceDrawerId;
  String? targetDrawerId;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    // Filter drawers for source (must have balance > 0)
    final sourceDrawers = widget.drawers.where((d) => d.balance > 0).toList();

    return AlertDialog(
      title: Text(
        "Transfer Funds",
        style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 300, maxWidth: 480),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // From
                DropdownButtonFormField<String>(
                value: sourceDrawerId,
                decoration: InputDecoration(
                  labelText: "From",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(
                    Icons.arrow_circle_up,
                    color: Colors.orange,
                  ),
                ),
                items: sourceDrawers.map((d) {
                  return DropdownMenuItem(
                    value: d.id,
                    child: Text(
                      "${d.name} (${NumberFormat.compactCurrency(symbol: 'AED ').format(d.balance)})",
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    sourceDrawerId = value;
                    // Reset target if same as source
                    if (targetDrawerId == value) targetDrawerId = null;
                  });
                },
                validator: (value) => value == null ? "Select source" : null,
              ),
              const SizedBox(height: 16),

              // To
              DropdownButtonFormField<String>(
                value: targetDrawerId,
                decoration: InputDecoration(
                  labelText: "To",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(
                    Icons.arrow_circle_down,
                    color: Colors.green,
                  ),
                ),
                items: widget.drawers.where((d) => d.id != sourceDrawerId).map((
                  d,
                ) {
                  return DropdownMenuItem(value: d.id, child: Text(d.name));
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    targetDrawerId = value;
                  });
                },
                validator: (value) => value == null ? "Select target" : null,
              ),
              const SizedBox(height: 16),

              // Amount
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: "Amount",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.attach_money),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return "Enter amount";
                  final amount = double.tryParse(value);
                  if (amount == null || amount <= 0) return "Invalid amount";

                  // Check balance
                  if (sourceDrawerId != null) {
                    final source = widget.drawers.firstWhere(
                      (d) => d.id == sourceDrawerId,
                    );
                    if (amount > source.balance) {
                      return "Insufficient funds (Max: ${source.balance})";
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Description
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: "Description",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.description),
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? "Enter description" : null,
              ),
            ],
          ),
        ),
      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Cancel", style: GoogleFonts.poppins(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final amount = double.parse(_amountController.text);
              context.read<DrawerBloc>().add(
                TransferFunds(
                  sourceDrawerId: sourceDrawerId!,
                  targetDrawerId: targetDrawerId!,
                  amount: amount,
                  description: _descriptionController.text,
                ),
              );
              Navigator.pop(context);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green[700],
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            "Confirm Transfer",
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
