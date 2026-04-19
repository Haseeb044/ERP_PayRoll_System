import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/rider_model.dart';
import 'rider_repository.dart';

class SupabaseRiderRepository implements RiderRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<Map<String, Map<String, String>>> _fetchAliasMap(
    List<Map<String, dynamic>> riders,
  ) async {
    final ids = riders
        .map((r) => (r['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return {};

    final aliases = await _client
        .from('rider_aliases')
        .select('rider_id, platform, platform_rider_id, status, valid_to')
        .inFilter('rider_id', ids);

    final aliasMap = <String, Map<String, String>>{};
    for (final row in aliases as List) {
      final a = Map<String, dynamic>.from(row as Map);
      final riderId = (a['rider_id'] ?? '').toString();
      final platform = (a['platform'] ?? '').toString().toLowerCase();
      final platformId = (a['platform_rider_id'] ?? '').toString();
      final status = (a['status'] ?? '').toString().toLowerCase();
      final validTo = a['valid_to'];

      if (riderId.isEmpty || platformId.isEmpty || platform.isEmpty) continue;
      if (status == 'inactive') continue;
      // Prefer currently active alias entries when available.
      if (validTo != null && validTo.toString().isNotEmpty) continue;

      aliasMap.putIfAbsent(riderId, () => {});
      aliasMap[riderId]![platform] = platformId;
    }

    return aliasMap;
  }

  List<RiderModel> _mergeRidersWithAliases(
    List<Map<String, dynamic>> riderRows,
    Map<String, Map<String, String>> aliasMap,
  ) {
    return riderRows.map((row) {
      final riderId = (row['id'] ?? '').toString();
      final aliases = aliasMap[riderId] ?? const <String, String>{};
      final enriched = Map<String, dynamic>.from(row)
        ..['talabat_id'] = aliases['talabat']
        ..['keeta_id'] = aliases['keeta'];
      return RiderModel.fromJson(enriched);
    }).toList();
  }

  @override
  Future<List<RiderModel>> fetchRiders() async {
    try {
      final response = await _client.from('riders').select();
      final riders = (response as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final aliasMap = await _fetchAliasMap(riders);
      return _mergeRidersWithAliases(riders, aliasMap);
    } catch (e) {
      print("Error fetching riders: $e");
      return []; // Return empty list or throw
    }
  }

  @override
  Stream<List<RiderModel>> getRidersStream() async* {
    // Polling avoids websocket/DNS realtime failures from crashing consumer blocs.
    while (true) {
      yield await fetchRiders();
      await Future<void>.delayed(const Duration(seconds: 15));
    }
  }

  @override
  Future<void> addRider(RiderModel rider) async {
    try {
      await _client.from('riders').insert(rider.toJson());
    } catch (e) {
      print("Error adding rider: $e");
      throw e;
    }
  }

  @override
  Future<void> updateRider(RiderModel updatedRider) async {
    try {
      await _client
          .from('riders')
          .update(updatedRider.toJson())
          .eq('id', updatedRider.id);
    } catch (e) {
      print("Error updating rider: $e");
      throw e;
    }
  }

  @override
  Future<String> createGhostRider(String name) async {
    try {
      final response = await _client
          .from('riders')
          .insert({
            'name': '[Ghost] $name',
            'status': 'retired',
            'city': 'Unknown',
          })
          .select('id')
          .single();

      return response['id'].toString();
    } catch (e) {
      print("Error creating ghost rider: $e");
      throw Exception("Failed to create ghost rider: $e");
    }
  }
}
