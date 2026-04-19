import 'package:equatable/equatable.dart';

enum BikeStatus { active, maintenance, retired }

class BikeModel extends Equatable {
  final String chassisNumber;  // New Primary Key
  final String plateNumber;    // Human-readable plate
  final String model;
  final BikeStatus status;
  final String? salikId;
  final DateTime? createdAt;

  const BikeModel({
    required this.chassisNumber,
    required this.plateNumber,
    required this.model,
    required this.status,
    this.salikId,
    this.createdAt,
  });

  factory BikeModel.fromJson(Map<String, dynamic> json) {
    return BikeModel(
      chassisNumber: json['chassis_number'] ?? json['bike_id'] ?? '',
      plateNumber: json['bike_id'] ?? '',
      model: json['model'] ?? 'Unknown',
      status: BikeStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => BikeStatus.active,
      ),
      salikId: json['salik_id']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  @override
  List<Object?> get props => [
    chassisNumber,
    plateNumber,
    model,
    status,
    salikId,
    createdAt,
  ];
}

class BikeAssignmentModel extends Equatable {
  final String id;
  final String chassisNumber; // FK to bikes.chassis_number
  final String? plateNumber;  // For display
  final String riderId;
  final String? riderName;
  final DateTime assignedAt;
  final DateTime? returnedAt;

  const BikeAssignmentModel({
    required this.id,
    required this.chassisNumber,
    this.plateNumber,
    required this.riderId,
    this.riderName,
    required this.assignedAt,
    this.returnedAt,
  });

  factory BikeAssignmentModel.fromJson(Map<String, dynamic> json) {
    try {
      return BikeAssignmentModel(
        id: json['id'] ?? '',
        chassisNumber: json['chassis_number'] ?? json['bike_id'] ?? '', // Database column was renamed to chassis_number
        plateNumber: json['bikes']?['bike_id'], // Resolved via join
        riderId: json['rider_id']?.toString() ?? '',
        riderName: json['rider_name'],
        assignedAt:
            DateTime.tryParse(json['assigned_at'] ?? '') ?? DateTime.now(),
        returnedAt: json['returned_at'] != null
            ? DateTime.parse(json['returned_at'])
            : null,
      );
    } catch (e) {
      print("ERROR parsing BikeAssignmentModel: $e");
      rethrow;
    }
  }

  @override
  List<Object?> get props => [
    id,
    chassisNumber,
    plateNumber,
    riderId,
    riderName,
    assignedAt,
    returnedAt,
  ];
}

enum FineType { speeding, parking, laneViolation, redLight, other }

enum FineStatus { matched, unmatched, assigned, partial_match, partially_recovered, fully_recovered }

class FineModel extends Equatable {
  final String id;
  final String ticketNumber;
  final String plateNumber;
  final DateTime violationDate;
  final double amount;
  final double remainingBalance;
  final double plusAmount;
  final FineType type;
  final String? finesSource;
  final String? riderId;
  final String? riderName;
  final FineStatus status;
  final String? imageUrl;
  final String? description;
  final String? city;
  final String? journalId;
  final String? ticketTime;
  final DateTime? createdAt;
  final DateTime? paidToGovtDate;
  final String? paidToGovtDrawer;
  final String? paidToGovtJournalId;

  const FineModel({
    required this.id,
    required this.ticketNumber,
    required this.plateNumber,
    required this.violationDate,
    required this.amount,
    this.remainingBalance = 0.0,
    this.plusAmount = 0.0,
    required this.type,
    this.finesSource = 'System',
    this.riderId,
    this.riderName,
    required this.status,
    this.imageUrl,
    this.description,
    this.city,
    this.journalId,
    this.ticketTime,
    this.createdAt,
    this.paidToGovtDate,
    this.paidToGovtDrawer,
    this.paidToGovtJournalId,
  });

  String get violationTime =>
      ticketTime ??
      "${violationDate.hour.toString().padLeft(2, '0')}:${violationDate.minute.toString().padLeft(2, '0')}";

