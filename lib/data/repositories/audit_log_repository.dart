import '../models/audit_log_model.dart';

abstract class AuditLogRepository {
  Future<List<AuditLogModel>> fetchLogs({
    String? tableName,
    String? recordId,
    int limit = 100,
  });
}
