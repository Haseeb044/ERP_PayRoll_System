import '../models/journal_model.dart';
import '../models/user_model.dart';

abstract class JournalRepository {
  Future<List<JournalModel>> fetchJournals({UserRole? role, String? userId, JournalStatus? status});
  Future<Map<String, String?>> createJournal(JournalModel journal);
  Future<void> approveJournal({
    required String journalId,
    required String drawerId,
    required String paymentMethod,
    bool isReceivable = false,
    double? receivableAmount,
    String? riderId,
    List<Map<String, dynamic>> lines = const [],
  });
  Future<void> reverseJournal(String id, String reason);
  Future<void> createExpenseJournal({
    required double amount,
    required String category,
    required String description,
    String? riderId,
    String? fineId,
  });
  // Note: submitExpenseByPro removed — Post New Journal dialog deleted
}