  FineModel copyWith({
    String? id,
    String? ticketNumber,
    String? plateNumber,
    DateTime? violationDate,
    double? amount,
    double? remainingBalance,
    double? plusAmount,
    FineType? type,
    String? finesSource,
    String? riderId,
    String? riderName,
    FineStatus? status,
    String? imageUrl,
    String? description,
    String? city,
    String? journalId,
    String? ticketTime,
    DateTime? createdAt,
    DateTime? paidToGovtDate,
    String? paidToGovtDrawer,
    String? paidToGovtJournalId,
  }) {
    return FineModel(
      id: id ?? this.id,
      ticketNumber: ticketNumber ?? this.ticketNumber,
      plateNumber: plateNumber ?? this.plateNumber,
      violationDate: violationDate ?? this.violationDate,
      amount: amount ?? this.amount,
      remainingBalance: remainingBalance ?? this.remainingBalance,
      plusAmount: plusAmount ?? this.plusAmount,
      type: type ?? this.type,
      finesSource: finesSource ?? this.finesSource,
      riderId: riderId ?? this.riderId,
      riderName: riderName ?? this.riderName,
      status: status ?? this.status,
      imageUrl: imageUrl ?? this.imageUrl,
      description: description ?? this.description,
      city: city ?? this.city,
      journalId: journalId ?? this.journalId,
      ticketTime: ticketTime ?? this.ticketTime,
      createdAt: createdAt ?? this.createdAt,
      paidToGovtDate: paidToGovtDate ?? this.paidToGovtDate,
      paidToGovtDrawer: paidToGovtDrawer ?? this.paidToGovtDrawer,
      paidToGovtJournalId: paidToGovtJournalId ?? this.paidToGovtJournalId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'ticket_number': ticketNumber,
      'plate_number': plateNumber,
      'violation_date': violationDate.toIso8601String(),
      'amount': amount,
      // Only include optional DB-backed keys when they carry a meaningful value.
      if (remainingBalance != 0.0) 'remaining_balance': remainingBalance,
      if (plusAmount != 0.0) 'plus_amount': plusAmount,
      'type': type.toString().split('.').last,
      'fines_source': finesSource ?? 'System',
      'rider_id': riderId,
      'rider_name': riderName,
      'status': status.toString().split('.').last,
      'image_url': imageUrl,
      'description': description,
      'city': city,
      if (journalId != null) 'journal_id': journalId,
      if (ticketTime != null) 'ticket_time': ticketTime,
      if (paidToGovtDate != null) 'paid_to_govt_date': paidToGovtDate!.toIso8601String(),
      if (paidToGovtDrawer != null) 'paid_to_govt_drawer': paidToGovtDrawer,
      if (paidToGovtJournalId != null) 'paid_to_govt_journal_id': paidToGovtJournalId,
    };
  }

  factory FineModel.fromJson(Map<String, dynamic> json) {
    final rawStatus = (json['status'] ?? '').toString().toLowerCase();
    FineStatus status;
    if (rawStatus == 'matched') {
      status = FineStatus.matched;
    } else if (rawStatus == 'assigned') {
      status = FineStatus.assigned;
    } else if (rawStatus == 'partial_match') {
      status = FineStatus.partial_match;
    } else if (rawStatus == 'partially_recovered') {
      status = FineStatus.partially_recovered;
    } else if (rawStatus == 'fully_recovered' || rawStatus == 'paid') {
      status = FineStatus.fully_recovered;
    } else {
      status = FineStatus.unmatched;
    }

    return FineModel(
      id: json['id']?.toString() ?? '',
      ticketNumber: json['ticket_number'] ?? '',
      plateNumber: json['plate_number'] ?? '',
      violationDate:
          DateTime.tryParse(json['violation_date'] ?? '') ?? DateTime.now(),
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      remainingBalance: (json['remaining_balance'] as num?)?.toDouble() ??
          (json['amount'] as num?)?.toDouble() ??
          0.0,
      plusAmount: (json['plus_amount'] as num?)?.toDouble() ?? 0.0,
      type: FineType.values.firstWhere(
        (e) => e.toString().split('.').last == json['type'],
        orElse: () => FineType.other,
      ),
      finesSource: json['fines_source'],
      riderId: json['rider_id'],
      riderName: json['rider_name'],
      status: status,
      imageUrl: json['image_url'],
      description: json['description'],
      city: json['city'],
      journalId: json['journal_id']?.toString(),
      ticketTime: json['ticket_time']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      paidToGovtDate: json['paid_to_govt_date'] != null
          ? DateTime.tryParse(json['paid_to_govt_date'].toString())
          : null,
      paidToGovtDrawer: json['paid_to_govt_drawer']?.toString(),
      paidToGovtJournalId: json['paid_to_govt_journal_id']?.toString(),
    );
  }

  @override
  List<Object?> get props => [
    id,
    ticketNumber,
    plateNumber,
    violationDate,
    amount,
    plusAmount,
    type,
    finesSource,
    riderId,
    riderName,
    status,
    imageUrl,
    description,
    city,
    journalId,
    ticketTime,
    createdAt,
    paidToGovtDate,
    paidToGovtDrawer,
    paidToGovtJournalId,
  ];
}
