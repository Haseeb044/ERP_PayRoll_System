import 'package:equatable/equatable.dart';

/// Maps to the `ledger` table.
/// Read-only double-entry ledger rows auto-populated by the
/// `fn_journal_to_ledger` trigger whenever a journal status
/// changes to 'Posted'.
class LedgerEntryModel extends Equatable {
  final String id;
  final String journalId;
  final String journalLineId;
  final String accountName;
  final double debit;
  final double credit;
  final DateTime postedAt;

  // Joined fields (from journal header — optional)
  final String? journalDescription;
  final String? entryDate;
  final String? journalType;
  final String? counterpartyName;
  final String? counterpartyType;
  final String? counterpartyId;

  const LedgerEntryModel({
    required this.id,
    required this.journalId,
    required this.journalLineId,
    required this.accountName,
    required this.debit,
    required this.credit,
    required this.postedAt,
    this.journalDescription,
    this.entryDate,
    this.journalType,
    this.counterpartyName,
    this.counterpartyType,
    this.counterpartyId,
  });

  /// Net effect: positive = debit-heavy, negative = credit-heavy.
  double get netAmount => debit - credit;

  factory LedgerEntryModel.fromJson(Map<String, dynamic> json) {
    // Handle joined journal data
    final journals = json['journals'];
    String? description;
    String? date;
    String? type;
    String? partyName;
    String? partyType;
    String? partyId;
    if (journals is Map<String, dynamic>) {
      description = journals['description']?.toString();
      date = journals['entry_date']?.toString();
      type = journals['type']?.toString();
      partyName = journals['counterparty_name']?.toString();
      partyType = journals['party_type']?.toString() ?? journals['receivable_entity_type']?.toString();
      partyId = journals['party_id']?.toString() ?? journals['receivable_entity_id']?.toString() ?? journals['rider_id']?.toString();
    }

    return LedgerEntryModel(
      id: json['id']?.toString() ?? '',
      journalId: json['journal_id']?.toString() ?? '',
      journalLineId: json['journal_line_id']?.toString() ?? '',
      // Support both old (account_name) and new (account_id) column names
      accountName: json['account_name']?.toString() ??
          json['account_id']?.toString() ??
          '',
      debit: (json['debit'] as num?)?.toDouble() ??
          (json['debit_amount'] as num?)?.toDouble() ??
          0.0,
      credit: (json['credit'] as num?)?.toDouble() ??
          (json['credit_amount'] as num?)?.toDouble() ??
          0.0,
      postedAt: DateTime.tryParse(json['posted_at']?.toString() ?? '') ??
          DateTime.now(),
      journalDescription: description,
      entryDate: date,
      journalType: type,
      counterpartyName: partyName,
      counterpartyType: partyType,
      counterpartyId: partyId,
    );
  }

  @override
  List<Object?> get props => [
    id,
    journalId,
    journalLineId,
    accountName,
    debit,
    credit,
    postedAt,
    journalDescription,
    entryDate,
    journalType,
    counterpartyName,
    counterpartyType,
    counterpartyId,
  ];
}
