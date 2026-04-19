import '../models/rider_model.dart';

abstract class RiderRepository {
  Future<List<RiderModel>> fetchRiders();
  Stream<List<RiderModel>> getRidersStream();
  Future<void> addRider(RiderModel rider);
  Future<void> updateRider(RiderModel updatedRider);
  Future<String> createGhostRider(String name);
}
