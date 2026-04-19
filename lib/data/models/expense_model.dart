class ExpenseStatusValues {
  static const String pending = 'pending';
  static const String approved = 'approved';
  static const String rejected = 'rejected';
  static const List<String> all = [pending, approved, rejected];
}

class Expense {
  final String? id;
  final String riderId;
  final String? riderName;
  final String expenseType;
  final double amount;
  final double baseAmount;
  final double vatRate;
  final double vatAmount;
  final String expenseDate;
  final String? description;
  final String? status;
  final String? categoryId;
  final String? journalId;
  final String? receiptUrl;
  final String? createdByRole;
  final String? createdAt;
  final bool isReceivable;
  final bool isPayable;

  Expense({
    this.id,
    required this.riderId,
    this.riderName,
    required this.expenseType,
    required this.amount,
    this.baseAmount = 0.0,
    this.vatRate = 0.0,
    this.vatAmount = 0.0,
    required this.expenseDate,
    this.description,
    this.status,
    this.categoryId,
    this.journalId,
    this.receiptUrl,
    this.createdByRole,
    this.createdAt,
    this.isReceivable = false,
    this.isPayable = true,
  });

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: json['id']?.toString(),
      riderId: json['rider_id'] ?? '',
      riderName: json['rider_name'],
      expenseType: json['expense_type'] ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      baseAmount: (json['base_amount'] as num?)?.toDouble() ?? 0.0,
      vatRate: (json['vat_rate'] as num?)?.toDouble() ?? 0.0,
      vatAmount: (json['vat_amount'] as num?)?.toDouble() ?? 0.0,
      expenseDate: json['expense_date'] ?? '',
      description: json['description'],
      status: json['status'],
      categoryId: json['category_id']?.toString(),
      journalId: json['journal_id']?.toString(),
      receiptUrl: json['receipt_url'],
      createdByRole: json['created_by_role']?.toString(),
      createdAt: json['created_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'rider_id': riderId,
      'rider_name': riderName,
      'expense_type': expenseType,
      'amount': amount,
      'base_amount': baseAmount,
      'vat_rate': vatRate,
      'vat_amount': vatAmount,
      'expense_date': expenseDate,
      'description': description,
      'status': status?.toLowerCase(),
      if (categoryId != null) 'category_id': categoryId,
      if (journalId != null) 'journal_id': journalId,
      if (receiptUrl != null) 'receipt_url': receiptUrl,
      if (createdByRole != null) 'created_by_role': createdByRole,
      if (createdAt != null) 'created_at': createdAt,
    };
  }
}
