import 'package:equatable/equatable.dart';
import 'user_model.dart';
import '../../utils/date_utils.dart';

enum JournalStatus { draft, posted, reversed }

enum JournalType { expense, salary, fine, loan, manualAdjustment, suspense }

/// Helper to convert DB status string to enum.
/// New schema uses lowercase ENUM: 'draft', 'posted', 'reversed'
JournalStatus _statusFromString(String? s) {
  switch (s?.toLowerCase()) {
    case 'posted':
      return JournalStatus.posted;
    case 'reversed':
      return JournalStatus.reversed;
    default:
      return JournalStatus.draft;
  }
}

/// Helper to convert enum to DB status string (lowercase for ENUM type).
String _statusToString(JournalStatus s) {
  switch (s) {
    case JournalStatus.posted:
      return 'posted';
    case JournalStatus.reversed:
      return 'reversed';
    case JournalStatus.draft:
      return 'draft';
  }
}

/// Convert DB journal_type ENUM string to Dart enum.
JournalType _typeFromString(String? s) {
  switch (s?.toLowerCase()) {
    case 'salary':
      return JournalType.salary;
    case 'fine':
      return JournalType.fine;
    case 'loan':
      return JournalType.loan;
    case 'manual_adjustment':
      return JournalType.manualAdjustment;
    case 'suspense':
      return JournalType.suspense;
    default:
      return JournalType.expense;
  }
}

/// Convert Dart enum to DB journal_type ENUM string.
String _typeToString(JournalType t) {
  switch (t) {
    case JournalType.salary:
      return 'salary';
    case JournalType.fine:
      return 'fine';
    case JournalType.loan:
      return 'loan';
    case JournalType.manualAdjustment:
      return 'manual_adjustment';
    case JournalType.suspense:
      return 'suspense';
    case JournalType.expense:
      return 'expense';
  }
}

/// Convert DB user_role ENUM string to Dart [UserRole].
UserRole _roleFromString(String? s) {
  switch (s?.toLowerCase()) {
    case 'accountant':
      return UserRole.accountant;
    default:
      return UserRole.pro;
  }
}

/// Fallback: infer journal type from description text when DB type is null.
JournalType _inferType(String description) {
  final lower = description.toLowerCase();
  if (lower.contains('salary') || lower.contains('payroll')) {
    return JournalType.salary;
  }
  if (lower.contains('fine') || lower.contains('traffic')) {
    return JournalType.fine;
  }
  if (lower.contains('loan') || lower.contains('advance')) {
    return JournalType.loan;
  }
  return JournalType.expense;
}

class JournalModel extends Equatable {
  final String id;
  final DateTime date;
  final String description;
  final double amount;
  final JournalStatus status;
  final JournalType type;
  final UserRole createdByRole;
  final String? paymentMethod;
  final String? drawerId;
  final List<JournalEntryModel> entries;

  // --- DB-compatible fields ---
  final bool isReceivable;
  final String? receivableEntityType;
  final String? receivableEntityId;
  final double? receivableAmount;
  final String? createdByUserId;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? reversalOfJournalId;
  final DateTime? createdAt;
  final double? baseAmount;
  final double? vatRate;
  final double? vatAmount;

  // Expense-linked fields (SRS 1.1.1: no transaction without a journal)
  final String? expenseType;
  final String? riderId;
  final String? receiptUrl;

  const JournalModel({
    required this.id,
    required this.date,
    required this.description,
    required this.amount,
    required this.status,
    required this.type,
    required this.createdByRole,
    this.paymentMethod,
    this.drawerId,
    this.entries = const [],
    this.isReceivable = false,
    this.receivableEntityType,
    this.receivableEntityId,
    this.receivableAmount,
    this.createdByUserId,
    this.approvedBy,
    this.approvedAt,
    this.reversalOfJournalId,
    this.createdAt,
    this.baseAmount,
    this.vatRate,
    this.vatAmount,
    this.expenseType,
    this.riderId,
    this.receiptUrl,
  });

