import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ledger_entry_model.dart';
import 'ledger_repository.dart';

class SupabaseLedgerRepository implements LedgerRepository {
  final SupabaseClient _client = Supabase.instance.client;

  bool _isSameRiderId(dynamic value, String riderId) {
    return value != null && value.toString() == riderId;
  }

  bool _isRiderType(dynamic value) {
    return (value ?? '').toString().toLowerCase() == 'rider';
  }

  bool _rowBelongsToRider(Map<String, dynamic> row, String riderId) {
    // Support both legacy ledger columns and newer journal-level party fields.
    if (_isSameRiderId(row['rider_id'], riderId)) {
      return true;
    }

    if (_isRiderType(row['party_type']) && _isSameRiderId(row['party_id'], riderId)) {
      return true;
    }

    final journals = row['journals'];
    if (journals is Map<String, dynamic>) {
      if (_isSameRiderId(journals['rider_id'], riderId)) {
        return true;
      }

      if (_isRiderType(journals['party_type']) && _isSameRiderId(journals['party_id'], riderId)) {
        return true;
      }

      if (_isRiderType(journals['receivable_entity_type']) &&
          _isSameRiderId(journals['receivable_entity_id'], riderId)) {
        return true;
      }
    }

    return false;
  }

  @override
  Future<List<LedgerEntryModel>> fetchEntries({
    String? account,
    String? fromDate,
    String? toDate,
  }) async {
    try {
      var query = _client.from('ledger').select('*, journals(*)');

      if (account != null) {
        query = query.eq('account_id', account);
      }
      if (fromDate != null) {
        query = query.gte('posted_at', fromDate);
      }
      if (toDate != null) {
        query = query.lte('posted_at', toDate);
      }

      final response = await query.order('id', ascending: false);
      final rows = (response as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final riderIds = <String>{};
      final vendorIds = <String>{};
      final supplierIds = <String>{};

      for (final row in rows) {
        final j = row['journals'];
        if (j is! Map<String, dynamic>) continue;

        final partyType =
            (j['party_type'] ?? j['receivable_entity_type'] ?? '').toString().toLowerCase();
        final partyId =
            (j['party_id'] ?? j['receivable_entity_id'] ?? j['rider_id'] ?? '').toString();
        if (partyId.isEmpty) continue;

        if (partyType == 'rider') {
          riderIds.add(partyId);
        } else if (partyType == 'vendor') {
          vendorIds.add(partyId);
        } else if (partyType == 'supplier') {
          supplierIds.add(partyId);
        }
      }

      final riderNameById = <String, String>{};
      final vendorNameById = <String, String>{};
      final supplierNameById = <String, String>{};

      if (riderIds.isNotEmpty) {
        final riderRows = await _client
            .from('riders')
            .select('id, name')
            .inFilter('id', riderIds.toList());
        for (final r in (riderRows as List)) {
          final m = Map<String, dynamic>.from(r as Map);
          final id = m['id']?.toString() ?? '';
          final name = m['name']?.toString() ?? '';
          if (id.isNotEmpty && name.isNotEmpty) riderNameById[id] = name;
        }
      }

      if (vendorIds.isNotEmpty) {
        final vendorRows = await _client
            .from('vendors')
            .select('id, name')
            .inFilter('id', vendorIds.toList());
        for (final v in (vendorRows as List)) {
          final m = Map<String, dynamic>.from(v as Map);
          final id = m['id']?.toString() ?? '';
          final name = m['name']?.toString() ?? '';
          if (id.isNotEmpty && name.isNotEmpty) vendorNameById[id] = name;
        }
      }

      if (supplierIds.isNotEmpty) {
        final supplierRows = await _client
            .from('suppliers')
            .select('id, name')
            .inFilter('id', supplierIds.toList());
        for (final s in (supplierRows as List)) {
          final m = Map<String, dynamic>.from(s as Map);
          final id = m['id']?.toString() ?? '';
          final name = m['name']?.toString() ?? '';
          if (id.isNotEmpty && name.isNotEmpty) supplierNameById[id] = name;
        }
      }

      for (final row in rows) {
        final j = row['journals'];
        if (j is! Map<String, dynamic>) continue;

        final partyType =
            (j['party_type'] ?? j['receivable_entity_type'] ?? '').toString().toLowerCase();
        final partyId =
            (j['party_id'] ?? j['receivable_entity_id'] ?? j['rider_id'] ?? '').toString();

        String? counterpartyName;
        if (partyType == 'rider') {
          counterpartyName = riderNameById[partyId];
        } else if (partyType == 'vendor') {
          counterpartyName = vendorNameById[partyId];
        } else if (partyType == 'supplier') {
          counterpartyName = supplierNameById[partyId];
        }

        j['counterparty_name'] = counterpartyName;
      }

      return rows.map(LedgerEntryModel.fromJson).toList();
    } catch (e) {
      print('Error fetching ledger entries: $e');
      return [];
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchSummary() async {
    try {
      // Keep summary deterministic across environments where RPC may be absent.
      final entries = await fetchEntries();
      final Map<String, Map<String, dynamic>> summaryMap = {};

      for (final entry in entries) {
        final acc = entry.accountName;
        if (!summaryMap.containsKey(acc)) {
          summaryMap[acc] = {
            'account_id': acc,
            'account_name': acc,
            'total_debit': 0.0,
            'total_credit': 0.0,
            'balance': 0.0,
          };
        }
        summaryMap[acc]!['total_debit'] += entry.debit;
        summaryMap[acc]!['total_credit'] += entry.credit;
        summaryMap[acc]!['balance'] += (entry.debit - entry.credit);
      }
      return summaryMap.values.toList();
    } catch (e) {
      print('Error fetching ledger summary: $e');
      return [];
    }
  }

  @override
  Future<List<Map<String, String>>> fetchAccounts() async {
    try {
      // Try to select both, if account_name fails, we catch and try just account_id
      final List<dynamic> response = await _client.from('ledger').select('account_id').limit(1000);
      
      final Map<String, String> map = {};
      for (final e in response) {
        final id = e['account_id']?.toString() ?? '';
        if (id.isEmpty) continue;
        // Since we know account_name might be missing, we'll just use ID for now
        // or join with an accounts table if we had one.
        map[id] = id; 
      }
      final accounts = map.entries
          .map((e) => {'id': e.key, 'name': e.value})
          .toList(growable: false);
      accounts.sort((a, b) => a['name']!.compareTo(b['name']!));
      return accounts;
    } catch (e) {
      print('Error fetching ledger accounts: $e');
      return [];
    }
  }

  @override
  Future<List<LedgerEntryModel>> fetchRiderStatement(String riderId) async {
    try {
      Future<List<Map<String, dynamic>>> _safeRows(
        Future<dynamic> Function() query,
      ) async {
        try {
          final res = await query();
          return (res as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        } catch (_) {
          return <Map<String, dynamic>>[];
        }
      }

      final byLedgerRiderId = await _safeRows(
        () => _client
            .from('ledger')
            .select('*, journals(*)')
            .eq('rider_id', riderId)
            .order('posted_at', ascending: false),
      );

      final byLedgerParty = await _safeRows(
        () => _client
            .from('ledger')
            .select('*, journals(*)')
            .eq('party_type', 'rider')
            .eq('party_id', riderId)
            .order('posted_at', ascending: false),
      );

      final byJournalRiderId = await _safeRows(
        () => _client
            .from('ledger')
        .select('*, journals!inner(*)')
            .eq('journals.rider_id', riderId)
            .order('posted_at', ascending: false),
      );

      final byJournalParty = await _safeRows(
        () => _client
            .from('ledger')
        .select('*, journals!inner(*)')
            .eq('journals.party_type', 'rider')
            .eq('journals.party_id', riderId)
            .order('posted_at', ascending: false),
      );

      final byJournalReceivable = await _safeRows(
        () => _client
            .from('ledger')
        .select('*, journals!inner(*)')
            .eq('journals.receivable_entity_type', 'rider')
            .eq('journals.receivable_entity_id', riderId)
            .order('posted_at', ascending: false),
      );

      final mergedByLedgerId = <String, Map<String, dynamic>>{};
      for (final source in [
        byLedgerRiderId,
        byLedgerParty,
        byJournalRiderId,
        byJournalParty,
        byJournalReceivable,
      ]) {
        for (final m in source) {
          final key = (m['id'] ?? '').toString();
          if (key.isEmpty) {
            continue;
          }
          mergedByLedgerId[key] = m;
        }
      }

      final mergedRows = mergedByLedgerId.values
          .where((row) => _rowBelongsToRider(row, riderId))
          .toList()
        ..sort(
          (a, b) => (DateTime.tryParse(b['posted_at']?.toString() ?? '') ??
                  DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(
                DateTime.tryParse(a['posted_at']?.toString() ?? '') ??
                    DateTime.fromMillisecondsSinceEpoch(0),
              ),
        );

      return mergedRows.map((e) {
        return LedgerEntryModel.fromJson(e);
      }).toList();
    } catch (e) {
      print("Error fetching rider statement: $e");
      return [];
    }
  }

  @override
  Future<Map<String, dynamic>> fetchRiderStatementSummary(String riderId) async {
    try {
      final response = await _client.rpc(
        'fn_get_rider_statement_summary',
        params: {'p_rider_id': riderId},
      );

      if (response is Map<String, dynamic>) {
        return response;
      }

      if (response is List && response.isNotEmpty && response.first is Map<String, dynamic>) {
        return response.first as Map<String, dynamic>;
      }

      return <String, dynamic>{};
    } catch (e) {
      print('Error fetching rider statement summary: $e');
      return <String, dynamic>{};
    }
  }
}
