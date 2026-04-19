import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/audit_log_model.dart';
import 'audit_log_repository.dart';

class SupabaseAuditLogRepository implements AuditLogRepository {
  final SupabaseClient _client = Supabase.instance.client;

  @override
  Future<List<AuditLogModel>> fetchLogs({
    String? tableName,
    String? recordId,
    int limit = 100,
  }) async {
    try {
      var query = _client.from('audit_log').select();

      if (tableName != null && tableName.isNotEmpty) {
        query = query.eq('table_name', tableName);
      }
      if (recordId != null && recordId.isNotEmpty) {
        query = query.eq('record_id', recordId);
      }
      final response = await query.order('changed_at', ascending: false).limit(limit);
      
      return (response as List)
          .map((json) => AuditLogModel.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching audit logs: $e');
      rethrow;
    }
  }
}
