import '../models/drawer_model.dart';

abstract class DrawerRepository {
  Future<List<DrawerModel>> fetchDrawers();
  Future<List<DrawerTransactionModel>> fetchTransactions(String? drawerId);
  Future<void> transferFunds({
    required String sourceDrawerId,
    required String targetDrawerId,
    required double amount,
    required String description,
  });
  Future<void> addTransaction(DrawerTransactionModel transaction);
  Future<bool> hasSufficientFunds(String drawerId, double amount);
}
