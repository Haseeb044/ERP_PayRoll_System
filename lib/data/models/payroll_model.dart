import 'package:equatable/equatable.dart';
import 'payslip_item_model.dart';

enum PayrollBatchStatus { draft, finalized, posted, error }

class PayrollBatchModel extends Equatable {
  final String id;
  final DateTime month;
  final String platform; // Talabat, Keeta
  final PayrollBatchStatus status;
  final double totalAmount;

  const PayrollBatchModel({
    required this.id,
    required this.month,
    required this.platform,
    required this.status,
    required this.totalAmount,
  });

  @override
  List<Object?> get props => [id, month, platform, status, totalAmount];

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'month': month.toIso8601String(),
      'platform': platform,
      'status': status.toString().split('.').last,
      'total_amount': totalAmount,
    };
  }

  factory PayrollBatchModel.fromJson(Map<String, dynamic> json) {
    String monthStr = json['month']?.toString() ?? '';
    // Handle YYYY-MM format from Supabase
    if (monthStr.length == 7 && monthStr.contains('-')) {
      monthStr = '$monthStr-01';
    }

    return PayrollBatchModel(
      id: json['id']?.toString() ?? '',
      month: monthStr.isNotEmpty ? DateTime.parse(monthStr) : DateTime.now(),
      platform: json['platform'] ?? '',
      status: PayrollBatchStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => PayrollBatchStatus.draft,
      ),
      totalAmount: (json['total_amount'] as num? ?? 0.0).toDouble(),
    );
  }

  PayrollBatchModel copyWith({
    String? id,
    DateTime? month,
    String? platform,
    PayrollBatchStatus? status,
    double? totalAmount,
  }) {
    return PayrollBatchModel(
      id: id ?? this.id,
      month: month ?? this.month,
      platform: platform ?? this.platform,
      status: status ?? this.status,
      totalAmount: totalAmount ?? this.totalAmount,
    );
  }
}

enum PayslipDraftStatus { matched, error, finalized }

class PayslipDraftModel extends Equatable {
  final String id;
  final String? riderId;
  final String? batchId;
  final String? riderAliasId;
  final String riderName;
  final String externalId;
  final double grossSalary;
  final double netSalary;
  final double totalExpenses;
  final double totalFines;
  final double internalFines;
  final double internalExpenses;
  final double platformDeductions;
  final double otherDeductions;
  final double arrears;
  final double tdsBonus;
  final double foodCompensation;
  final double tips;
  final double codDeficit;
  final double clawbackDeduction;
  final double prevBalance;
  final String? wpsBatch;
  final List<PayslipItemModel> items; // Dynamic items
  final PayslipDraftStatus status;
  final String? errorReason;
  final String? platform; // Added for PDF labeling
  final bool reviewRequired;
  final List<String> issueCodes;

  final double onlineHours;
  final int orderCount;

  const PayslipDraftModel({
    required this.id,
    this.riderId,
    this.batchId,
    this.riderAliasId,
    required this.riderName,
    required this.externalId,
    required this.grossSalary,
    required this.netSalary,
    this.totalExpenses = 0,
    this.totalFines = 0,
    this.internalFines = 0,
    this.internalExpenses = 0,
    this.platformDeductions = 0,
    this.otherDeductions = 0,
    this.arrears = 0,
    this.tdsBonus = 0,
    this.foodCompensation = 0,
    this.tips = 0,
    this.codDeficit = 0,
    this.clawbackDeduction = 0,
    this.prevBalance = 0,
    this.wpsBatch,
    required this.items,
    required this.status,
    this.errorReason,
    this.onlineHours = 0.0,
    this.orderCount = 0,
    this.platform,
    this.reviewRequired = false,
    this.issueCodes = const [],
  });

