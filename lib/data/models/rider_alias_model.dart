import 'package:equatable/equatable.dart';

/// Maps to the `rider_aliases` table.
/// Tracks versioned Talabat / Keeta IDs per rider.
/// `validTo == null` means the alias is currently active.
class RiderAliasModel extends Equatable {
  final String id;
  final String riderId;
  final String platform; // 'talabat' or 'keeta'
  final String platformRiderId;
  final String? c3Id;
  final DateTime validFrom;
  final DateTime? validTo;
  final String status; // 'active' or 'inactive'
  final DateTime? createdAt;

  const RiderAliasModel({
    required this.id,
    required this.riderId,
    required this.platform,
    required this.platformRiderId,
    this.c3Id,
    required this.validFrom,
    this.validTo,
    this.status = 'active',
    this.createdAt,
  });

  /// Whether this alias is currently active.
  bool get isActive => status == 'active';

  factory RiderAliasModel.fromJson(Map<String, dynamic> json) {
    return RiderAliasModel(
      id: json['id']?.toString() ?? '',
      riderId: json['rider_id']?.toString() ?? '',
      platform: json['platform'] ?? '',
      platformRiderId: json['platform_rider_id'] ?? '',
      c3Id: json['c3_id']?.toString(),
      validFrom: DateTime.tryParse(json['valid_from']?.toString() ?? '') ??
          DateTime.now(),
      validTo: json['valid_to'] != null
          ? DateTime.tryParse(json['valid_to'].toString())
          : null,
      status: json['status']?.toString() ?? 'active',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'rider_id': riderId,
      'platform': platform,
      'platform_rider_id': platformRiderId,
      if (c3Id != null) 'c3_id': c3Id,
      'valid_from': validFrom.toIso8601String().split('T').first,
      if (validTo != null)
        'valid_to': validTo!.toIso8601String().split('T').first,
      'status': status,
    };
  }

  RiderAliasModel copyWith({
    String? id,
    String? riderId,
    String? platform,
    String? platformRiderId,
    String? c3Id,
    DateTime? validFrom,
    DateTime? validTo,
    String? status,
    DateTime? createdAt,
  }) {
    return RiderAliasModel(
      id: id ?? this.id,
      riderId: riderId ?? this.riderId,
      platform: platform ?? this.platform,
      platformRiderId: platformRiderId ?? this.platformRiderId,
      c3Id: c3Id ?? this.c3Id,
      validFrom: validFrom ?? this.validFrom,
      validTo: validTo ?? this.validTo,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    riderId,
    platform,
    platformRiderId,
    c3Id,
    validFrom,
    validTo,
    status,
    createdAt,
  ];
}
