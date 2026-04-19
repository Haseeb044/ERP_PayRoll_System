import 'package:equatable/equatable.dart';

/// Maps to the `expense_categories` table in Supabase.
/// Lookup table for categorising expenses and linking them
/// to a default journal type.
class ExpenseCategoryModel extends Equatable {
  final String id;
  final String name;
  final String? description;
  final String defaultType; // journal_type enum: 'expense', 'salary', etc.
  final bool isActive;
  final DateTime? createdAt;

  const ExpenseCategoryModel({
    required this.id,
    required this.name,
    this.description,
    this.defaultType = 'expense',
    this.isActive = true,
    this.createdAt,
  });

  factory ExpenseCategoryModel.fromJson(Map<String, dynamic> json) {
    return ExpenseCategoryModel(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      description: json['description']?.toString(),
      defaultType: json['default_type']?.toString() ?? 'expense',
      isActive: json['is_active'] != false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (description != null) 'description': description,
      'default_type': defaultType,
      'is_active': isActive,
    };
  }

  ExpenseCategoryModel copyWith({
    String? id,
    String? name,
    String? description,
    String? defaultType,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return ExpenseCategoryModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      defaultType: defaultType ?? this.defaultType,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [id, name, description, defaultType, isActive, createdAt];
}
