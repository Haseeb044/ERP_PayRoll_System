import 'package:equatable/equatable.dart';

/// Maps to the `transactions` table in Supabase.
/// Every cash movement from a drawer to a rider is recorded here.
/// `amount` must be > 0 (DB constraint).
/// `status` is one of: 'pending', 'approved', 'rejected'.
class TransactionModel extends Equatable {
  final String id;
  final String drawerId; // FK → drawer.id
  final String riderId;  // FK → riders.id
  final double amount;   // Must be positive
  final String status;   // 'pending', 'approved', 'rejected'
  final String reason;
  final String? journalId;
  final DateTime? createdAt;

  // Joined fields (optional — populated when querying with rider/drawer join)
  final String? riderName;
  final String? drawerName;

  const TransactionModel({
    required this.id,
    required this.drawerId,
    required this.riderId,
    required this.amount,
    required this.status,
    required this.reason,
    this.journalId,
    this.createdAt,
    this.riderName,
    this.drawerName,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['id']?.toString() ?? '',
      drawerId: json['drawer_id']?.toString() ?? '',
      riderId: json['rider_id']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] ?? 'pending',
      reason: json['reason'] ?? '',
      journalId: json['journal_id']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      riderName: json['rider_name']?.toString(),
      drawerName: json['drawer_name']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'drawer_id': drawerId,
      'rider_id': riderId,
      'amount': amount,
      'status': status,
      'reason': reason,
      if (journalId != null) 'journal_id': journalId,
    };
  }

  TransactionModel copyWith({
    String? id,
    String? drawerId,
    String? riderId,
    double? amount,
    String? status,
    String? reason,
    String? journalId,
    DateTime? createdAt,
    String? riderName,
    String? drawerName,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      drawerId: drawerId ?? this.drawerId,
      riderId: riderId ?? this.riderId,
      amount: amount ?? this.amount,
      status: status ?? this.status,
      reason: reason ?? this.reason,
      journalId: journalId ?? this.journalId,
      createdAt: createdAt ?? this.createdAt,
      riderName: riderName ?? this.riderName,
      drawerName: drawerName ?? this.drawerName,
    );
  }

  @override
  List<Object?> get props => [
    id,
    drawerId,
    riderId,
    amount,
    status,
    reason,
    journalId,
    createdAt,
    riderName,
    drawerName,
  ];
}
