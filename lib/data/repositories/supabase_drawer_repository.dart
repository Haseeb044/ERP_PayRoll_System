import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/drawer_model.dart';
import 'drawer_repository.dart';

class SupabaseDrawerRepository implements DrawerRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Maps a drawer type string to a friendly display name
  static String _nameForType(String type) {
    switch (type.toLowerCase()) {
      case 'bank':
        return 'ADCB Bank';
      case 'noqodi':
        return 'Noqodi Wallet';
      case 'petty_cash':
        return 'Main Safe';
      default:
        return type.replaceAll('_', ' ');
    }
  }

  /// Maps a drawer type string to a DrawerType enum
  static DrawerType _typeForString(String type) {
    switch (type.toLowerCase()) {
      case 'bank':
        return DrawerType.bank;
      case 'noqodi':
        return DrawerType.wallet;
      case 'petty_cash':
        return DrawerType.cash;
      default:
        return DrawerType.cash;
    }
  }

  /// Maps a drawer type string to a color code
  static int _colorForType(String type) {
    switch (type.toLowerCase()) {
      case 'bank':
        return 0xFF3B82F6; // Blue
      case 'noqodi':
        return 0xFF8B5CF6; // Purple
      case 'petty_cash':
        return 0xFFF97316; // Orange
      default:
        return 0xFF10B981; // Green
    }
  }

  @override
  Future<List<DrawerModel>> fetchDrawers() async {
    try {
      final response = await _client.from('drawer').select().order('type');

      return (response as List).map((json) {
        final type = json['type']?.toString() ?? 'unknown';
        final drawerId = json['id']?.toString() ?? type;

        return DrawerModel(
          id: drawerId,
          name: _nameForType(type),
          type: _typeForString(type),
          // Source of truth for UI: persisted drawer balance maintained by accounting flows.
          balance: (json['balance'] as num?)?.toDouble() ?? 0.0,
          colorCode: _colorForType(type),
        );
      }).toList();
    } catch (e) {
      print("Error fetching drawers from database: $e");
      return [];
    }
  }

  @override
  Future<List<DrawerTransactionModel>> fetchTransactions(
    String? drawerId,
  ) async {
    try {
        // Direct query to journal_lines joined with its parent journal
        var query = _client.from('journal_lines')
          .select('*, journals(description, entry_date, status, type)');
      
      if (drawerId != null) {
        query = query.eq('drawer_id', drawerId);
      } else {
        query = query.not('drawer_id', 'is', null);
      }

      final response = await query.order('entry_date', referencedTable: 'journals', ascending: false).limit(100);

      return (response as List).map((json) {
        final journal = json['journals'] as Map<String, dynamic>;
        final double debit = (json['debit_amount'] as num?)?.toDouble() ?? 0.0;
        final double credit = (json['credit_amount'] as num?)?.toDouble() ?? 0.0;
        
        // For a Drawer (Asset account):
        // Debit = Money In (isCredit: true in model terms)
        // Credit = Money Out (isCredit: false in model terms)
        final bool isCredit = debit > 0;
        final double amount = isCredit ? debit : credit;

        return DrawerTransactionModel(
          id: json['id']?.toString() ?? '',
          drawerId: json['drawer_id']?.toString() ?? '',
          amount: amount,
          isCredit: isCredit,
          description: journal['description'] ?? 'System Transaction',
          date: DateTime.tryParse(journal['entry_date'] ?? json['created_at'] ?? '') ?? DateTime.now(),
        );
      }).toList();
    } catch (e) {
      print("Error fetching transactions from database: $e");
      return [];
    }
  }

  @override
  Future<void> transferFunds({
    required String sourceDrawerId,
    required String targetDrawerId,
    required double amount,
    required String description,
  }) async {
    final sourceRes = await _client
        .from('drawer')
        .select('balance')
        .eq('id', sourceDrawerId)
        .single();
    final targetRes = await _client
        .from('drawer')
        .select('balance')
        .eq('id', targetDrawerId)
        .single();

    final sourceBalance = (sourceRes['balance'] as num?)?.toDouble() ?? 0.0;
    final targetBalance = (targetRes['balance'] as num?)?.toDouble() ?? 0.0;

    if (sourceBalance < amount) {
      throw Exception('Insufficient funds in source drawer');
    }

    await _client
        .from('drawer')
        .update({'balance': sourceBalance - amount})
        .eq('id', sourceDrawerId);
    await _client
        .from('drawer')
        .update({'balance': targetBalance + amount})
        .eq('id', targetDrawerId);
  }

  @override
  Future<void> addTransaction(DrawerTransactionModel transaction) async {
    final res = await _client
        .from('drawer')
        .select('balance')
        .eq('id', transaction.drawerId)
        .single();

    final currentBalance = (res['balance'] as num?)?.toDouble() ?? 0.0;
    final delta = transaction.isCredit
        ? transaction.amount.abs()
        : -transaction.amount.abs();
    final updatedBalance = currentBalance + delta;

    if (updatedBalance < 0) {
      throw Exception('Insufficient funds in drawer');
    }

    await _client
        .from('drawer')
        .update({'balance': updatedBalance})
        .eq('id', transaction.drawerId);
  }

  @override
  Future<bool> hasSufficientFunds(String drawerId, double amount) async {
    try {
      final res = await _client
          .from('drawer')
          .select('balance')
          .eq('id', drawerId)
          .single();
      final balance = (res['balance'] as num?)?.toDouble() ?? 0.0;
      return balance >= amount;
    } catch (e) {
      print("Error checking sufficient funds: $e");
      return false;
    }
  }
}
