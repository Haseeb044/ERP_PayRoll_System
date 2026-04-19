import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/fines_model.dart';
import 'fines_repository.dart'; // For FinesRepository interface

class SupabaseFinesRepository implements FinesRepository {
  final SupabaseClient _client = Supabase.instance.client;

  @override
  Future<List<FineModel>> fetchFines() async {
    try {
      final response = await _client
          .from('traffic_fines')
          .select()
          .order('violation_date', ascending: false)
          .limit(1000);
      return (response as List)
          .map((item) => FineModel.fromJson(item))
          .toList();
    } catch (e) {
      print("Error fetching fines: $e");
      return [];
    }
  }

  @override
  Stream<List<FineModel>> getFinesStream() async* {
    // Polling avoids websocket/DNS realtime failures from crashing consumer blocs.
    while (true) {
      yield await fetchFines();
      await Future<void>.delayed(const Duration(seconds: 15));
    }
  }

  @override
  Future<List<BikeModel>> fetchBikes() async {
    try {
      final response = await _client.from('bikes').select();
      return (response as List).map((e) => BikeModel.fromJson(e)).toList();
    } catch (e) {
      print("Error fetching bikes: $e");
      return [];
    }
  }

  @override
  Future<List<BikeAssignmentModel>> fetchAssignments() async {
    try {
      final response = await _client
          .from('bike_assignment')
          .select()
          .order('assigned_at', ascending: false)
          .limit(1000);
      return (response as List)
          .map((e) => BikeAssignmentModel.fromJson(e))
          .toList();
    } catch (e) {
      print("Error fetching assignments: $e");
      return [];
    }
  }

  @override
  Future<void> assignFine(String fineId, String riderId) async {
    try {
      // 1. Fetch fine amount to set initial remaining_balance if needed
      final fineResponse = await _client
          .from('traffic_fines')
          .select('amount, remaining_balance')
          .eq('id', fineId)
          .single();
      final amount = (fineResponse['amount'] as num).toDouble();
      final currentBalance = fineResponse['remaining_balance'] != null
          ? (fineResponse['remaining_balance'] as num).toDouble()
          : amount;

      // 2. Fetch rider name for denormalization (as per schema)
      final riderResponse = await _client
          .from('riders')
          .select('name')
          .eq('id', riderId)
          .single();
      final riderName = riderResponse['name'];

      // 3. Update fine record
      await _client
          .from('traffic_fines')
          .update({
            'rider_id': riderId,
            'rider_name': riderName,
            'status': 'assigned',
            'remaining_balance': currentBalance,
          })
          .eq('id', fineId);
    } catch (e) {
      print("Error assigning fine: $e");
      throw e;
    }
  }

  @override
  Future<Map<String, dynamic>> fetchAssignmentProof(String fineId) async {
    try {
      // Fetch fine first
      final fineData = await _client
          .from('traffic_fines')
          .select()
          .eq('id', fineId)
          .single();
      final fine = FineModel.fromJson(fineData);

      if (fine.riderId == null) {
        return {'fine': fine};
      }

      // Fetch rider
      final riderData = await _client
          .from('riders')
          .select()
          .eq('id', fine.riderId!)
          .single();

      // Fetch the specific assignment that spans the violation date
      // Note: violation_date is TIMESTAMPTZ.
      final assignmentData = await _client
          .from('bike_assignment')
          .select()
          .eq('bike_id', fine.plateNumber)
          .lte('assigned_at', fine.violationDate.toIso8601String())
          .or(
            'returned_at.is.null,returned_at.gte.${fine.violationDate.toIso8601String()}',
          )
          .maybeSingle();

      return {'fine': fine, 'rider': riderData, 'assignment': assignmentData};
    } catch (e) {
      print("Error fetching assignment proof: $e");
      throw e;
    }
  }

  @override
  Future<void> bulkUpdateStatus(List<String> ids, String status) async {
    try {
      await _client
          .from('traffic_fines')
          .update({'status': status})
          .filter('id', 'in', ids);
    } catch (e) {
      print("Error in bulk status update: $e");
      throw e;
    }
  }

