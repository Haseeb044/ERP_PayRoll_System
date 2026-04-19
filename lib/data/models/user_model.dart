import 'package:equatable/equatable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Only two roles: PRO and Accountant.
enum UserRole { accountant, pro }

/// Maps to the `profiles` table in Supabase.
/// Mirrors Supabase auth.users data plus a `role` field.
class UserModel extends Equatable {
  final String id;
  final String email;
  final UserRole role;
  final DateTime? createdAt;

  const UserModel({
    required this.id,
    required this.email,
    required this.role,
    this.createdAt,
  });

  /// Construct from a `profiles` table row (Supabase query result).
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String,
      role: UserRole.values.firstWhere(
        (e) =>
            e.name.toLowerCase() ==
            (json['role'] ?? '').toString().toLowerCase(),
        orElse: () => UserRole.pro,
      ),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  /// Construct from a Supabase [User] auth object + a role string.
  factory UserModel.fromAuthUser(User authUser, String role) {
    return UserModel(
      id: authUser.id,
      email: authUser.email ?? '',
      role: UserRole.values.firstWhere(
        (e) => e.name.toLowerCase() == role.toLowerCase(),
        orElse: () => UserRole.pro,
      ),
      createdAt: DateTime.tryParse(authUser.createdAt),
    );
  }

  /// Serialize to JSON for upserting into the `profiles` table.
  /// Role is stored as lowercase ('pro', 'accountant') to match
  /// the DB enum.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'role': role.name,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? id,
    String? email,
    UserRole? role,
    DateTime? createdAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [id, email, role, createdAt];
}
