import '../models/fines_model.dart';

abstract class FinesRepository {
  Future<List<FineModel>> fetchFines();
  Stream<List<FineModel>> getFinesStream();
  Future<List<BikeModel>> fetchBikes();
  Future<List<BikeAssignmentModel>> fetchAssignments();
  Future<List<FineModel>> uploadFinesSheet(List<int> fileBytes);
  Future<void> assignFine(String fineId, String riderId);
  Future<Map<String, dynamic>> fetchAssignmentProof(String fineId);
  Future<void> bulkUpdateStatus(List<String> ids, String status);
  Future<void> updateFineAmount(String fineId, double amount);
  Future<void> unlinkFine(String fineId);
  Future<void> payFinesToGovernment(List<String> fineIds, String drawerId);
}