  @override
  Future<void> updateFineAmount(String fineId, double amount) async {
    try {
      await _client
          .from('traffic_fines')
          .update({'amount': amount})
          .eq('id', fineId);
    } catch (e) {
      print("Error updating fine amount: $e");
      throw e;
    }
  }

  @override
  Future<List<FineModel>> uploadFinesSheet(List<int> fileBytes) async {
    // This is currently handled by ExcelService.parseFines which directly uploads.
    // For consistency, we should move the upload logic here later.
    // For now, return empty to satisfy interface.
    return [];
  }

  @override
  Future<void> unlinkFine(String fineId) async {
    try {
      await _client
          .from('traffic_fines')
          .update({'rider_id': null, 'rider_name': null, 'status': 'unmatched'})
          .eq('id', fineId);
    } catch (e) {
      print("Error unlinking fine: $e");
      throw e;
    }
  }

  @override
  Future<void> payFinesToGovernment(
    List<String> fineIds,
    String drawerId,
  ) async {
    if (fineIds.isEmpty) return;
    try {
      final finesData = await _client
          .from('traffic_fines')
          .select('id, amount, ticket_number, plate_number')
          .inFilter('id', fineIds);
      if (finesData.isEmpty) return;

      double totalAmount = 0;
      List<String> descriptions = [];
      for (var f in finesData) {
        totalAmount += (f['amount'] as num).toDouble();
        descriptions.add("${f['ticket_number']} (${f['plate_number']})");
      }

      // 1. Fetch drawer balance
      final drawer = await _client
          .from('drawer')
          .select('balance')
          .eq('id', drawerId)
          .single();
      final double currentBalance = (drawer['balance'] as num).toDouble();

      if (currentBalance < totalAmount) {
        throw Exception("Insufficient funds in drawer.");
      }

      // 2. Create Journal (strict schema compatibility)
      final String today = DateTime.now().toIso8601String().split('T').first;
      final String? userId = _client.auth.currentUser?.id;
      // No VAT for fines, so base_amount = total_amount, vat_rate = 0, vat_amount = 0
      final baseAmount = totalAmount;
      final vatRate = 0;
      final vatAmount = 0;
      final total = baseAmount + vatAmount;

      final journalRes = await _client
          .from('journals')
          .insert({
            'entry_date': today,
            'description':
                "Traffic fines: " +
                descriptions.take(3).join(', ') +
                (descriptions.length > 3 ? '...' : ''),
            'total_amount': total,
            'base_amount': baseAmount,
            'vat_rate': vatRate,
            'vat_amount': vatAmount,
            'status': 'posted',
            'type': 'expense',
            'created_by_user_id': userId,
            'drawer_id': drawerId,
            'payment_method': 'cash', // or infer from drawer type if needed
          })
          .select('id')
          .single();

      final journalId = journalRes['id'];

      // 3. Insert Journal Lines (no description field, strict schema)
      await _client.from('journal_lines').insert([
        {
          'journal_id': journalId,
          'account_id': 'expense_receivable',
          'debit_amount': totalAmount,
          'credit_amount': 0.0,
        },
        {
          'journal_id': journalId,
          'account_id': 'bank_drawer',
          'debit_amount': 0.0,
          'credit_amount': totalAmount,
          'drawer_id': drawerId,
        },
      ]);

      // 4. Update Drawer Balance
      await _client
          .from('drawer')
          .update({'balance': currentBalance - totalAmount})
          .eq('id', drawerId);

      // 5. Update Fines
      await _client
          .from('traffic_fines')
          .update({
            'paid_to_govt_date': DateTime.now().toIso8601String(),
            'paid_to_govt_drawer': drawerId,
            'paid_to_govt_journal_id': journalId,
          })
          .inFilter('id', fineIds);
    } catch (e) {
      print("Error paying fines to government: $e");
      throw Exception("Payment failed: $e");
    }
  }
}
