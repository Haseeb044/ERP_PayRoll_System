import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../logic/riders/riders_bloc.dart';
import '../../core/app_theme.dart';
import '../../data/repositories/supabase_rider_repository.dart';

class ManualAssignmentDialog extends StatefulWidget {
  final String fineId;
  final Function(String riderId) onConfirm;

  const ManualAssignmentDialog({
    super.key,
    required this.fineId,
    required this.onConfirm,
  });

  @override
  State<ManualAssignmentDialog> createState() => _ManualAssignmentDialogState();
}

class _ManualAssignmentDialogState extends State<ManualAssignmentDialog> {
  String? selectedRiderId;
  String _searchQuery = '';
  String _rawSearchQuery = '';
  bool _isCreating = false;

  Future<void> _handleCreateGhostRider() async {
    final name = _rawSearchQuery.trim();
    if (name.isEmpty) return;

    setState(() => _isCreating = true);
    try {
      final repo = SupabaseRiderRepository();
      final newRiderId = await repo.createGhostRider(name);

      widget.onConfirm(newRiderId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error creating ghost rider: $e"),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    context.read<RidersBloc>().add(LoadRiders());
  }

  @override
  Widget build(BuildContext context) {
    final displayId = widget.fineId.isNotEmpty 
        ? (widget.fineId.length > 8 ? widget.fineId.substring(0, 8) : widget.fineId)
        : "N/A";

    return Material(
      type: MaterialType.transparency,
      child: AlertDialog(
        title: Text(
          "Assign Liability",
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        actionsOverflowButtonSpacing: 8,
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Select rider for Fine #$displayId",
                style: GoogleFonts.poppins(
                  color: Colors.grey[600],
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  hintText: "Search rider name...",
                  prefixIcon: const Icon(Icons.search, size: 20),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _rawSearchQuery = value;
                    _searchQuery = value.toLowerCase();
                  });
                },
              ),
              const SizedBox(height: 12),
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: BlocBuilder<RidersBloc, RidersState>(
                    builder: (context, state) {
                      if (state is RidersLoading) {
                        return const SizedBox(
                          height: 150,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (state is RidersLoaded) {
                        final filteredRiders = state.riders.where((r) {
                          return r.name.toLowerCase().contains(_searchQuery);
                        }).toList();

                        if (filteredRiders.isEmpty) {
                          return const SizedBox(
                            height: 100,
                            child: Center(child: Text("No riders found")),
                          );
                        }

                        return ListView.separated(
                          shrinkWrap: true,
                          itemCount: filteredRiders.length,
                          separatorBuilder: (ctx, idx) => const Divider(height: 1),
                          itemBuilder: (ctx, index) {
                            final rider = filteredRiders[index];
                            final isSelected = selectedRiderId == rider.id;
                            return ListTile(
                              dense: true,
                              selected: isSelected,
                              selectedTileColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                              title: Text(
                                rider.name,
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  color: isSelected ? AppTheme.primaryColor : Colors.black87,
                                ),
                              ),
                              onTap: () {
                                setState(() {
                                  selectedRiderId = rider.id;
                                });
                              },
                              trailing: isSelected 
                                ? const Icon(Icons.check_circle, color: AppTheme.primaryColor, size: 18)
                                : null,
                            );
                          },
                        );
                      }
                      return const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text("Failed to load riders."),
                      );
                    },
                  ),
                ),
              ),
              if (_rawSearchQuery.length >= 2) ...[
                const SizedBox(height: 12),
                Center(
                  child: TextButton.icon(
                    onPressed: _isCreating ? null : _handleCreateGhostRider,
                    icon: _isCreating 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange))
                        : const Icon(Icons.person_add_alt_1),
                    label: Text("Quick Create '$_rawSearchQuery' Ghost Profile"),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.orange[800],
                      textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                  )
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: selectedRiderId == null
                ? null
                : () {
                    widget.onConfirm(selectedRiderId!);
                    Navigator.pop(context);
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              "Confirm Liability",
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

