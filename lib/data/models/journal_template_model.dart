import 'package:equatable/equatable.dart';

/// Maps to the `journal_templates` table in Supabase.
/// Pre-configured templates that speed up journal creation by
/// providing default accounts, drawer, category, VAT rate, etc.
class JournalTemplateModel extends Equatable {
  final String id;
  final String name;
  final String type; // journal_type enum: 'expense', 'salary', 'fine', 'loan', 'manual_adjustment'
  final String? defaultDrawerId;
  final String? categoryId;
  final List<Map<String, dynamic>> defaultAccounts; // JSONB array
  final double vatRate;
  final bool isReceivable;
  final bool isPayable;
  final String? description;
  final String? createdBy;
  final DateTime? createdAt;

  const JournalTemplateModel({
    required this.id,
    required this.name,
    this.type = 'expense',
    this.defaultDrawerId,
    this.categoryId,
    this.defaultAccounts = const [],
    this.vatRate = 0,
    this.isReceivable = false,
    this.isPayable = false,
    this.description,
    this.createdBy,
    this.createdAt,
  });

  factory JournalTemplateModel.fromJson(Map<String, dynamic> json) {
    return JournalTemplateModel(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      type: json['type']?.toString() ?? 'expense',
      defaultDrawerId: json['default_drawer_id']?.toString(),
      categoryId: json['category_id']?.toString(),
      defaultAccounts: (json['default_accounts'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      vatRate: (json['vat_rate'] as num?)?.toDouble() ?? 0,
      isReceivable: json['is_receivable'] == true,
      isPayable: json['is_payable'] == true,
      description: json['description']?.toString(),
      createdBy: json['created_by']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type,
      if (defaultDrawerId != null) 'default_drawer_id': defaultDrawerId,
      if (categoryId != null) 'category_id': categoryId,
      'default_accounts': defaultAccounts,
      'vat_rate': vatRate,
      'is_receivable': isReceivable,
      'is_payable': isPayable,
      if (description != null) 'description': description,
      if (createdBy != null) 'created_by': createdBy,
    };
  }

  JournalTemplateModel copyWith({
    String? id,
    String? name,
    String? type,
    String? defaultDrawerId,
    String? categoryId,
    List<Map<String, dynamic>>? defaultAccounts,
    double? vatRate,
    bool? isReceivable,
    bool? isPayable,
    String? description,
    String? createdBy,
    DateTime? createdAt,
  }) {
    return JournalTemplateModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      defaultDrawerId: defaultDrawerId ?? this.defaultDrawerId,
      categoryId: categoryId ?? this.categoryId,
      defaultAccounts: defaultAccounts ?? this.defaultAccounts,
      vatRate: vatRate ?? this.vatRate,
      isReceivable: isReceivable ?? this.isReceivable,
      isPayable: isPayable ?? this.isPayable,
      description: description ?? this.description,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    type,
    defaultDrawerId,
    categoryId,
    defaultAccounts,
    vatRate,
    isReceivable,
    isPayable,
    description,
    createdBy,
    createdAt,
  ];
}
