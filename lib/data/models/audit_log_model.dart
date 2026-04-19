import 'package:equatable/equatable.dart';

/// Maps to the `audit_log` table.
/// Immutable change log auto-populated by the `fn_audit_log` trigger
/// on INSERT / UPDATE / DELETE for critical tables.
class AuditLogModel extends Equatable {
  final String id;
  final String tableName;
  final String recordId;
  final String action; // 'INSERT', 'UPDATE', 'DELETE'
  final Map<String, dynamic>? oldData;
  final Map<String, dynamic>? newData;
  final String? changedByUserId;
  final DateTime changedAt;

  const AuditLogModel({
    required this.id,
    required this.tableName,
    required this.recordId,
    required this.action,
    this.oldData,
    this.newData,
    this.changedByUserId,
    required this.changedAt,
  });

  /// Returns a human-readable summary of what changed.
  String get summary {
    switch (action) {
      case 'INSERT':
        return 'Created $tableName record';
      case 'UPDATE':
        return 'Updated $tableName record';
      case 'DELETE':
        return 'Deleted $tableName record';
      default:
        return '$action on $tableName';
    }
  }

  factory AuditLogModel.fromJson(Map<String, dynamic> json) {
    return AuditLogModel(
      id: json['id']?.toString() ?? '',
      tableName: json['table_name'] ?? '',
      recordId: json['record_id']?.toString() ?? '',
      action: json['action'] ?? '',
      oldData: json['old_data'] is Map<String, dynamic>
          ? json['old_data'] as Map<String, dynamic>
          : null,
      newData: json['new_data'] is Map<String, dynamic>
          ? json['new_data'] as Map<String, dynamic>
          : null,
      changedByUserId: json['changed_by_user_id']?.toString(),
      changedAt: DateTime.tryParse(json['changed_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
    id,
    tableName,
    recordId,
    action,
    oldData,
    newData,
    changedByUserId,
    changedAt,
  ];
}
