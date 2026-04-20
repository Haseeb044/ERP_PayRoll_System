import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_theme.dart';
import '../../data/models/rider_model.dart';
import '../../utils/id_utils.dart';
import '../../data/repositories/supabase_rider_repository.dart';

class AliasResolutionScreen extends StatefulWidget {
  final String? actionItemId;
  final String? payslipId;
  final String? platform;
  final String? platformRiderId;
  final String? riderNameFromSheet;
  final double? grossSalary;
  final String? payrollMonth;

  const AliasResolutionScreen({
    super.key,
    this.actionItemId,
    this.payslipId,
    this.platform,
    this.platformRiderId,
    this.riderNameFromSheet,
    this.grossSalary,
    this.payrollMonth,
  });

  @override
  State<AliasResolutionScreen> createState() => _AliasResolutionScreenState();
}

class _AliasResolutionScreenState extends State<AliasResolutionScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  List<RiderModel> _searchResults = [];
  RiderModel? _selectedRider;
  bool _isSearching = false;
  bool _isSaving = false;
  bool _isLoadingData = false;

  // Local data to handle both direct params and fetched data
  String? _actionItemId;
  String? _payslipId;
  String? _platform;
  String? _platformRiderId;
  String? _riderNameFromSheet;
  double? _grossSalary;
  String? _payrollMonth;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    
    // Use params if provided, otherwise fetch
    if (widget.payslipId != null) {
      _payslipId = widget.payslipId;
      _platform = widget.platform;
      _platformRiderId = widget.platformRiderId;
      _riderNameFromSheet = widget.riderNameFromSheet;
      _grossSalary = widget.grossSalary;
      _payrollMonth = widget.payrollMonth;
      _searchController.text = _riderNameFromSheet ?? "";
    } else {
      _fetchActionData();
    }
  }

  Future<void> _fetchActionData() async {
    setState(() => _isLoadingData = true);
    try {
      // 1. Fetch Action Item
      Map<String, dynamic> actionRes;
      if (widget.actionItemId != null) {
        actionRes = await _supabase
            .from('action_items')
            .select()
            .eq('id', widget.actionItemId!)
            .single();
      } else if (widget.payslipId != null) {
        actionRes = await _supabase
            .from('action_items')
            .select()
            .eq('reference_id', widget.payslipId!)
            .eq('type', 'alias_mismatch')
            .single();
      } else {
        throw Exception("No identifiers provided to resolve alias");
      }
      
      _actionItemId = actionRes['id'].toString();
      final metadata = actionRes['metadata'] as Map<String, dynamic>?;
      final payslipId = actionRes['reference_id']?.toString();

      if (payslipId == null) throw Exception("No payslip linked to this action");

      // 2. Fetch Payslip
      final payslipRes = await _supabase
          .from('payslips')
          .select()
          .eq('id', payslipId)
          .single();

      if (mounted) {
        setState(() {
          _payslipId = payslipId;
          _platform = metadata?['platform']?.toString() ?? payslipRes['platform_data']?['platform']?.toString() ?? "Unknown";
          _platformRiderId = metadata?['platform_rider_id']?.toString() ?? payslipRes['external_id']?.toString() ?? "";
          _riderNameFromSheet = metadata?['rider_name_from_sheet']?.toString() ?? payslipRes['rider_name']?.toString() ?? "Unknown";
          _grossSalary = (payslipRes['gross_salary'] as num?)?.toDouble() ?? 0.0;
          _payrollMonth = metadata?['month']?.toString() ?? "Unknown";
          
          _searchController.text = _riderNameFromSheet!;
          _isLoadingData = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading action data: $e")),
        );
        setState(() => _isLoadingData = false);
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query.length < 2) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    _performSearch(query);
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isSearching = true);
    try {
      final response = await _supabase
          .from('riders')
          .select()
          .ilike('name', '%$query%')
          .limit(10);
      
      if (mounted) {
        setState(() {
          _searchResults = (response as List)
              .map((e) => RiderModel.fromJson(e))
              .toList();
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  Future<void> _handleConfirm() async {
    if (_selectedRider == null) return;

    setState(() => _isSaving = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception("User not authenticated");

      final String validFrom = "${_payrollMonth}-01";

      // Call the RPC function we created
      await _supabase.rpc('fn_resolve_alias_manually', params: {
        'p_action_item_id': _actionItemId!,
        'p_payslip_id': _payslipId!,
        'p_rider_id': _selectedRider!.id,
        'p_platform': _platform!.toLowerCase(),
        'p_platform_rider_id': cleanPlatformId(_platformRiderId!),
        'p_valid_from': validFrom,
        'p_resolved_by': user.id,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Rider alias resolved successfully!"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true); // Return success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error resolving alias: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _handleCreateGhostRider() async {
    final name = _searchController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final repo = SupabaseRiderRepository();
      final newRiderId = await repo.createGhostRider(name);

      setState(() {
        _selectedRider = RiderModel(
          id: newRiderId,
          name: '[Ghost] $name',
          status: RiderStatus.retired,
        );
      });

      await _handleConfirm();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error creating ghost rider: $e"),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isSaving = false);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return Scaffold(
        appBar: AppBar(title: const Text("Loading...")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_payslipId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Error")),
        body: const Center(child: Text("Could not load resolution data.")),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          "Unresolved Rider Alias",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info Card
            _buildInfoCard(),
            const SizedBox(height: 32),
            
            // Search Section
            Text(
              "Matching Internal Rider",
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 12),
            _buildSearchBar(),
            const SizedBox(height: 16),
            
            // Results List
            _buildResultsList(),
            
            const SizedBox(height: 16),
            if (_searchController.text.length >= 2)
               Center(
                 child: TextButton.icon(
                   onPressed: _isSaving ? null : _handleCreateGhostRider,
                   icon: const Icon(Icons.person_add_alt_1),
                   label: Text("Quick Create '${_searchController.text}' Ghost Profile"),
                   style: TextButton.styleFrom(
                     foregroundColor: Colors.orange[800],
                     textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                   ),
                 )
               ),
            
            const SizedBox(height: 40),
            
            // Action Button
            _buildConfirmButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    final cleanedId = cleanPlatformId(_platformRiderId);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFEF4444),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Data from Excel Sheet",
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    Text(
                      _riderNameFromSheet ?? "Unknown",
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 32, color: Color(0xFFE2E8F0)),
          _buildInfoRow(Icons.apps, "Platform", _platform ?? "Unknown"),
          _buildInfoRow(Icons.numbers, "Platform ID", cleanedId),
          _buildInfoRow(Icons.payments, "Gross Salary", "AED ${_grossSalary?.toStringAsFixed(2) ?? '0.00'}"),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 8),
          Text(
            "$label: ",
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: const Color(0xFF64748B),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: "Search by rider name...",
        prefixIcon: const Icon(Icons.search, color: Color(0xFF94A3B8)),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.primaryColor),
        ),
        suffixIcon: _isSearching
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
      ),
    );
  }

  Widget _buildResultsList() {
    if (_searchResults.isEmpty) {
      if (_searchController.text.length < 2) {
        return const SizedBox.shrink();
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            "No riders found matching '${_searchController.text}'",
            style: GoogleFonts.poppins(color: const Color(0xFF64748B)),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _searchResults.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final rider = _searchResults[index];
          final isSelected = _selectedRider?.id == rider.id;
          
          return ListTile(
            onTap: () => setState(() => _selectedRider = rider),
            selected: isSelected,
            selectedTileColor: AppTheme.primaryColor.withValues(alpha: 0.05),
            leading: CircleAvatar(
              backgroundColor: isSelected ? AppTheme.primaryColor : const Color(0xFFF1F5F9),
              child: Icon(
                Icons.person,
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                size: 20,
              ),
            ),
            title: Text(
              rider.name,
              style: GoogleFonts.poppins(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: const Color(0xFF1E293B),
              ),
            ),
            subtitle: Text(
              "${rider.city ?? 'No City'} â€¢ ${rider.status.name.toUpperCase()}",
              style: GoogleFonts.poppins(fontSize: 12),
            ),
            trailing: isSelected
                ? Icon(Icons.check_circle, color: AppTheme.primaryColor)
                : const Icon(Icons.chevron_right, size: 18),
          );
        },
      ),
    );
  }

  Widget _buildConfirmButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: (_selectedRider == null || _isSaving) ? null : _handleConfirm,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: _isSaving
            ? const CircularProgressIndicator(color: Colors.white)
            : Text(
                "Confirm & Link Rider",
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}

