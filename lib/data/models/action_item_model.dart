import 'package:equatable/equatable.dart';

enum ActionType { 
  fine_unmatched, 
  alias_mismatch, 
  journal_pending_approval, 
  rider_pending_approval, 
  insufficient_funds, 
  bike_overlap, 
  duplicate_payslip, 
  other 
}

enum ActionSeverity { blocker, warning, info }

class ActionItemModel extends Equatable {
  final String id;
  final ActionType type;
  final String title;
  final String subtitle;
  final ActionSeverity severity;
  final String route;
  final String? argumentId;
  final String? relatedEntity;
  final String? referenceId;
  final String? responsibleRole;
  final String? resolvedBy;
  final String? resolutionNotes;
  final DateTime? resolvedAt;
  final DateTime? createdAt;

  const ActionItemModel({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.severity,
    required this.route,
    this.argumentId,
    this.relatedEntity,
    this.referenceId,
    this.responsibleRole,
    this.resolvedBy,
    this.resolutionNotes,
    this.resolvedAt,
    this.createdAt,
  });

  factory ActionItemModel.fromJson(Map<String, dynamic> json) {
    return ActionItemModel(
      id: json['id']?.toString() ?? '',
      type: ActionType.values.firstWhere(
        (e) => e.name == (json['type'] ?? 'other').toString().toLowerCase(),
        orElse: () => ActionType.other,
      ),
      title: json['title'] ?? '',
      subtitle: json['subtitle'] ?? '',
      severity: ActionSeverity.values.firstWhere(
        (e) => e.name == (json['severity'] ?? 'info').toString().toLowerCase(),
        orElse: () => ActionSeverity.info,
      ),
      route: json['route'] ?? '',
      argumentId: json['argument_id']?.toString(),
      relatedEntity: json['related_entity']?.toString(),
      referenceId: json['reference_id']?.toString(),
      responsibleRole: json['responsible_role']?.toString(),
      resolvedBy: json['resolved_by']?.toString(),
      resolutionNotes: json['resolution_notes']?.toString(),
      resolvedAt: json['resolved_at'] != null
          ? DateTime.tryParse(json['resolved_at'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'title': title,
      'subtitle': subtitle,
      'severity': severity.name,
      'route': route,
      if (argumentId != null) 'argument_id': argumentId,
      if (relatedEntity != null) 'related_entity': relatedEntity,
      if (referenceId != null) 'reference_id': referenceId,
      if (responsibleRole != null) 'responsible_role': responsibleRole,
      if (resolvedBy != null) 'resolved_by': resolvedBy,
      if (resolutionNotes != null) 'resolution_notes': resolutionNotes,
      if (resolvedAt != null) 'resolved_at': resolvedAt!.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
    id,
    type,
    title,
    subtitle,
    severity,
    route,
    argumentId,
    relatedEntity,
    referenceId,
    responsibleRole,
    resolvedBy,
    resolutionNotes,
    resolvedAt,
    createdAt,
  ];
}
