import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../core/app_theme.dart';
import '../../data/models/fines_model.dart';
import '../../data/models/rider_model.dart';
import '../../data/repositories/vehicle_repository.dart';
import '../../data/repositories/rider_repository.dart';
import '../../utils/user_friendly_error.dart';

class FleetScreen extends StatefulWidget {
  const FleetScreen({super.key});

  @override
  State<FleetScreen> createState() => _FleetScreenState();
}

class _FleetScreenState extends State<FleetScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Bikes Tab State
  List<dynamic> _bikes = [];
  Map<String, BikeAssignmentModel> _activeAssignments = {};
  bool _loadingBikes = true;
  String _bikeSearchQuery = '';
  final TextEditingController _bikeSearchController = TextEditingController();

  // History Tab State
  List<BikeAssignmentModel> _allHistoryItems = [];
  List<BikeAssignmentModel> _filteredHistoryItems = [];
  bool _loadingHistory = true;
  String _searchQuery = '';
  final TextEditingController _historySearchController = TextEditingController();
  DateTimeRange? _selectedDateRange;

  void _applyFilters() {
    setState(() {
      _filteredHistoryItems = _allHistoryItems.where((item) {
        final q = _searchQuery.trim().toLowerCase();
        if (q.isNotEmpty) {
          final plate = (item.plateNumber ?? '').toLowerCase();
          final chassis = item.chassisNumber.toLowerCase();
          final riderName = (item.riderName ?? '').toLowerCase();
          if (!plate.contains(q) && !chassis.contains(q) && !riderName.contains(q)) {
            return false;
          }
        }
        if (_selectedDateRange != null) {
          final dt = DateUtils.dateOnly(item.assignedAt.toLocal());
          final start = DateUtils.dateOnly(_selectedDateRange!.start);
          final end = DateUtils.dateOnly(_selectedDateRange!.end);
          if (dt.isBefore(start) || dt.isAfter(end)) {
            return false;
          }
        }
        return true;
      }).toList();
    });
  }

  void _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: AppTheme.primaryColor),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      _selectedDateRange = picked;
      _applyFilters();
    }
  }

  void _clearDateRange() {
    _selectedDateRange = null;
    _applyFilters();
  }

  String _getMonth(int m) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[m - 1];
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        if (_tabController.index == 0) {
          _loadBikesData();
        } else {
          _loadHistoryData();
        }
      }
    });
    _loadBikesData();
    _loadHistoryData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _bikeSearchController.dispose();
    _historySearchController.dispose();
    super.dispose();
  }

  Future<void> _loadBikesData() async {
    if (!mounted) return;
    setState(() => _loadingBikes = true);
    try {
      final repo = context.read<VehicleRepository>();
      final bikes = await repo.fetchBikes();
      final activeMap = await repo.fetchFullActiveAssignments();
      if (mounted) {
        setState(() {
          _bikes = bikes;
          _activeAssignments = activeMap;
          _loadingBikes = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingBikes = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(toUserFriendlyError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadHistoryData() async {
    if (!mounted) return;
    setState(() => _loadingHistory = true);
    try {
      final repo = context.read<VehicleRepository>();
      final history = await repo.fetchBikeAssignments();
      // fetchBikeAssignments handles ORDER BY assigned_at DESC in Supabase.
      if (mounted) {
        _allHistoryItems = history;
        _loadingHistory = false;
        _applyFilters();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingHistory = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(toUserFriendlyError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _refreshAll() async {
    await _loadBikesData();
    await _loadHistoryData();
  }

  Future<void> _addBike() async {
    final plateController = TextEditingController();
    final modelController = TextEditingController();
    final salikController = TextEditingController();
    final chassisController = TextEditingController();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add New Bike', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 360, maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: chassisController,
                  decoration: InputDecoration(
                    labelText: 'Vehicle Serial No (Chassis) *',
                    hintText: 'Required Unique Identifier',
                    prefixIcon: const Icon(Icons.qr_code_scanner),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: plateController,
                  decoration: InputDecoration(
                    labelText: 'Plate No *',
                    hintText: 'e.g. DXB-12345',
                    prefixIcon: const Icon(Icons.confirmation_number),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: modelController,
                  decoration: InputDecoration(
                    labelText: 'Model (Optional)',
                    hintText: 'e.g. Honda PCX',
                    prefixIcon: const Icon(Icons.pedal_bike),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: salikController,
                  decoration: InputDecoration(
                    labelText: 'Salik Tag ID (Optional)',
                    hintText: 'e.g. 1234567',
                    prefixIcon: const Icon(Icons.nfc),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
            onPressed: () {
              final chassis = chassisController.text.trim();
              final plate = plateController.text.trim();
              if (chassis.isEmpty || plate.isEmpty) {
                // Ideally show validation error
                return;
              }
              Navigator.pop(ctx, {
                'bike_id': plate,
                'model': modelController.text.trim(),
                'salik_id': salikController.text.trim(),
                'chassis_number': chassis,
              });
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null && result['bike_id']!.isNotEmpty) {
      try {
        final repo = context.read<VehicleRepository>();
        await repo.createBike(
          result['bike_id']!,
          model: result['model']!.isEmpty ? null : result['model'],
          salikId: result['salik_id']!.isEmpty ? null : result['salik_id'],
          chassisNumber: result['chassis_number']!,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Bike added successfully'), backgroundColor: Colors.green),
          );
        }
        _refreshAll();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(toUserFriendlyError(e)),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteBike(String chassisNumber, String plateNumber) async {
    if (_activeAssignments.containsKey(chassisNumber)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Return the bike first'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Bike'),
        content: Text('Remove bike (Plate No: $plateNumber)?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final repo = context.read<VehicleRepository>();
        await repo.deleteBike(chassisNumber);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bike deleted'), backgroundColor: Colors.green),
          );
        }
        _refreshAll();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(toUserFriendlyError(e)),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _assignBike(String chassisNumber) async {
    RiderModel? selectedRider;
    DateTime selectedDateTime = DateTime.now();
    List<RiderModel> activeRiders = [];

    try {
      final riderRepo = context.read<RiderRepository>();
      final allRiders = await riderRepo.fetchRiders();
      activeRiders = allRiders.where((r) => r.status == RiderStatus.active).toList();
      activeRiders.sort((a, b) => a.name.compareTo(b.name));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(toUserFriendlyError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text('Assign Bike', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
              content: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 360, maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Select Rider', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<RiderModel>(
                      value: selectedRider,
                      hint: const Text('Choose a rider'),
                      isExpanded: true,
                      items: activeRiders.map((r) => DropdownMenuItem(value: r, child: Text(r.name))).toList(),
                      onChanged: (val) => setStateDialog(() => selectedRider = val),
                      decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                    ),
                    const SizedBox(height: 16),
                    Text('Assignment Time', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: ctx,
                          initialDate: selectedDateTime,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (date != null) {
                          if (!ctx.mounted) return;
                          final time = await showTimePicker(
                            context: ctx,
                            initialTime: TimeOfDay.fromDateTime(selectedDateTime),
                          );
                          if (time != null) {
                            setStateDialog(() {
                              selectedDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                            });
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(10)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              DateFormat('yyyy-MM-dd HH:mm').format(selectedDateTime),
                              style: GoogleFonts.poppins(fontSize: 14),
                            ),
                            const Icon(Icons.calendar_today, size: 20, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: selectedRider == null ? null : () {
                    Navigator.pop(ctx, {'rider': selectedRider, 'time': selectedDateTime});
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                  child: const Text('Confirm'),
                ),
              ],
            );
          }
        );
      },
    );

    if (result != null) {
      if (!mounted) return;
      final RiderModel r = result['rider'];
      final DateTime t = result['time'];

      try {
        final repo = context.read<VehicleRepository>();
        
        // 1. Check if bike is already assigned
        final isBikeAssigned = await repo.checkActiveAssignment(chassisNumber);
        if (isBikeAssigned) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This bike is already assigned'), backgroundColor: Colors.red));
          }
          return;
        }

        // 2. Check if rider already has an active bike
        final isRiderAssigned = await repo.checkRiderActiveAssignment(r.id);
        if (isRiderAssigned) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This rider already has another active bike assignment'), backgroundColor: Colors.red));
          }
          return;
        }

        await repo.assignBike(
          chassisNumber: chassisNumber,
          riderId: r.id,
          riderName: r.name,
          assignedAt: t.toIso8601String(),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bike assigned successfully'), backgroundColor: Colors.green));
        }
        _refreshAll();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(toUserFriendlyError(e)),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _returnBike(String chassisNumber) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Return Bike'),
        content: const Text('Confirm return?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final repo = context.read<VehicleRepository>();
        await repo.returnBike(chassisNumber);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bike returned'), backgroundColor: Colors.green));
        }
        _refreshAll();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(toUserFriendlyError(e)),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _changeStatus(String chassisNumber, String currentStatus) async {
    final isAssigned = _activeAssignments.containsKey(chassisNumber);

    final newStatus = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Status'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Active'),
              leading: const Icon(Icons.check_circle, color: Colors.green),
              onTap: () => Navigator.pop(ctx, 'active'),
            ),
            ListTile(
              title: const Text('Maintenance'),
              leading: const Icon(Icons.build, color: Colors.orange),
              onTap: () => Navigator.pop(ctx, 'maintenance'),
            ),
            ListTile(
              title: const Text('Retired'),
              leading: const Icon(Icons.cancel, color: Colors.red),
              onTap: () {
                if (isAssigned) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Return the bike first'), backgroundColor: Colors.red));
                } else {
                  Navigator.pop(ctx, 'retired');
                }
              },
            ),
          ],
        ),
      ),
    );

    if (newStatus != null && newStatus != currentStatus) {
      if (newStatus == 'retired' && isAssigned) return;
      try {
        final repo = context.read<VehicleRepository>();
        await repo.updateBikeStatus(chassisNumber, newStatus);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Status updated'), backgroundColor: Colors.green));
        }
        _refreshAll();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(toUserFriendlyError(e)),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Color _getStatusColor(String status) {
    if (status == 'active') return Colors.green;
    if (status == 'maintenance') return Colors.orange;
    if (status == 'retired') return Colors.red;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(top: 32, left: 32, right: 32, bottom: 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Fleet and Assets',
                  style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            labelColor: AppTheme.primaryColor,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppTheme.primaryColor,
            tabs: const [
              Tab(text: 'Bikes'),
              Tab(text: 'Assignment History'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBikesTab(),
                _buildHistoryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBikesTab() {
    if (_loadingBikes) return const Center(child: CircularProgressIndicator());

    final activeCount = _bikes.where((b) => b['status'] == 'active').length;
    final availableCount = _bikes.where((b) => b['status'] == 'active' && !_activeAssignments.containsKey(b['chassis_number'] ?? '')).length;
    final maintCount = _bikes.where((b) => b['status'] == 'maintenance').length;
    final retiredCount = _bikes.where((b) => b['status'] == 'retired').length;
    final totalCount = _bikes.length;

    final filteredBikes = _bikes.where((bike) {
      if (_bikeSearchQuery.isEmpty) return true;
      final plate = (bike['bike_id'] ?? '').toString().toLowerCase();
      final chassis = (bike['chassis_number'] ?? '').toString().toLowerCase();
      final assignment = _activeAssignments[bike['chassis_number']];
      final riderName = (assignment?.riderName ?? '').toLowerCase();
      return plate.contains(_bikeSearchQuery) || chassis.contains(_bikeSearchQuery) || riderName.contains(_bikeSearchQuery);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _statCard('Total Bikes', totalCount.toString(), Colors.blue),
                  _statCard('Active', activeCount.toString(), Colors.teal),
                  _statCard('Available', availableCount.toString(), Colors.green),
                  _statCard('Maintenance', maintCount.toString(), Colors.orange),
                  _statCard('Retired', retiredCount.toString(), Colors.red),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _addBike,
                icon: const Icon(Icons.add),
                label: const Text('Add Bike'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _bikeSearchController,
            decoration: InputDecoration(
              hintText: 'Search by Plate No or Rider Name',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: (val) {
              setState(() => _bikeSearchQuery = val.trim().toLowerCase());
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: filteredBikes.isEmpty
                ? const Center(child: Text('No bikes found'))
                : ListView.builder(
                    itemCount: filteredBikes.length,
                    itemBuilder: (context, index) {
                      final bike = filteredBikes[index];
                      final plate = bike['bike_id'] ?? '';
                      final model = bike['model'] ?? '-';
                      final salikId = bike['salik_id'];
                      final chassisNo = bike['chassis_number'] ?? '';
                      final status = bike['status'] ?? 'active';
                      final assignment = _activeAssignments[chassisNo];
                      final isAssigned = assignment != null;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.pedal_bike, color: Colors.blue),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(plate, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(color: _getStatusColor(status).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                                          child: Text(status.toUpperCase(), style: GoogleFonts.poppins(color: _getStatusColor(status), fontSize: 10, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text('Model: $model', style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 12)),
                                    if (salikId != null)
                                      Row(
                                        children: [
                                          const Icon(Icons.nfc, size: 12, color: Colors.grey),
                                          const SizedBox(width: 4),
                                          Text('Salik: $salikId', style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 12)),
                                        ],
                                      ),
                                    if (chassisNo != null)
                                      Row(
                                        children: [
                                          const Icon(Icons.qr_code_scanner, size: 12, color: Colors.grey),
                                          const SizedBox(width: 4),
                                          Text('Serial: $chassisNo', style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 12)),
                                        ],
                                      ),
                                    const SizedBox(height: 4),
                                    if (isAssigned)
                                      Text('Assigned To: ${assignment.riderName ?? 'Unknown'}', style: GoogleFonts.poppins(fontWeight: FontWeight.w500))
                                    else
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                        child: Text('Available', style: GoogleFonts.poppins(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                                      ),
                                  ],
                                ),
                              ),
                              if (isAssigned)
                                IconButton(icon: const Icon(Icons.assignment_return, color: Colors.blue), onPressed: () => _returnBike(chassisNo))
                              else
                                IconButton(icon: const Icon(Icons.person_add, color: Colors.green), onPressed: () => _assignBike(chassisNo)),
                              IconButton(icon: const Icon(Icons.edit, color: Colors.orange), onPressed: () => _changeStatus(chassisNo, status)),
                              IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteBike(chassisNo, plate)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_loadingHistory) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _historySearchController,
                  decoration: InputDecoration(
                    hintText: 'Search by Plate No or Rider Name',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (val) {
                    _searchQuery = val.trim();
                    _applyFilters();
                  },
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                onPressed: _pickDateRange,
                icon: const Icon(Icons.date_range),
                color: AppTheme.primaryColor,
                tooltip: "Filter by Date Range",
              ),
              IconButton(
                 onPressed: _loadHistoryData,
                 icon: const Icon(Icons.refresh),
                 color: AppTheme.primaryColor,
                 tooltip: "Refresh List",
              ),
            ],
          ),
          if (_selectedDateRange != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.date_range, size: 14, color: AppTheme.primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        '${_selectedDateRange!.start.day} ${_getMonth(_selectedDateRange!.start.month)} ${_selectedDateRange!.start.year} - ${_selectedDateRange!.end.day} ${_getMonth(_selectedDateRange!.end.month)} ${_selectedDateRange!.end.year}',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _clearDateRange,
                        child: const Icon(Icons.close, size: 16, color: AppTheme.primaryColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: _filteredHistoryItems.isEmpty
                ? const Center(child: Text('No history found'))
                : ListView.builder(
                    itemCount: _filteredHistoryItems.length,
                    itemBuilder: (context, index) {
                      final item = _filteredHistoryItems[index];
                      final isActive = item.returnedAt == null;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: (isActive ? Colors.green : Colors.grey).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.history, color: isActive ? Colors.green : Colors.grey),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(item.plateNumber ?? item.chassisNumber, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(color: (isActive ? Colors.green : Colors.grey).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                                          child: Text(isActive ? 'ACTIVE' : 'RETURNED', style: GoogleFonts.poppins(color: isActive ? Colors.green : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text('Rider: ${item.riderName ?? 'Unknown'}', style: GoogleFonts.poppins(color: Colors.black87, fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 4),
                                    Text('Assigned: ${DateFormat('dd MMM yyyy').format(item.assignedAt)}', style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 12)),
                                    Text('Returned: ${item.returnedAt != null ? DateFormat('dd MMM yyyy').format(item.returnedAt!) : '-'}', style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