  @override
  List<Object?> get props => [
    id,
    riderId,
    batchId,
    riderAliasId,
    riderName,
    externalId,
    grossSalary,
    netSalary,
    totalExpenses,
    totalFines,
    internalFines,
    internalExpenses,
    platformDeductions,
    otherDeductions,
    arrears,
    tdsBonus,
    foodCompensation,
    tips,
    codDeficit,
    clawbackDeduction,
    prevBalance,
    wpsBatch,
    items,
    status,
    errorReason,
    onlineHours,
    orderCount,
    platform,
    reviewRequired,
    issueCodes,
  ];

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      if (riderId != null) 'rider_id': riderId,
      if (batchId != null) 'batch_id': batchId,
      if (riderAliasId != null) 'rider_alias_id': riderAliasId,
      'rider_name': riderName,
      'external_id': externalId,
      'gross_salary': grossSalary,
      'net_salary': netSalary,
      'total_expenses': totalExpenses,
      'total_fines': totalFines,
      'platform_deductions': platformDeductions,
      'other_deductions': otherDeductions,
      'arrears': arrears,
      'tds_bonus': tdsBonus,
      'food_compensation': foodCompensation,
      'tips': tips,
      'cod_deficit': codDeficit,
      'clawback_deduction': clawbackDeduction,
      'prev_balance': prevBalance,
      if (wpsBatch != null) 'wps_batch': wpsBatch,
      'items': items.map((e) => e.toJson()).toList(),
      'status': status.toString().split('.').last,
      'error_reason': errorReason,
      'online_hours': onlineHours,
      'order_count': orderCount,
      'platform': platform,
      'review_required': reviewRequired,
      'issue_codes': issueCodes,
    };
  }

  factory PayslipDraftModel.fromJson(Map<String, dynamic> json) {
    return PayslipDraftModel(
      id: json['id']?.toString() ?? '',
      riderId: json['rider_id']?.toString(),
      batchId: json['batch_id']?.toString(),
      riderAliasId: json['rider_alias_id']?.toString(),
      riderName: json['rider_name'] ?? '',
      externalId: json['external_id'] ?? '',
      grossSalary: (json['gross_salary'] as num? ?? 0.0).toDouble(),
      netSalary: (json['net_salary'] as num? ?? 0.0).toDouble(),
      totalExpenses: (json['total_expenses'] as num? ?? 0.0).toDouble(),
      totalFines: (json['total_fines'] as num? ?? 0.0).toDouble(),
      internalFines: (json['internal_fines'] as num? ?? 0.0).toDouble(),
      internalExpenses: (json['internal_expenses'] as num? ?? 0.0).toDouble(),
      platformDeductions: (json['platform_deductions'] as num? ?? 0.0)
          .toDouble(),
      otherDeductions: (json['other_deductions'] as num? ?? 0.0).toDouble(),
      arrears: (json['arrears'] as num? ?? 0.0).toDouble(),
      tdsBonus: (json['tds_bonus'] as num? ?? 0.0).toDouble(),
      foodCompensation: (json['food_compensation'] as num? ?? 0.0).toDouble(),
      tips: (json['tips'] as num? ?? 0.0).toDouble(),
      codDeficit: (json['cod_deficit'] as num? ?? 0.0).toDouble(),
      clawbackDeduction: (json['clawback_deduction'] as num? ?? 0.0).toDouble(),
      prevBalance: (json['prev_balance'] as num? ?? 0.0).toDouble(),
      wpsBatch: json['wps_batch']?.toString(),
      items:
          (json['items'] as List<dynamic>?)
              ?.map((e) => PayslipItemModel.fromJson(e))
              .toList() ??
          [],
      status: PayslipDraftStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => PayslipDraftStatus.error,
      ),
      errorReason: json['error_reason'],
      onlineHours: (json['online_hours'] as num? ?? 0.0).toDouble(),
      orderCount: json['order_count'] ?? 0,
      platform: json['platform']?.toString(),
      reviewRequired: json['review_required'] == true,
      issueCodes:
          (json['issue_codes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  PayslipDraftModel copyWith({
    String? id,
    String? riderId,
    String? batchId,
    String? riderAliasId,
    String? riderName,
    String? externalId,
    double? grossSalary,
    double? netSalary,
    double? totalExpenses,
    double? totalFines,
    double? internalFines,
    double? internalExpenses,
    double? platformDeductions,
    double? otherDeductions,
    double? arrears,
    double? tdsBonus,
    double? foodCompensation,
    double? tips,
    double? codDeficit,
    double? clawbackDeduction,
    double? prevBalance,
    String? wpsBatch,
    List<PayslipItemModel>? items,
    PayslipDraftStatus? status,
    String? errorReason,
    double? onlineHours,
    int? orderCount,
    String? platform,
    bool? reviewRequired,
    List<String>? issueCodes,
  }) {
    return PayslipDraftModel(
      id: id ?? this.id,
      riderId: riderId ?? this.riderId,
      batchId: batchId ?? this.batchId,
      riderAliasId: riderAliasId ?? this.riderAliasId,
      riderName: riderName ?? this.riderName,
      externalId: externalId ?? this.externalId,
      grossSalary: grossSalary ?? this.grossSalary,
      netSalary: netSalary ?? this.netSalary,
      totalExpenses: totalExpenses ?? this.totalExpenses,
      totalFines: totalFines ?? this.totalFines,
      internalFines: internalFines ?? this.internalFines,
      internalExpenses: internalExpenses ?? this.internalExpenses,
      platformDeductions: platformDeductions ?? this.platformDeductions,
      otherDeductions: otherDeductions ?? this.otherDeductions,
      arrears: arrears ?? this.arrears,
      tdsBonus: tdsBonus ?? this.tdsBonus,
      foodCompensation: foodCompensation ?? this.foodCompensation,
      tips: tips ?? this.tips,
      codDeficit: codDeficit ?? this.codDeficit,
      clawbackDeduction: clawbackDeduction ?? this.clawbackDeduction,
      prevBalance: prevBalance ?? this.prevBalance,
      wpsBatch: wpsBatch ?? this.wpsBatch,
      items: items ?? this.items,
      status: status ?? this.status,
      errorReason: errorReason ?? this.errorReason,
      onlineHours: onlineHours ?? this.onlineHours,
      orderCount: orderCount ?? this.orderCount,
      platform: platform ?? this.platform,
      reviewRequired: reviewRequired ?? this.reviewRequired,
      issueCodes: issueCodes ?? this.issueCodes,
    );
  }
}
