import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/fines_model.dart';
import 'vehicle_repository.dart';

class SupabaseVehicleRepository implements VehicleRepository {
  final SupabaseClient _client = Supabase.instance.client;

  @override
  Future<List<Map<String, dynamic>>> fetchBikes() async {
    try {
      final response = await _client.from('bikes').select('*').order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching bikes: $e');
      return [];
    }
  }

  @override
  Future<void> createBike(String plateNumber, {String? model, String? salikId, required String chassisNumber}) async {
    final trimmedSalik = (salikId != null && salikId.trim().isNotEmpty) ? salikId.trim() : null;
    await _client.from('bikes').insert({
      'bike_id': plateNumber,
      'model': model,
      'salik_id': trimmedSalik,
      'chassis_number': chassisNumber,
      'status': 'active',
    });
  }

  @override
  Future<void> deleteBike(String chassisNumber) async {
    await _client.from('bikes').delete().eq('chassis_number', chassisNumber);
  }

  @override
  Future<void> returnBike(String chassisNumber) async {
    final nowIso = DateTime.now().toIso8601String();
    await _client
        .from('bike_assignment')
        .update({'returned_at': nowIso})
        .eq('chassis_number', chassisNumber)
        .filter('returned_at', 'is', null);

    await _client.from('bikes').update({'status': 'active'}).eq('chassis_number', chassisNumber);
  }

  @override
  Future<List<BikeAssignmentModel>> fetchBikeAssignments() async {
    try {
      final response = await _client.from('bike_assignment').select('*, bikes(bike_id, chassis_number)').order('assigned_at', ascending: false);
      return (response as List).map((json) => BikeAssignmentModel.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching bike assignments: $e');
      return [];
    }
  }

  @override
  Future<Map<String, String>> fetchActiveAssignments() async {
    try {
      final response = await _client
          .from('bike_assignment')
          .select('chassis_number, rider_name')
          .filter('returned_at', 'is', null);
      
      final list = List<Map<String, dynamic>>.from(response);
      final map = <String, String>{};
      for (final row in list) {
        final bId = row['chassis_number']?.toString(); // Updated column name
        final rName = row['rider_name']?.toString();
        if (bId != null && rName != null) {
          map[bId] = rName;
        }
      }
      return map;
    } catch (e) {
      print('Error fetching active assignments: $e');
      return {};
    }
  }

  @override
  Future<bool> checkActiveAssignment(String chassisNumber) async {
    try {
      final response = await _client
          .from('bike_assignment')
          .select('id')
          .eq('chassis_number', chassisNumber)
          .filter('returned_at', 'is', null)
          .limit(1);
      return (response as List).isNotEmpty;
    } catch (e) {
      print('Error checking active assignment: $e');
      return false; 
    }
  }

  @override
  Future<bool> checkRiderActiveAssignment(String riderId) async {
    try {
      final response = await _client
          .from('bike_assignment')
          .select('id')
          .eq('rider_id', riderId)
          .filter('returned_at', 'is', null)
          .limit(1);
      return (response as List).isNotEmpty;
    } catch (e) {
      print('Error checking rider active assignment: $e');
      return false;
    }
  }

  @override
  Future<void> assignBike({
    required String chassisNumber,
    required String riderId,
    required String riderName,
    required String assignedAt,
  }) async {
    await _client.from('bike_assignment').insert({
      'chassis_number': chassisNumber,
      'rider_id': riderId,
      'rider_name': riderName,
      'assigned_at': assignedAt,
      'returned_at': null,
    });
    
    await _client.from('bikes').update({'status': 'active'}).eq('chassis_number', chassisNumber);
  }

  @override
  Future<void> updateBikeStatus(String chassisNumber, String status) async {
    await _client.from('bikes').update({'status': status}).eq('chassis_number', chassisNumber);
  }

  @override
  Future<Map<String, BikeAssignmentModel>> fetchFullActiveAssignments() async {
    try {
      final response = await _client
          .from('bike_assignment')
          .select('*, bikes(bike_id, chassis_number)')
          .filter('returned_at', 'is', null);
      
      final list = List<Map<String, dynamic>>.from(response);
      final map = <String, BikeAssignmentModel>{};
      for (final row in list) {
        final bId = row['chassis_number']?.toString();
        if (bId != null) {
          map[bId] = BikeAssignmentModel.fromJson(row);
        }
      }
      return map;
    } catch (e) {
      print('Error fetching full active assignments: $e');
      return {};
    }
  }
}
