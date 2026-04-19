import '../models/fines_model.dart';

abstract class VehicleRepository {
  Future<List<Map<String, dynamic>>> fetchBikes();
  Future<void> createBike(String plateNumber, {String? model, String? salikId, required String chassisNumber});
  Future<void> deleteBike(String chassisNumber);
  Future<void> returnBike(String chassisNumber);
  Future<List<BikeAssignmentModel>> fetchBikeAssignments();
  Future<Map<String, String>> fetchActiveAssignments();
  Future<bool> checkActiveAssignment(String chassisNumber);
  Future<bool> checkRiderActiveAssignment(String riderId);
  Future<void> assignBike({
    required String chassisNumber,
    required String riderId,
    required String riderName,
    required String assignedAt,
  });
  Future<void> updateBikeStatus(String chassisNumber, String status);
  Future<Map<String, BikeAssignmentModel>> fetchFullActiveAssignments();
}
