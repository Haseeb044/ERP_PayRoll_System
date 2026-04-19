import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_theme.dart';
import '../../utils/rider_code_utils.dart';

class ProAddRiderPage extends StatefulWidget {
  const ProAddRiderPage({super.key});

  @override
  State<ProAddRiderPage> createState() => _ProAddRiderPageState();
}

class _ProAddRiderPageState extends State<ProAddRiderPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _riderCodeController;
  late TextEditingController _nameController;
  late TextEditingController _emiratesIdController;
  late TextEditingController _phoneController;
  late TextEditingController _passportController;
  late TextEditingController _cityController;

  String? _riderCodeError;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _riderCodeController =
        TextEditingController(text: RiderCodeUtils.generateRandomCode());
    _nameController = TextEditingController();
    _emiratesIdController = TextEditingController();
    _phoneController = TextEditingController();
    _passportController = TextEditingController();
    _cityController = TextEditingController();
  }

  @override
  void dispose() {
    _riderCodeController.dispose();
    _nameController.dispose();
    _emiratesIdController.dispose();
    _phoneController.dispose();
    _passportController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _riderCodeController.text = RiderCodeUtils.generateRandomCode();
    _nameController.clear();
    _emiratesIdController.clear();
    _phoneController.clear();
    _passportController.clear();
    _cityController.clear();
    setState(() => _riderCodeError = null);
  }

  Future<void> _submitForm() async {
    setState(() => _riderCodeError = null);

    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Validate rider code format
    final codeError = RiderCodeUtils.validateRiderCode(_riderCodeController.text);
    if (codeError != null) {
      setState(() => _riderCodeError = codeError);
      _formKey.currentState!.validate();
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final supabase = Supabase.instance.client;

      // 1. Submit Rider Request in one atomic transaction
      await supabase.rpc('rpc_submit_rider_request', params: {
        'p_rider_code': _riderCodeController.text,
        'p_name': _nameController.text,
        'p_emirates_id_number': _emiratesIdController.text,
        'p_phone': _phoneController.text.isNotEmpty ? _phoneController.text : null,
        'p_passport_number': _passportController.text.isNotEmpty ? _passportController.text : null,
        'p_city': _cityController.text.isNotEmpty ? _cityController.text : null,
      });


      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Rider submitted for review"),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );

        _resetForm();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error creating rider: $e"),
            backgroundColor: AppTheme.errorColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 700;
    final pad = isNarrow ? 16.0 : 28.0;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackgroundColor,
      body: SingleChildScrollView(
        padding: EdgeInsets.all(pad),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Add Rider",
                style: GoogleFonts.poppins(
                  fontSize: isNarrow ? 22 : 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Create a new rider entry for accountant review",
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),

              // Rider ID Field
              _buildTextField(
                controller: _riderCodeController,
                label: "Rider ID*",
                hint: "e.g., RD#29A7! or A1@B2#C3",
                validator: (v) =>
                    RiderCodeUtils.validateRiderCode(v) ?? _riderCodeError,
                suffixIcon: _riderCodeError != null
                    ? Icon(Icons.error, color: AppTheme.errorColor, size: 20)
                    : (RiderCodeUtils.isValidFormat(_riderCodeController.text)
                        ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                        : null),
              ),
              const SizedBox(height: 20),

              // Name Field
              _buildTextField(
                controller: _nameController,
                label: "Rider Name*",
                hint: "Enter full name",
                validator: (v) => v!.isEmpty ? "Name is required" : null,
              ),
              const SizedBox(height: 20),

              // Emirates ID Field
              _buildTextField(
                controller: _emiratesIdController,
                label: "Emirates ID*",
                hint: "784-xxxx-xxxxxxx-x",
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v!.isEmpty) return "Emirates ID is required";
                  if (!RegExp(r'^[0-9-]+$').hasMatch(v)) {
                    return "Numeric only";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Phone Field
              _buildTextField(
                controller: _phoneController,
                label: "Phone Number",
                hint: "+97150xxxxxxx",
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 20),

              // Passport Number Field
              _buildTextField(
                controller: _passportController,
                label: "Passport Number",
                hint: "Enter passport number",
              ),
              const SizedBox(height: 20),

              // City Field
              _buildTextField(
                controller: _cityController,
                label: "City",
                hint: "e.g. Dubai, Abu Dhabi",
              ),
              const SizedBox(height: 40),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitForm,
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
                            Text(
                              "Please wait...",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          "Add Rider",
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
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
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.errorColor),
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
}
