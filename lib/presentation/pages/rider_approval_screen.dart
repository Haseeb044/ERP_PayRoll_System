import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../logic/actions/action_bloc.dart';
import '../../logic/riders/riders_bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../utils/id_utils.dart';
import 'package:intl/intl.dart';

class RiderApprovalScreen extends StatefulWidget {
  final String requestId;
  final String actionItemId;

  const RiderApprovalScreen({
    super.key,
    required this.requestId,
    required this.actionItemId,
  });

  @override
  State<RiderApprovalScreen> createState() => _RiderApprovalScreenState();
}

class _RiderApprovalScreenState extends State<RiderApprovalScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emiratesIdController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passportController = TextEditingController();
  final _cityController = TextEditingController();
  final _riderCodeController = TextEditingController();
  final _passportExpiryController = TextEditingController();
  final _emiratesExpiryController = TextEditingController();
  final _holdReasonController = TextEditingController();
  final _holdUntilController = TextEditingController();

  String _wpsStatus = 'WPS';
  String _releaseHold = 'release';
  List<Map<String, dynamic>> _aliases = [];
  String? _error;
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emiratesIdController.dispose();
    _phoneController.dispose();
    _passportController.dispose();
    _cityController.dispose();
    _riderCodeController.dispose();
    _passportExpiryController.dispose();
    _emiratesExpiryController.dispose();
    _holdReasonController.dispose();
    _holdUntilController.dispose();
    super.dispose();
  }

  Future<void> _pickDateInto(TextEditingController controller) async {
    DateTime initialDate = DateTime.now();
    if (controller.text.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(controller.text.trim());
      if (parsed != null) initialDate = parsed;
    }

    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (selected != null) {
      controller.text = DateFormat('yyyy-MM-dd').format(selected);
      if (mounted) setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchRequestData();
  }

  Future<void> _fetchRequestData() async {
    try {
      final data = await Supabase.instance.client
          .from('rider_requests')
          .select()
          .eq('id', widget.requestId)
          .eq('status', 'pending') // Ensure only pending requests are fetched
          .single();

      setState(() {
        _nameController.text = data['name'] ?? '';
        _emiratesIdController.text = data['emirates_id_number'] ?? '';
        _phoneController.text = data['phone'] ?? '';
        _passportController.text = data['passport_number'] ?? '';
        _cityController.text = data['city'] ?? '';
        _riderCodeController.text = data['rider_code'] ?? '';
        _isLoading = false;
      });

      // Trigger refresh on relevant BLoCs
      context.read<ActionBloc>().add(ScanSystem());
      context.read<RidersBloc>().add(LoadRiders());
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading request: $e")),
        );
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

  Future<void> _approve() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    try {
      final aliasData = _aliases.map((a) => {
        'platform': a['platform'],
        'platform_rider_id': cleanPlatformId(a['platform_rider_id']).toUpperCase(),
        'c3_id': cleanPlatformId(a['c3_id']).toUpperCase(),
        'valid_from': (a['valid_from'] as DateTime).toIso8601String().split('T').first,
      }).toList();

      final conflictRows = <String>[];
      for (final a in aliasData) {
        final previewRes = await Supabase.instance.client.rpc(
          'rpc_preview_rider_alias_conflicts',
          params: {
            'p_rider_id': '00000000-0000-0000-0000-000000000000',
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

      await Supabase.instance.client.rpc('rpc_approve_rider_request', params: {
        'p_request_id': widget.requestId,
        'p_action_item_id': widget.actionItemId,
        'p_name': _nameController.text,
        'p_emirates_id_number': _emiratesIdController.text,
        'p_phone': _phoneController.text,
        'p_passport_number': _passportController.text,
        'p_city': _cityController.text,
        'p_rider_code': _riderCodeController.text,
        'p_wps_status': _wpsStatus,
        'p_release_hold': _releaseHold,
        'p_aliases': aliasData,
      });

      // Persist additional approval-only fields while keeping existing RPC flow intact.
      final riderLookup = await Supabase.instance.client
          .from('riders')
          .select('id')
          .eq('emirates_id_number', _emiratesIdController.text)
          .order('created_at', ascending: false)
          .limit(1);

      if (riderLookup.isNotEmpty) {
        final riderId = riderLookup.first['id'];
        await Supabase.instance.client.from('riders').update({
          'passport_expiry_date': _passportExpiryController.text.isEmpty ? null : _passportExpiryController.text,
          'emirates_id_expiry_date': _emiratesExpiryController.text.isEmpty ? null : _emiratesExpiryController.text,
          'hold_reason': _releaseHold == 'hold' && _holdReasonController.text.isNotEmpty
              ? _holdReasonController.text
              : null,
          'hold_until': _releaseHold == 'hold' && _holdUntilController.text.isNotEmpty
              ? _holdUntilController.text
              : null,
        }).eq('id', riderId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Rider approved successfully")),
        );
        
        // Refresh data
        context.read<ActionBloc>().add(ScanSystem());
        context.read<RidersBloc>().add(LoadRiders());
        
        // Navigate to riders list
        context.go('/riders');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Approval failed: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _reject() async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Reject Rider Request"),
        content: TextFormField(
          controller: reasonController,
          decoration: const InputDecoration(labelText: "Rejection Reason"),
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

    if (reason == null || reason.trim().isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      await Supabase.instance.client.rpc('rpc_reject_rider_request', params: {
        'p_request_id': widget.requestId,
        'p_action_item_id': widget.actionItemId,
        'p_rejection_reason': reason,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Rider request rejected")),
        );
        
        // Refresh actions
        context.read<ActionBloc>().add(ScanSystem());
        
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Rejection failed: $e")),
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

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Approve Rider Request")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline, size: 64, color: Colors.blue),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go('/riders'),
                child: const Text("Go to Riders List"),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Approve Rider Request")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle("Basic Information"),
              _buildTextField(_nameController, "Full Name"),
              _buildTextField(_emiratesIdController, "Emirates ID"),
              _buildTextField(_phoneController, "Phone"),
              _buildTextField(_passportController, "Passport Number"),
              _buildTextField(_cityController, "City"),
              _buildTextField(_riderCodeController, "Rider Code"),

              const SizedBox(height: 24),
              _buildSectionTitle("Document Expiry"),
              _buildTextField(
                _passportExpiryController,
                "Passport Expiry (YYYY-MM-DD)",
                readOnly: true,
                onTap: () => _pickDateInto(_passportExpiryController),
              ),
              _buildTextField(
                _emiratesExpiryController,
                "Emirates ID Expiry (YYYY-MM-DD)",
                readOnly: true,
                onTap: () => _pickDateInto(_emiratesExpiryController),
              ),
              
              const SizedBox(height: 24),
              _buildSectionTitle("Payroll Configuration"),
              _buildDropdown("WPS Status", _wpsStatus, ['WPS', 'Non-WPS'], (v) => setState(() => _wpsStatus = v!)),
              _buildDropdown("Release/Hold", _releaseHold, ['release', 'hold'], (v) => setState(() => _releaseHold = v!)),
              if (_releaseHold == 'hold') ...[
                _buildTextField(_holdReasonController, "Hold Reason"),
                _buildTextField(
                  _holdUntilController,
                  "Hold Until (YYYY-MM-DD)",
                  readOnly: true,
                  onTap: () => _pickDateInto(_holdUntilController),
                ),
              ],
              
              const SizedBox(height: 24),
              _buildSectionTitle("Platform Aliases"),
              ..._aliases.asMap().entries.map((entry) => _buildAliasRow(entry.key, entry.value)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _addAlias,
                icon: const Icon(Icons.add),
                label: const Text("Add Alias"),
              ),
              
              const SizedBox(height: 48),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _approve,
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
                          : const Text("Approve"),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting ? null : _reject,
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
                          : const Text("Reject"),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        onTap: onTap,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: readOnly ? const Icon(Icons.calendar_today) : null,
          filled: true,
          fillColor: Colors.grey[50],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)),
        ),
        validator: (v) => v!.isEmpty ? "Required" : null,
      ),
    );
  }

  Widget _buildDropdown(String label, String value, List<String> options, ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        value: value,
        items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.grey[50],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)),
        ),
      ),
    );
  }

  Widget _buildAliasRow(int index, Map<String, dynamic> alias) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    value: alias['platform'],
                    items: ['talabat', 'keeta'].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                    onChanged: (v) => setState(() => alias['platform'] = v!),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _aliases.removeAt(index)),
                  icon: const Icon(Icons.delete, color: Colors.red),
                ),
              ],
            ),
            TextFormField(
              initialValue: alias['platform_rider_id'],
              onChanged: (v) => alias['platform_rider_id'] = v,
              decoration: const InputDecoration(labelText: "Platform Rider ID"),
            ),
            if (alias['platform'] == 'keeta')
              TextFormField(
                initialValue: alias['c3_id'],
                onChanged: (v) => alias['c3_id'] = v,
                decoration: const InputDecoration(labelText: "C3 ID"),
              ),
            ListTile(
              title: Text("Valid From: ${DateFormat('yyyy-MM-dd').format(alias['valid_from'])}"),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: alias['valid_from'],
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (d != null) setState(() => alias['valid_from'] = d);
              },
            ),
          ],
        ),
      ),
    );
  }
}