  /// Construct from a JSON map returned by the backend / Supabase.
  /// Expects the journals row with an optional nested `journal_lines` list.
  factory JournalModel.fromJson(Map<String, dynamic> json) {
    final List<JournalEntryModel> lines = [];
    if (json['journal_lines'] != null) {
      for (final line in json['journal_lines'] as List) {
        lines.add(JournalEntryModel.fromJson(line as Map<String, dynamic>));
      }
    }

    // Compute amount: prefer DB total_amount, else sum debits from lines
    double amount = 0;
    if (json['total_amount'] != null) {
      amount = (json['total_amount'] as num).toDouble();
    } else if (lines.isNotEmpty) {
      amount = lines.fold(0.0, (sum, l) => sum + l.debitAmount);
    }
    // Fallback: if backend passes amount directly
    if (amount == 0 && json['amount'] != null) {
      amount = (json['amount'] as num).toDouble();
    }

    final description = json['description'] ?? '';

    // Read type from DB, fallback to inference
    final JournalType type = json['type'] != null
        ? _typeFromString(json['type'].toString())
        : _inferType(description);

    // Read created_by_role from DB, fallback to accountant
    final UserRole role = json['created_by_role'] != null
        ? _roleFromString(json['created_by_role'].toString())
        : UserRole.accountant;

    final String _entryRaw = json['entry_date']?.toString() ?? '';
    final DateTime _entryDate = parseDateOnly(_entryRaw) ?? DateTime.now();

    String? expenseType = json['expense_type']?.toString();
    if ((expenseType == null || expenseType.isEmpty) && json['expenses'] is List) {
      final expenses = json['expenses'] as List;
      if (expenses.isNotEmpty && expenses.first is Map<String, dynamic>) {
        expenseType = (expenses.first as Map<String, dynamic>)['expense_type']?.toString();
      }
    }

    return JournalModel(
      id: json['id']?.toString() ?? '',
      date: _entryDate,
      description: description,
      amount: amount,
      status: _statusFromString(json['status']?.toString()),
      type: type,
      createdByRole: role,
      paymentMethod: json['payment_method']?.toString(),
      drawerId: json['drawer_id']?.toString(),
      entries: lines,
      isReceivable: json['is_receivable'] == true,
      receivableEntityType: json['receivable_entity_type'],
      receivableEntityId: json['receivable_entity_id']?.toString(),
      receivableAmount: json['receivable_amount'] != null
          ? (json['receivable_amount'] as num).toDouble()
          : null,
      createdByUserId: json['created_by_user_id']?.toString(),
      approvedBy: json['approved_by']?.toString(),
      approvedAt: DateTime.tryParse(json['approved_at']?.toString() ?? ''),
      reversalOfJournalId: json['reversal_of_journal_id']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
        baseAmount: json['base_amount'] != null
          ? (json['base_amount'] as num).toDouble()
          : null,
        vatRate: json['vat_rate'] != null
          ? (json['vat_rate'] as num).toDouble()
          : null,
        vatAmount: json['vat_amount'] != null
          ? (json['vat_amount'] as num).toDouble()
          : null,
      expenseType: expenseType,
      riderId: json['rider_id']?.toString(),
      receiptUrl: json['receipt_url']?.toString(),
    );
  }

  /// Serialize to JSON for creating a journal via the backend.
  Map<String, dynamic> toJson() {
    return {
      'entry_date': formatDateForServer(date),
      'description': description,
      'total_amount': amount,
      if (baseAmount != null) 'base_amount': baseAmount,
      if (vatRate != null) 'vat_rate': vatRate,
      if (vatAmount != null) 'vat_amount': vatAmount,
      'status': _statusToString(status),
      'type': _typeToString(type),
      'created_by_role': createdByRole.name,
      'is_receivable': isReceivable,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (drawerId != null) 'drawer_id': drawerId,
      if (receivableEntityType != null)
        'receivable_entity_type': receivableEntityType,
      if (receivableEntityId != null)
        'receivable_entity_id': receivableEntityId,
      if (receivableAmount != null) 'receivable_amount': receivableAmount,
      if (createdByUserId != null) 'created_by_user_id': createdByUserId,
      if (receiptUrl != null) 'receipt_url': receiptUrl,
      if (riderId != null) 'rider_id': riderId,
      if (expenseType != null) 'expense_type': expenseType,
      'lines': entries.map((e) => e.toJson()).toList(),
    };
  }

