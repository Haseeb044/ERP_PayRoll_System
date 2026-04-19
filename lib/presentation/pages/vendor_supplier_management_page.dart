import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rider_payroll_erp/core/app_theme.dart';
import 'package:rider_payroll_erp/services/api_service.dart';

class VendorSupplierManagementPage extends StatefulWidget {
  const VendorSupplierManagementPage({super.key});

  @override
  State<VendorSupplierManagementPage> createState() =>
      _VendorSupplierManagementPageState();
}

class _VendorSupplierManagementPageState
    extends State<VendorSupplierManagementPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoadingVendors = true;
  bool _isLoadingSuppliers = true;
  List<Map<String, dynamic>> _vendors = [];
  List<Map<String, dynamic>> _suppliers = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadVendors();
    _loadSuppliers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadVendors() async {
    setState(() => _isLoadingVendors = true);
    try {
      final rows = await ApiService.instance.getVendors(status: 'active');
      if (!mounted) return;
      setState(() {
        _vendors = rows;
        _isLoadingVendors = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingVendors = false);
    }
  }

  Future<void> _loadSuppliers() async {
    setState(() => _isLoadingSuppliers = true);
    try {
      final rows = await ApiService.instance.getSuppliers(status: 'active');
      if (!mounted) return;
      setState(() {
        _suppliers = rows;
        _isLoadingSuppliers = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingSuppliers = false);
    }
  }

  Future<void> _showCreateDialog(String type) async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final addressController = TextEditingController();
    final vatController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: Text(
            type == 'vendor' ? 'Create Vendor' : 'Create Supplier',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Name *'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: phoneController,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: addressController,
                    decoration: const InputDecoration(labelText: 'Address'),
                  ),
                  if (type == 'vendor') ...[
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: vatController,
                      decoration: const InputDecoration(
                        labelText: 'VAT No (optional)',
                      ),
                    ),
                  ],
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
                      setLocalState(() => isSubmitting = true);
                      try {
                        if (type == 'vendor') {
                          await ApiService.instance.createVendor(
                            name: nameController.text.trim(),
                            phone: phoneController.text.trim().isEmpty
                                ? null
                                : phoneController.text.trim(),
                            email: emailController.text.trim().isEmpty
                                ? null
                                : emailController.text.trim(),
                            address: addressController.text.trim().isEmpty
                                ? null
                                : addressController.text.trim(),
                            vatNo: vatController.text.trim().isEmpty
                                ? null
                                : vatController.text.trim(),
                            vatApplicable: true,
                            status: 'active',
                          );
                          await _loadVendors();
                        } else {
                          await ApiService.instance.createSupplier(
                            name: nameController.text.trim(),
                            phone: phoneController.text.trim().isEmpty
                                ? null
                                : phoneController.text.trim(),
                            email: emailController.text.trim().isEmpty
                                ? null
                                : emailController.text.trim(),
                            address: addressController.text.trim().isEmpty
                                ? null
                                : addressController.text.trim(),
                            status: 'active',
                          );
                          await _loadSuppliers();
                        }

                        if (!mounted) return;
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              type == 'vendor'
                                  ? 'Vendor created successfully'
                                  : 'Supplier created successfully',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        setLocalState(() => isSubmitting = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed: $e'),
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
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntityList({
    required bool isLoading,
    required List<Map<String, dynamic>> rows,
    required String entityLabel,
    required VoidCallback onCreate,
  }) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (rows.isEmpty) {
      return Center(
        child: Text(
          'No $entityLabel found',
          style: GoogleFonts.poppins(color: Colors.grey),
        ),
      );
    }

    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: Text('Create $entityLabel'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final r = rows[index];
              final name = r['name']?.toString() ?? '-';
              final code =
                  (r['vendor_code'] ?? r['supplier_code'])?.toString() ?? '';
              final phone = r['phone']?.toString() ?? '-';
              final email = r['email']?.toString() ?? '-';
              final status = r['status']?.toString().toUpperCase() ?? 'ACTIVE';

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            code.isNotEmpty ? '$name ($code)' : name,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text('Phone: $phone',
                              style: GoogleFonts.poppins(fontSize: 12)),
                          Text('Email: $email',
                              style: GoogleFonts.poppins(fontSize: 12)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: status == 'ACTIVE'
                            ? Colors.green.withValues(alpha: 0.12)
                            : Colors.grey.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        status,
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: status == 'ACTIVE'
                              ? Colors.green
                              : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vendor & Supplier Management',
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 16),
            TabBar(
              controller: _tabController,
              labelColor: AppTheme.primaryColor,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppTheme.primaryColor,
              labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Vendors'),
                Tab(text: 'Suppliers'),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildEntityList(
                    isLoading: _isLoadingVendors,
                    rows: _vendors,
                    entityLabel: 'Vendor',
                    onCreate: () => _showCreateDialog('vendor'),
                  ),
                  _buildEntityList(
                    isLoading: _isLoadingSuppliers,
                    rows: _suppliers,
                    entityLabel: 'Supplier',
                    onCreate: () => _showCreateDialog('supplier'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
