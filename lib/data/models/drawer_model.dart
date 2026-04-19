import 'package:equatable/equatable.dart';

enum DrawerType { cash, bank, wallet }

class DrawerModel extends Equatable {
  final String id;
  final String name;
  final DrawerType type;
  final double balance;
  final int colorCode; // 0xFF...
  final String currency;
  final bool isActive;

  const DrawerModel({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
    required this.colorCode,
    this.currency = 'AED',
    this.isActive = true,
  });

  DrawerModel copyWith({
    String? id,
    String? name,
    DrawerType? type,
    double? balance,
    int? colorCode,
    String? currency,
    bool? isActive,
  }) {
    return DrawerModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      balance: balance ?? this.balance,
      colorCode: colorCode ?? this.colorCode,
      currency: currency ?? this.currency,
      isActive: isActive ?? this.isActive,
    );
  }

  factory DrawerModel.fromJson(Map<String, dynamic> json) {
    return DrawerModel(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      type: DrawerType.values.firstWhere(
        (e) => e.name == (json['type'] ?? 'cash').toString().toLowerCase(),
        orElse: () => DrawerType.cash,
      ),
      balance: (json['balance'] as num?)?.toDouble() ?? 0.0,
      colorCode:
          int.tryParse(json['color_code']?.toString() ?? '') ?? 0xFF000000,
      currency: json['currency']?.toString() ?? 'AED',
      isActive: json['is_active'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'balance': balance,
      'color_code': colorCode.toString(),
      'currency': currency,
      'is_active': isActive,
    };
  }

  @override
  List<Object?> get props => [id, name, type, balance, colorCode, currency, isActive];
}

class DrawerTransactionModel extends Equatable {
  final String id;
  final String drawerId;
  final double amount;
  final bool isCredit; // true = Money In, false = Money Out
  final String description;
  final DateTime date;

  const DrawerTransactionModel({
    required this.id,
    required this.drawerId,
    required this.amount,
    required this.isCredit,
    required this.description,
    required this.date,
  });

  factory DrawerTransactionModel.fromJson(Map<String, dynamic> json) {
    return DrawerTransactionModel(
      id: json['id']?.toString() ?? '',
      drawerId: json['drawer_id']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      isCredit: json['is_credit'] ?? false,
      description: json['description'] ?? '',
      date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'drawer_id': drawerId,
      'amount': amount,
      'is_credit': isCredit,
      'description': description,
      'date': date.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
    id,
    drawerId,
    amount,
    isCredit,
    description,
    date,
  ];
}
