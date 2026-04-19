import 'package:equatable/equatable.dart';

enum RiderStatus { active, vacation, retired }

class RiderModel extends Equatable {
  final String id; // UUID
  final String? riderCode; // Unique 8-char code
  final String name;
  final String? emiratesIdNumber; // The actual ID number
  final String? phone;
  final RiderStatus status;
  final String? passportNumber;
  final String? city;
  final String? wpsStatus;
  final String? releaseHold;
  final String? passportExpiryDate;
  final String? emiratesIdExpiryDate;
  final String? visaExpiryDate;
  final String? holdReason;
  final String? holdUntil;
  final String? holdSetBy;
  final DateTime? holdSetAt;
  final String? createdByUserId;
  final DateTime? createdAt;
  final String? talabatId;
  final String? keetaId;

  const RiderModel({
    required this.id,
    this.riderCode,
    required this.name,
    this.emiratesIdNumber,
    this.phone,
    required this.status,
    this.passportNumber,
    this.city,
    this.wpsStatus = 'WPS',
    this.releaseHold = 'release',
    this.passportExpiryDate,
    this.emiratesIdExpiryDate,
    this.visaExpiryDate,
    this.holdReason,
    this.holdUntil,
    this.holdSetBy,
    this.holdSetAt,
    this.createdByUserId,
    this.createdAt,
    this.talabatId,
    this.keetaId,
  });

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      if (riderCode != null && riderCode!.isNotEmpty) 'rider_code': riderCode,
      'name': name,
      'emirates_id_number': emiratesIdNumber,
      'phone': phone,
      'status': status.toString().split('.').last,
      'passport_number': passportNumber,
      'city': city,
      'wps_status': wpsStatus,
      'release_hold': releaseHold,
      'passport_expiry_date': passportExpiryDate,
      'emirates_id_expiry_date': emiratesIdExpiryDate,
      'visa_expiry_date': visaExpiryDate,
      'hold_reason': holdReason,
      'hold_until': holdUntil,
      'hold_set_by': holdSetBy,
      if (holdSetAt != null) 'hold_set_at': holdSetAt?.toIso8601String(),
      if (createdByUserId != null) 'created_by_user_id': createdByUserId,
      if (createdAt != null) 'created_at': createdAt?.toIso8601String(),
      if (talabatId != null) 'talabat_id': talabatId,
      if (keetaId != null) 'keeta_id': keetaId,
    };
  }

  factory RiderModel.fromJson(Map<String, dynamic> json) {
    return RiderModel(
      id: json['id'] ?? '',
      riderCode: json['rider_code'],
      name: json['name'] ?? '',
      emiratesIdNumber: json['emirates_id_number'],
      phone: json['phone'],
      status: RiderStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => RiderStatus.active,
      ),
      passportNumber: json['passport_number'],
      city: json['city'],
      wpsStatus: json['wps_status'],
      releaseHold: json['release_hold'],
      passportExpiryDate: json['passport_expiry_date'],
      emiratesIdExpiryDate: json['emirates_id_expiry_date'],
      visaExpiryDate: json['visa_expiry_date'],
      holdReason: json['hold_reason'],
      holdUntil: json['hold_until'],
      holdSetBy: json['hold_set_by'],
      holdSetAt: json['hold_set_at'] != null ? DateTime.parse(json['hold_set_at']) : null,
      createdByUserId: json['created_by_user_id'],
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
      talabatId: json['talabat_id']?.toString(),
      keetaId: json['keeta_id']?.toString(),
    );
  }

  RiderModel copyWith({
    String? id,
    String? riderCode,
    String? name,
    String? emiratesIdNumber,
    String? phone,
    RiderStatus? status,
    String? passportNumber,
    String? city,
    String? wpsStatus,
    String? releaseHold,
    String? passportExpiryDate,
    String? emiratesIdExpiryDate,
    String? visaExpiryDate,
    String? holdReason,
    String? holdUntil,
    String? holdSetBy,
    DateTime? holdSetAt,
    String? createdByUserId,
    DateTime? createdAt,
    String? talabatId,
    String? keetaId,
  }) {
    return RiderModel(
      id: id ?? this.id,
      riderCode: riderCode ?? this.riderCode,
      name: name ?? this.name,
      emiratesIdNumber: emiratesIdNumber ?? this.emiratesIdNumber,
      phone: phone ?? this.phone,
      status: status ?? this.status,
      passportNumber: passportNumber ?? this.passportNumber,
      city: city ?? this.city,
      wpsStatus: wpsStatus ?? this.wpsStatus,
      releaseHold: releaseHold ?? this.releaseHold,
      passportExpiryDate: passportExpiryDate ?? this.passportExpiryDate,
      emiratesIdExpiryDate: emiratesIdExpiryDate ?? this.emiratesIdExpiryDate,
      visaExpiryDate: visaExpiryDate ?? this.visaExpiryDate,
      holdReason: holdReason ?? this.holdReason,
      holdUntil: holdUntil ?? this.holdUntil,
      holdSetBy: holdSetBy ?? this.holdSetBy,
      holdSetAt: holdSetAt ?? this.holdSetAt,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      createdAt: createdAt ?? this.createdAt,
      talabatId: talabatId ?? this.talabatId,
      keetaId: keetaId ?? this.keetaId,
    );
  }

  @override
  List<Object?> get props => [
    id,
    riderCode,
    name,
    emiratesIdNumber,
    phone,
    status,
    passportNumber,
    city,
    wpsStatus,
    releaseHold,
    passportExpiryDate,
    emiratesIdExpiryDate,
    visaExpiryDate,
    holdReason,
    holdUntil,
    holdSetBy,
    holdSetAt,
    createdByUserId,
    createdAt,
    talabatId,
    keetaId,
  ];
}
