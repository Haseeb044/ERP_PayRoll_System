import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

enum RiderRequestStatus { pending, approved, rejected }

class RiderRequestModel extends Equatable {
  final String id;
  final String name;
  final String emiratesIdNumber;
  final String? phone;
  final String? passportNumber;
  final String? city;
  final String? riderCode;
  final String submittedBy;
  final RiderRequestStatus status;
  final DateTime createdAt;

  const RiderRequestModel({
    required this.id,
    required this.name,
    required this.emiratesIdNumber,
    this.phone,
    this.passportNumber,
    this.city,
    this.riderCode,
    required this.submittedBy,
    required this.status,
    required this.createdAt,
  });

  factory RiderRequestModel.fromJson(Map<String, dynamic> json) {
    return RiderRequestModel(
      id: json['id'],
      name: json['name'],
      emiratesIdNumber: json['emirates_id_number'],
      phone: json['phone'],
      passportNumber: json['passport_number'],
      city: json['city'],
      riderCode: json['rider_code'],
      submittedBy: json['submitted_by'],
      status: RiderRequestStatus.values.firstWhere(
        (e) => e.name == (json['status'] ?? 'pending'),
        orElse: () => RiderRequestStatus.pending,
      ),
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  String get statusDisplay {
    switch (status) {
      case RiderRequestStatus.pending:
        return 'Pending Review';
      case RiderRequestStatus.approved:
        return 'Approved';
      case RiderRequestStatus.rejected:
        return 'Rejected';
    }
  }

  Color get statusColor {
    switch (status) {
      case RiderRequestStatus.pending:
        return Colors.orange;
      case RiderRequestStatus.approved:
        return Colors.green;
      case RiderRequestStatus.rejected:
        return Colors.red;
    }
  }

  @override
  List<Object?> get props => [id, name, status, createdAt];
}
