import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../data/models/rider_model.dart';
import '../../logic/riders/riders_bloc.dart';
import '../../data/repositories/rider_repository.dart';
import '../../services/api_service.dart';
import '../../utils/rider_code_utils.dart';
import '../../utils/user_friendly_error.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';

class RiderFormScreen extends StatefulWidget {
  final RiderModel? rider;
  final bool isAccountantCreate;

  const RiderFormScreen({super.key, this.rider, this.isAccountantCreate = false});

  @override
  State<RiderFormScreen> createState() => _RiderFormScreenState();
}

class _RiderFormScreenState extends State<RiderFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _riderCodeController;
  late TextEditingController _nameController;
  late TextEditingController _emiratesIdController;
  late TextEditingController _phoneController;
  late TextEditingController _passportNumberController;
  late TextEditingController _cityController;
  late TextEditingController _passportExpiryController;
  late TextEditingController _emiratesExpiryController;
  late TextEditingController _visaExpiryController;
  late TextEditingController _holdReasonController;
  late TextEditingController _holdUntilController;
  late TextEditingController _statusReasonController;
  late TextEditingController _expectedReturnController;

  String _wpsStatus = 'WPS';
  String _releaseHold = 'release';
  String _selectedStatus = 'active';
  List<Map<String, dynamic>> _aliases = [];
  bool _isSubmitting = false;

  String? _riderCodeError;

  @override
  void initState() {
    super.initState();
    _riderCodeController = TextEditingController(
      text: widget.rider?.riderCode ?? RiderCodeUtils.generateRandomCode(),
    );
    _nameController = TextEditingController(text: widget.rider?.name ?? '');
    _emiratesIdController = TextEditingController(
      text: widget.rider?.emiratesIdNumber ?? '',
    );
    _phoneController = TextEditingController(text: widget.rider?.phone ?? '');
    _passportNumberController = TextEditingController(
      text: widget.rider?.passportNumber ?? '',
    );
    _cityController = TextEditingController(text: widget.rider?.city ?? '');
    _passportExpiryController = TextEditingController(
      text: widget.rider?.passportExpiryDate ?? '',
    );
    _emiratesExpiryController = TextEditingController(
      text: widget.rider?.emiratesIdExpiryDate ?? '',
    );
    _visaExpiryController = TextEditingController(
      text: widget.rider?.visaExpiryDate ?? '',
    );
    _holdReasonController = TextEditingController(
      text: widget.rider?.holdReason ?? '',
    );
    _holdUntilController = TextEditingController(
      text: widget.rider?.holdUntil ?? '',
    );
    _statusReasonController = TextEditingController();
    _expectedReturnController = TextEditingController();
    _selectedStatus = _statusToString(widget.rider?.status ?? RiderStatus.active);
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

  @override
  void dispose() {
    _riderCodeController.dispose();
    _nameController.dispose();
    _emiratesIdController.dispose();
    _phoneController.dispose();
    _passportNumberController.dispose();
    _cityController.dispose();
    _passportExpiryController.dispose();
    _emiratesExpiryController.dispose();
    _visaExpiryController.dispose();
    _holdReasonController.dispose();
    _holdUntilController.dispose();
    _statusReasonController.dispose();
    _expectedReturnController.dispose();
    super.dispose();
  }

  String _statusToString(RiderStatus status) {
    return status.toString().split('.').last;
  }

  RiderStatus _statusFromString(String value) {
    switch (value) {
      case 'vacation':
        return RiderStatus.vacation;
      case 'retired':
        return RiderStatus.retired;
      default:
        return RiderStatus.active;
    }
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

  void _saveRider() async {
    if (_isSubmitting) return;

    // Clear any previous error
    setState(() => _riderCodeError = null);

    if (_formKey.currentState!.validate()) {
      // Validate rider code format
      final codeError = RiderCodeUtils.validateRiderCode(_riderCodeController.text);
      if (codeError != null) {
        setState(() => _riderCodeError = codeError);
        _formKey.currentState!.validate(); // Trigger visual feedback
        return;
      }

      // For new riders, check uniqueness of rider_code against database
      if (widget.rider == null) {
        try {
          final repo = context.read<RiderRepository>();
          final existingRiders = await repo.fetchRiders();
          final codeExists = existingRiders
              .any((r) => r.riderCode == _riderCodeController.text);

          if (codeExists) {
            setState(() => _riderCodeError =
                "This Rider ID is already taken, please use a different one");
            _formKey.currentState!.validate();
            return;
          }
        } catch (e) {
          print('Error checking rider code uniqueness: $e');
          // Continue anyway - the database will enforce uniqueness constraint
        }
      }

      // PRO form only sends rider_code, name, emirates_id_number, phone,
      // passport_number, city. Status, wps_status, release_hold are set by
      // the accountant during approval, not by the PRO.
      final rider = RiderModel(
        id: widget.rider?.id ?? '',
        riderCode: _riderCodeController.text,
        name: _nameController.text,
        emiratesIdNumber: _emiratesIdController.text,
        phone: _phoneController.text.isNotEmpty
            ? _phoneController.text
            : null,
        status: widget.rider?.status ?? _statusFromString(_selectedStatus),
        passportNumber: _passportNumberController.text.isNotEmpty
            ? _passportNumberController.text
            : null,
        city: _cityController.text.isNotEmpty ? _cityController.text : null,
        wpsStatus: _wpsStatus,
        releaseHold: _releaseHold,
        passportExpiryDate: _passportExpiryController.text.isNotEmpty
          ? _passportExpiryController.text
          : null,
        emiratesIdExpiryDate: _emiratesExpiryController.text.isNotEmpty
          ? _emiratesExpiryController.text
          : null,
        visaExpiryDate: _visaExpiryController.text.isNotEmpty
          ? _visaExpiryController.text
          : null,
        holdReason: _holdReasonController.text.isNotEmpty
          ? _holdReasonController.text
          : null,
        holdUntil: _holdUntilController.text.isNotEmpty
          ? _holdUntilController.text
          : null,
      );

      if (mounted) {
        setState(() => _isSubmitting = true);
      }

      if (widget.isAccountantCreate && widget.rider == null) {
        // Accountant direct create: Insert into tables directly to avoid RPC mismatch
        try {
          final supabase = Supabase.instance.client;

          // 1. Insert Rider and get the generated ID
          final riderData = rider.toJson();
          riderData.remove('id'); // Let DB generate UUID if it's new
          
          final riderResponse = await supabase
              .from('riders')
              .insert(riderData)
              .select('id')
              .single();

          final newRiderId = riderResponse['id'];

          // 2. Insert Aliases if any
          if (_aliases.isNotEmpty) {
            final conflictRows = <String>[];
            for (final a in _aliases) {
              final platform = (a['platform'] ?? '').toString();
              final platformRiderId = (a['platform_rider_id'] ?? '').toString();
              final validFrom = (a['valid_from'] as DateTime).toIso8601String().split('T').first;

              final previewRes = await supabase.rpc(
                'rpc_preview_rider_alias_conflicts',
                params: {
                  'p_rider_id': newRiderId,
                  'p_platform': platform,
                  'p_platform_rider_id': platformRiderId,
                  'p_valid_from': validFrom,
                },
              );

              Map<String, dynamic>? preview;
              if (previewRes is Map<String, dynamic>) preview = previewRes;
              if (previewRes is List && previewRes.isNotEmpty && previewRes.first is Map<String, dynamic>) {
                preview = previewRes.first as Map<String, dynamic>;
              }

              if ((preview?['has_conflict'] == true) || ((preview?['other_rider_conflicts'] ?? 0) > 0)) {
                conflictRows.add('$platform / $platformRiderId');
              }
            }

            if (conflictRows.isNotEmpty && mounted) {
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

            final aliasData = _aliases.map((a) => {
              'rider_id': newRiderId,
              'platform': a['platform'],
              'platform_rider_id': a['platform_rider_id'],
              'c3_id': a['c3_id'],
              'valid_from': (a['valid_from'] as DateTime).toIso8601String().split('T').first,
            }).toList();

            await supabase.from('rider_aliases').insert(aliasData);
          }

          if (mounted) {
            context.read<RidersBloc>().add(LoadRiders());
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Rider added successfully'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.pop(context);
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(toUserFriendlyError(e))),
            );
          }
        } finally {
          if (mounted) setState(() => _isSubmitting = false);
        }
      } else {
        try {
          final repo = context.read<RiderRepository>();

          if (widget.rider == null) {
            final createRider = rider.copyWith(status: _statusFromString(_selectedStatus));
            await repo.addRider(createRider);

            if (mounted) {
              context.read<RidersBloc>().add(LoadRiders());
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Rider added successfully'),
                  backgroundColor: Colors.green,
                ),
              );
              Navigator.pop(context);
            }
            return;
          }

          final originalStatus = _statusToString(widget.rider!.status);
          final statusChanged = originalStatus != _selectedStatus;

          if (statusChanged && (_selectedStatus == 'vacation' || _selectedStatus == 'retired')) {
            if (_statusReasonController.text.trim().isEmpty) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Reason is required for vacation/retired status')),
                );
              }
              return;
            }
          }

          await repo.updateRider(rider);

          if (statusChanged) {
            await ApiService.instance.updateRiderStatus(
              riderId: widget.rider!.id,
              status: _selectedStatus,
              reason: _statusReasonController.text.trim().isEmpty
                  ? null
                  : _statusReasonController.text.trim(),
              expectedReturnDate: _expectedReturnController.text.trim().isEmpty
                  ? null
                  : _expectedReturnController.text.trim(),
            );
          }

          if (mounted) {
            context.read<RidersBloc>().add(LoadRiders());
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Rider updated successfully'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.pop(context);
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(toUserFriendlyError(e))),
            );
          }
        } finally {
          if (mounted) setState(() => _isSubmitting = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
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
                widget.rider == null ? "Add Rider" : "Edit Rider",
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(height: 32),
              // Rider Code with Generate button
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Rider ID*",
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _riderCodeController,
                          validator: (v) =>
                              RiderCodeUtils.validateRiderCode(v) ??
                              _riderCodeError,
                          decoration: InputDecoration(
                            hintText: "e.g., RD#29A7! or A1@B2#C3",
                            hintStyle: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                            suffixIcon: _riderCodeError != null
                                ? Icon(Icons.error,
                                    color: AppTheme.errorColor, size: 20)
                                : (RiderCodeUtils.isValidFormat(
                                        _riderCodeController.text)
                                    ? const Icon(Icons.check_circle,
                                        color: Colors.green, size: 20)
                                    : null),
                            filled: true,
                            fillColor: Colors.grey[50],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  BorderSide(color: Colors.grey[200]!),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  BorderSide(color: Colors.grey[200]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: AppTheme.primaryColor),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _riderCodeController.text =
                                RiderCodeUtils.generateRandomCode();
                            _riderCodeError = null;
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Icon(Icons.refresh, size: 20),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 32),
              _buildSectionTitle("Personal Information"),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _nameController,
                label: "Rider Name*",
                hint: "Enter full name",
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _emiratesIdController,
                label: "Emirates ID*",
                hint: "784-xxxx-xxxxxxx-x",
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v!.isEmpty) return "Required";
                  if (!RegExp(r'^[0-9-]+$').hasMatch(v)) return "Numeric only";
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _phoneController,
                label: "Phone Number",
                hint: "+97150xxxxxxx",
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _passportNumberController,
                label: "Passport Number",
                hint: "Enter passport number",
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _cityController,
                label: "City",
                hint: "e.g. Dubai, Abu Dhabi",
              ),
              const SizedBox(height: 16),
              // Accountant-only fields when creating directly
              if (widget.isAccountantCreate) ...[
                _buildSectionTitle("Payroll Configuration"),
                const SizedBox(height: 8),
                if (widget.rider != null) ...[
                  _buildDropdown(
                    "Rider Status",
                    _selectedStatus,
                    ['active', 'vacation', 'retired'],
                    (v) => setState(() => _selectedStatus = v!),
                  ),
                  if (_selectedStatus == 'vacation' || _selectedStatus == 'retired') ...[
                    _buildTextField(
                      controller: _statusReasonController,
                      label: "Status Reason*",
                      hint: "Why status changed",
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_selectedStatus == 'vacation') ...[
                    _buildTextField(
                      controller: _expectedReturnController,
                      label: "Expected Return (YYYY-MM-DD)",
                      hint: "e.g. 2026-05-01",
                      readOnly: true,
                      onTap: () => _pickDateInto(_expectedReturnController),
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
                _buildDropdown("WPS Status", _wpsStatus, ['WPS', 'Non-WPS'], (v) => setState(() => _wpsStatus = v!)),
                _buildDropdown("Release/Hold", _releaseHold, ['release', 'hold'], (v) => setState(() => _releaseHold = v!)),
                if (_releaseHold == 'hold') ...[
                  _buildTextField(
                    controller: _holdReasonController,
                    label: "Hold Reason",
                    hint: "Why this rider is on hold (optional)",
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _holdUntilController,
                    label: "Hold Until (YYYY-MM-DD)",
                    hint: "e.g. 2026-12-31",
                    readOnly: true,
                    onTap: () => _pickDateInto(_holdUntilController),
                    suffixIcon: const Icon(Icons.calendar_today),
                  ),
                ],
                const SizedBox(height: 16),
                _buildSectionTitle("Document Expiry"),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _passportExpiryController,
                  label: "Passport Expiry (YYYY-MM-DD)",
                  hint: "e.g. 2028-03-15",
                  readOnly: true,
                  onTap: () => _pickDateInto(_passportExpiryController),
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _emiratesExpiryController,
                  label: "Emirates ID Expiry (YYYY-MM-DD)",
                  hint: "e.g. 2027-08-01",
                  readOnly: true,
                  onTap: () => _pickDateInto(_emiratesExpiryController),
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                const SizedBox(height: 16),
                _buildSectionTitle("Platform Aliases"),
                const SizedBox(height: 8),
                ..._aliases.asMap().entries.map((entry) => _buildAliasRow(entry.key, entry.value)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _addAlias,
                  icon: const Icon(Icons.add),
                  label: const Text("Add Alias"),
                ),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _saveRider,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSubmitting
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Please wait...',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                            ),
                          ],
                        )
                      : Text(
                          'Save Details',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                        ),
                ),
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
      style: GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.grey[600],
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool readOnly = false,
    VoidCallback? onTap,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          readOnly: readOnly,
          onTap: onTap,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(fontSize: 14, color: Colors.grey),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: Colors.grey[50],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[200]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[200]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.primaryColor),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
      ],
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
