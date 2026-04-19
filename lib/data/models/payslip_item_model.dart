import 'package:equatable/equatable.dart';

enum PayslipItemType { earning, deduction, fine, loan, platformDeduction }

class PayslipItemModel extends Equatable {
  final String label;
  final double amount; // Positive for earning, negative for deduction
  final PayslipItemType type;

  const PayslipItemModel({
    required this.label,
    required this.amount,
    required this.type,
  });

  Map<String, dynamic> toJson() {
    final serializedType = switch (type) {
      PayslipItemType.platformDeduction => 'platform_deduction',
      _ => type.toString().split('.').last,
    };

    return {
      'label': label,
      'amount': amount,
      'type': serializedType,
    };
  }

  factory PayslipItemModel.fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] ?? '').toString().trim().toLowerCase();
    final normalizedType = switch (rawType) {
      'platform_deduction' => 'platformDeduction',
      'platformdeduction' => 'platformDeduction',
      'platform deduction' => 'platformDeduction',
      'expense' => 'deduction',
      'internal_expense' => 'deduction',
      'internal expense' => 'deduction',
      'loan' => 'loan',
      'advance' => 'loan',
      'loan_deduction' => 'loan',
      'traffic_fine' => 'fine',
      'traffic fine' => 'fine',
      _ => rawType,
    };

    return PayslipItemModel(
      label: json['label'] ?? '',
      amount: (json['amount'] as num).toDouble(),
      type: PayslipItemType.values.firstWhere(
        (e) => e.toString().split('.').last == normalizedType,
        orElse: () => PayslipItemType.earning,
      ),
    );
  }

  PayslipItemModel copyWith({
    String? label,
    double? amount,
    PayslipItemType? type,
  }) {
    return PayslipItemModel(
      label: label ?? this.label,
      amount: amount ?? this.amount,
      type: type ?? this.type,
    );
  }

  @override
  List<Object?> get props => [label, amount, type];
}