  JournalModel copyWith({
    String? id,
    DateTime? date,
    String? description,
    double? amount,
    JournalStatus? status,
    JournalType? type,
    UserRole? createdByRole,
    String? paymentMethod,
    String? drawerId,
    List<JournalEntryModel>? entries,
    bool? isReceivable,
    String? receivableEntityType,
    String? receivableEntityId,
    double? receivableAmount,
    String? createdByUserId,
    String? approvedBy,
    DateTime? approvedAt,
    String? reversalOfJournalId,
    DateTime? createdAt,
    String? expenseType,
    String? riderId,
    String? receiptUrl,
    double? baseAmount,
    double? vatRate,
    double? vatAmount,
  }) {
    return JournalModel(
      id: id ?? this.id,
      date: date ?? this.date,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      status: status ?? this.status,
      type: type ?? this.type,
      createdByRole: createdByRole ?? this.createdByRole,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      drawerId: drawerId ?? this.drawerId,
      entries: entries ?? this.entries,
      isReceivable: isReceivable ?? this.isReceivable,
      receivableEntityType: receivableEntityType ?? this.receivableEntityType,
      receivableEntityId: receivableEntityId ?? this.receivableEntityId,
      receivableAmount: receivableAmount ?? this.receivableAmount,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      approvedBy: approvedBy ?? this.approvedBy,
      approvedAt: approvedAt ?? this.approvedAt,
      reversalOfJournalId: reversalOfJournalId ?? this.reversalOfJournalId,
      createdAt: createdAt ?? this.createdAt,
      baseAmount: baseAmount ?? this.baseAmount,
      vatRate: vatRate ?? this.vatRate,
      vatAmount: vatAmount ?? this.vatAmount,
      expenseType: expenseType ?? this.expenseType,
      riderId: riderId ?? this.riderId,
      receiptUrl: receiptUrl ?? this.receiptUrl,
    );
  }

  @override
  List<Object?> get props => [
    id,
    date,
    description,
    amount,
    status,
    type,
    createdByRole,
    paymentMethod,
    drawerId,
    entries,
    isReceivable,
    receivableEntityType,
    receivableEntityId,
    receivableAmount,
    createdByUserId,
    approvedBy,
    approvedAt,
    reversalOfJournalId,
    createdAt,
    baseAmount,
    vatRate,
    vatAmount,
    expenseType,
    riderId,
  ];
}

class JournalEntryModel extends Equatable {
  final String accountId;
  final double debitAmount;
  final double creditAmount;
  final String? drawerId;

  const JournalEntryModel({
    required this.accountId,
    this.debitAmount = 0.0,
    this.creditAmount = 0.0,
    this.drawerId,
  });

  /// Construct from a journal_lines DB row.
  /// New schema columns: account_id, debit_amount, credit_amount, drawer_id
  factory JournalEntryModel.fromJson(Map<String, dynamic> json) {
    return JournalEntryModel(
      accountId: json['account_id']?.toString() ?? '',
      debitAmount: (json['debit_amount'] as num?)?.toDouble() ?? 0.0,
      creditAmount: (json['credit_amount'] as num?)?.toDouble() ?? 0.0,
      drawerId: json['drawer_id']?.toString(),
    );
  }

  /// Serialize to JSON for backend insertion.
  Map<String, dynamic> toJson() {
    return {
      'account_id': accountId,
      'debit_amount': debitAmount,
      'credit_amount': creditAmount,
      if (drawerId != null) 'drawer_id': drawerId,
    };
  }

  @override
  List<Object?> get props => [accountId, debitAmount, creditAmount, drawerId];
}
