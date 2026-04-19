import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_theme.dart';
import '../../data/models/rider_model.dart';
import '../../utils/id_utils.dart';

class RiderCompletionForm extends StatefulWidget {
  final String riderId;
  final String actionItemId;

  const RiderCompletionForm({
    super.key,
    required this.riderId,
    required this.actionItemId,
  });

  @override
  State<RiderCompletionForm> createState() => _RiderCompletionFormState();
}

class _RiderCompletionFormState extends State<RiderCompletionForm> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isSubmitting = false;
  RiderModel? _rider;

  final _passportExpiryController = TextEditingController();
  final _emiratesExpiryController = TextEditingController();
  final _holdReasonController = TextEditingController();
  final _holdUntilController = TextEditingController();

  // Editable fields
  String _wpsStatus = 'WPS';
  String _releaseHold = 'release';

  // Platform Aliases
  final List<Map<String, dynamic>> _aliases = [];

  @override
  void initState() {
    super.initState();
    _loadRiderData();
  }

  @override
  void dispose() {
    _passportExpiryController.dispose();
    _emiratesExpiryController.dispose();
    _holdReasonController.dispose();
    _holdUntilController.dispose();
    super.dispose();
  }

  Future<void> _loadRiderData() async {
    try {
      final response = await Supabase.instance.client
          .from('riders')
          .select()
          .eq('id', widget.riderId)
          .single();

      if (mounted) {
        setState(() {
          _rider = RiderModel.fromJson(response);
          _wpsStatus = _rider?.wpsStatus ?? 'WPS';
          _releaseHold = _rider?.releaseHold ?? 'release';
          _passportExpiryController.text = _rider?.passportExpiryDate ?? '';
          _emiratesExpiryController.text = _rider?.emiratesIdExpiryDate ?? '';
          _holdReasonController.text = _rider?.holdReason ?? '';
          _holdUntilController.text = _rider?.holdUntil ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading rider: $e")),
        );
        Navigator.pop(context);
      }
    }
  }

  void _addAlias() {
    setState(() {
      _aliases.add({
        'platform': 'talabat',
        'platform_rider_id': '',
        'c3_id': '',
        'valid_from': DateTime.now(),
      });
    });
  }

  void _removeAlias(int index) {
    setState(() {
      _aliases.removeAt(index);
    });
  }

  Future<void> _approveRider() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final supabase = Supabase.instance.client;

      // 1. Prepare Alias Data
      final aliasData = _aliases.map((a) => {
        'platform': a['platform'],
        'platform_rider_id': cleanPlatformId(a['platform_rider_id']).toUpperCase(),
        'c3_id': cleanPlatformId(a['c3_id']).toUpperCase(),
        'valid_from': (a['valid_from'] as DateTime).toIso8601String().split('T').first,
      }).toList();

      final conflictRows = <String>[];
      for (final a in aliasData) {
        final previewRes = await supabase.rpc(
          'rpc_preview_rider_alias_conflicts',
          params: {
            'p_rider_id': widget.riderId,
            'p_platform': a['platform'],
            'p_platform_rider_id': a['platform_rider_id'],
            'p_valid_from': a['valid_from'],
          },
        );

        Map<String, dynamic>? preview;
        if (previewRes is Map<String, dynamic>) preview = previewRes;
        if (previewRes is List && previewRes.isNotEmpty && previewRes.first is Map<String, dynamic>) {
          preview = previewRes.first as Map<String, dynamic>;
        }

        if ((preview?['has_conflict'] == true) || ((preview?['other_rider_conflicts'] ?? 0) > 0)) {
          conflictRows.add('${a['platform']} / ${a['platform_rider_id']}');
        }
      }

      if (conflictRows.isNotEmpty) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Alias Conflict Warning'),
            content: Text(
              'Possible duplicate alias IDs were found:\n\n${conflictRows.join('\n')}\n\nDo you want to continue anyway?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
            ],
          ),
        );

        if (proceed != true) {
          if (mounted) setState(() => _isSubmitting = false);
          return;
        }
      }

      // 2. Call Atomic RPC
      await supabase.rpc('rpc_approve_rider', params: {
        'p_rider_id': widget.riderId,
        'p_action_item_id': widget.actionItemId,
        'p_wps_status': _wpsStatus,
        'p_release_hold': _releaseHold,
        'p_aliases': aliasData,
      });

      await supabase.from('riders').update({
        'passport_expiry_date': _passportExpiryController.text.isEmpty ? null : _passportExpiryController.text,
        'emirates_id_expiry_date': _emiratesExpiryController.text.isEmpty ? null : _emiratesExpiryController.text,
        'hold_reason': _releaseHold == 'hold' && _holdReasonController.text.isNotEmpty
            ? _holdReasonController.text
            : null,
        'hold_until': _releaseHold == 'hold' && _holdUntilController.text.isNotEmpty
            ? _holdUntilController.text
            : null,
      }).eq('id', widget.riderId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Rider approved and activated")),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error approving rider: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _rejectRider() async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Reject Rider"),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(hintText: "Reason for rejection"),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, reasonController.text),
            child: const Text("Reject"),
          ),
        ],
      ),
    );

    if (reason == null || reason.isEmpty) return;

    setState(() => _isSubmitting = true);

    try {
      final supabase = Supabase.instance.client;

      // 1. Retire Rider
      await supabase.from('riders').update({
        'status': 'retired',
      }).eq('id', widget.riderId);

      // 2. Resolve Action Item
      await supabase.from('action_items').update({
        'resolved_at': DateTime.now().toIso8601String(),
        'resolution_note': 'Rejected: $reason',
      }).eq('id', widget.actionItemId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Rider rejected")),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error rejecting rider: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("Complete Rider Profile", style: GoogleFonts.poppins()),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle("Rider Basic Information"),
              const SizedBox(height: 16),
              _buildReadOnlyField("Name", _rider?.name ?? ""),
              _buildReadOnlyField("Rider Code", _rider?.riderCode ?? ""),
              _buildReadOnlyField("Emirates ID", _rider?.emiratesIdNumber ?? ""),
              _buildReadOnlyField("Passport", _rider?.passportNumber ?? "-"),
              _buildReadOnlyField("Phone", _rider?.phone ?? "-"),
              _buildReadOnlyField("City", _rider?.city ?? "-"),

              const SizedBox(height: 24),
              _buildSectionTitle("Document Expiry"),
              const SizedBox(height: 16),
              _buildInputField(
                controller: _passportExpiryController,
                label: "Passport Expiry (YYYY-MM-DD)",
                hint: "e.g. 2028-03-15",
              ),
              const SizedBox(height: 12),
              _buildInputField(
                controller: _emiratesExpiryController,
                label: "Emirates ID Expiry (YYYY-MM-DD)",
                hint: "e.g. 2027-08-01",
              ),

              const SizedBox(height: 32),
              _buildSectionTitle("Employment Details"),
              const SizedBox(height: 16),
              _buildDropdownField(
                label: "WPS Status",
                value: _wpsStatus,
                items: ["WPS", "Non-WPS"],
                onChanged: (v) => setState(() => _wpsStatus = v!),
              ),
              const SizedBox(height: 16),
              _buildDropdownField(
                label: "Release / Hold",
                value: _releaseHold,
                items: ["release", "hold"],
                onChanged: (v) => setState(() => _releaseHold = v!),
              ),
              if (_releaseHold == 'hold') ...[
                const SizedBox(height: 16),
                _buildInputField(
                  controller: _holdReasonController,
                  label: "Hold Reason",
                  hint: "Why this rider is on hold",
                ),
                const SizedBox(height: 12),
                _buildInputField(
                  controller: _holdUntilController,
                  label: "Hold Until (YYYY-MM-DD)",
                  hint: "e.g. 2026-12-31",
                ),
              ],

              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSectionTitle("Platform Aliases"),
                  TextButton.icon(
                    onPressed: _addAlias,
                    icon: const Icon(Icons.add),
                    label: const Text("Add Alias"),
                  ),
                ],
              ),
              if (_aliases.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text("No aliases added yet.", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                ),
              ..._aliases.asMap().entries.map((entry) => _buildAliasCard(entry.key, entry.value)),

              const SizedBox(height: 48),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting ? null : _rejectRider,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isSubmitting
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.red,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text("Please wait..."),
                              ],
                            )
                          : const Text("Reject Rider"),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _approveRider,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isSubmitting
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
                                Text("Please wait..."),
                              ],
                            )
                          : const Text("Approve & Activate"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey[50],
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)),
          ),
        ),
      ],
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
      ),
    );
  }

  Widget _buildAliasCard(int index, Map<String, dynamic> alias) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: alias['platform'],
                    items: const [
                      DropdownMenuItem(value: 'talabat', child: Text("Talabat")),
                      DropdownMenuItem(value: 'keeta', child: Text("Keeta")),
                    ],
                    onChanged: (v) => setState(() => alias['platform'] = v),
                    decoration: const InputDecoration(labelText: "Platform"),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(onPressed: () => _removeAlias(index), icon: const Icon(Icons.delete, color: Colors.red)),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: alias['platform_rider_id'],
              onChanged: (v) => alias['platform_rider_id'] = v,
              decoration: const InputDecoration(labelText: "Platform Rider ID", hintText: "e.g. 12345"),
              validator: (v) => v!.isEmpty ? "Required" : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: alias['c3_id'],
              onChanged: (v) => alias['c3_id'] = v,
              decoration: const InputDecoration(labelText: "C3 ID (Optional)", hintText: "e.g. 98765"),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: alias['valid_from'],
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) setState(() => alias['valid_from'] = d);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: "Valid From"),
                child: Text("${(alias['valid_from'] as DateTime).toLocal()}".split(' ')[0]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}