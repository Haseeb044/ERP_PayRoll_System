import '../models/ledger_entry_model.dart';

abstract class LedgerRepository {
  Future<List<LedgerEntryModel>> fetchEntries({
    String? account,
    String? fromDate,
    String? toDate,
  });
  
  Future<List<Map<String, dynamic>>> fetchSummary();
  
  Future<List<Map<String, String>>> fetchAccounts();
  Future<List<LedgerEntryModel>> fetchRiderStatement(String riderId);
  Future<Map<String, dynamic>> fetchRiderStatementSummary(String riderId);
}
