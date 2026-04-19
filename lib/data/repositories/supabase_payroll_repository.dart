import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import '../models/payroll_model.dart';
import '../models/payroll_upload_response.dart';
import '../../services/api_service.dart';
import 'payroll_repository.dart';

class SupabasePayrollRepository implements PayrollRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // ───────────────────────── HISTORY ─────────────────────

  @override
  Future<List<PayrollBatchModel>> fetchPayrollHistory() async {
    try {
      final response = await _client
          .from('payroll_batches')
          .select()
          .order('created_at', ascending: false);
      final batches = (response as List)
          .map((e) => PayrollBatchModel.fromJson(e))
          .toList(growable: false);

      if (batches.isEmpty) {
        return batches;
      }

      final batchIds = batches
          .map((b) => b.id)
          .where((id) => id.isNotEmpty)
          .toList(growable: false);

      if (batchIds.isEmpty) {
        return batches;
      }

      final payslipRows = await _client
          .from('payslips')
          .select('batch_id, status, net_salary')
          .inFilter('batch_id', batchIds);

      final fullByBatch = <String, double>{};
      final pendingByBatch = <String, double>{};

      for (final row in (payslipRows as List)) {
        final m = Map<String, dynamic>.from(row as Map);
        final batchId = (m['batch_id'] ?? '').toString();
        if (batchId.isEmpty) {
          continue;
        }

        final net = (m['net_salary'] as num?)?.toDouble() ?? 0.0;
        final status = (m['status'] ?? '').toString();

        fullByBatch[batchId] = (fullByBatch[batchId] ?? 0.0) + net;
        if (status != 'finalized') {
          pendingByBatch[batchId] = (pendingByBatch[batchId] ?? 0.0) + net;
        }
      }

      return batches.map((b) {
        final full = fullByBatch[b.id];
        final pending = pendingByBatch[b.id] ?? 0.0;

        final recomputedTotal = b.status == PayrollBatchStatus.draft
            ? pending
            : (full ?? b.totalAmount);

        final normalizedStatus = (b.status == PayrollBatchStatus.finalized &&
                pending > 0)
            ? PayrollBatchStatus.draft
            : b.status;

        return b.copyWith(
          totalAmount: recomputedTotal,
          status: normalizedStatus,
        );
      }).toList(growable: false);
    } catch (e) {
      print("Error fetching payroll history: $e");
      return [];
    }
  }

  @override
  Future<Map<String, dynamic>> replacePayslipItems({
    required String payslipId,
    required List<Map<String, dynamic>> items,
    String? reason,
  }) {
    return ApiService.instance.replacePayslipItems(
      payslipId: payslipId,
      items: items,
      reason: reason,
    );
  }
  // ───────────────────────── UPLOAD ─────────────────────

  @override
  Future<List<PayslipDraftModel>> uploadPayrollSheet(
    File file,
    String platform,
    DateTime month,
  ) async {
    return []; // Use uploadPayroll instead
  }

  @override
  Future<PayrollUploadResponse> uploadPayroll(
    String month,
    String platform,
    List<Map<String, dynamic>> rows,
  ) async {
    try {
      // Delegate processing to the backend for atomicity and fault tolerance
      final response = await ApiService.instance.uploadPayroll(
        month,
        platform,
        rows,
      );
      return response;
    } catch (e) {
      print("Error in uploadPayroll delegation: $e");
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> fetchPayslips(String batchId) async {
    try {
      // 1-second safety delay to allow Supabase visibility to settle
      await Future.delayed(const Duration(seconds: 1));

      final batchData = await _client
          .from('payroll_batches')
          .select()
          .eq('id', batchId)
          .maybeSingle();

      if (batchData == null) {
        throw Exception(
          "Payroll Batch not found. Please refresh history manually.",
        );
      }

      final payslipsData = await _client
          .from('payslips')
          .select('*, riders(*)')
          .eq('batch_id', batchId);

      final List<dynamic> rawPayslips = List.from(payslipsData as List);
      final String platform = batchData['platform']?.toString() ?? 'Unknown';

      final List<dynamic> payslips = rawPayslips.map((p) {
        final map = Map<String, dynamic>.from(p);
        map['platform'] = platform;
        return map;
      }).toList();

      return {'batch': batchData, 'payslips': payslips};
    } catch (e) {
      print("Error fetching payslips: $e");
      throw e;
    }
  }

  // ignore: unused_element
  Future<void> _syncInternalDeductionsBatch(
    List<dynamic> payslips,
    List<String> riderIds,
  ) async {
    try {
      // 1. Fetch all pending fines and expenses for these riders in bulk
      final finesRes = await _client
          .from('traffic_fines')
          .select('id, rider_id, amount, remaining_balance')
          .inFilter('rider_id', riderIds)
          .inFilter('status', ['assigned', 'partially_recovered']);

      final expsRes = await _client
          .from('expenses')
          .select('id, rider_id, amount, expense_type')
          .inFilter('rider_id', riderIds)
          .inFilter('status', ['approved', 'posted', 'paid'])
          .not('journal_id', 'is', null);

      final finesByRider = <String, List<dynamic>>{};
      for (var f in (finesRes as List)) {
        final rId = f['rider_id'].toString();
        finesByRider.putIfAbsent(rId, () => []).add(f);
      }

      final expsByRider = <String, List<dynamic>>{};
      for (var ex in (expsRes as List)) {
        final rId = ex['rider_id'].toString();
        expsByRider.putIfAbsent(rId, () => []).add(ex);
      }

      final List<Map<String, dynamic>> updates = [];

      for (var p in payslips) {
        if (p['status'] == 'finalized' || p['rider_id'] == null) continue;
        final rId = p['rider_id'].toString();

        final List<dynamic> currentItems = List<dynamic>.from(p['items'] ?? []);
        // Remove existing internal items to avoid duplicates
        currentItems.removeWhere((item) => item['is_internal'] == true);

        double totalFines = 0.0;
        final riderFines = finesByRider[rId] ?? [];
        for (var f in riderFines) {
          final rem = f['remaining_balance'] != null
              ? (f['remaining_balance'] as num).toDouble()
              : (f['amount'] as num).toDouble();
          if (rem > 0) {
            totalFines += rem;
            currentItems.add({
              'label': 'Traffic Fine #${f['id'].toString().substring(0, 5)}',
              'amount': rem,
              'type': 'fine',
              'is_internal': true,
            });
          }
        }

        double totalEx = 0.0;
        final riderExps = expsByRider[rId] ?? [];
        for (var ex in riderExps) {
          final amt = (ex['amount'] as num).toDouble();
          if (amt > 0) {
            totalEx += amt;
            currentItems.add({
              'label': ex['expense_type']?.toString() ?? 'Company Expense',
              'amount': amt,
              'type': 'deduction',
              'is_internal': true,
            });
          }
        }

        // Re-calculate Net Salary
        final gross = (p['gross_salary'] as num? ?? 0.0).toDouble();
        final platformDed = (p['platform_deductions'] as num? ?? 0.0)
            .toDouble();
        final codDef = (p['cod_deficit'] as num? ?? 0.0).toDouble();
        final clawback = (p['clawback_deduction'] as num? ?? 0.0).toDouble();
        final arears = (p['arears'] as num? ?? 0.0).toDouble();
        final tdsBonus = (p['tds_bonus'] as num? ?? 0.0).toDouble();
        final foodComp = (p['food_compensation'] as num? ?? 0.0).toDouble();
        final tips = (p['tips'] as num? ?? 0.0).toDouble();

        double net =
            gross -
            platformDed -
            codDef -
            clawback -
            totalFines -
            totalEx +
            arears +
            tdsBonus +
            foodComp +
            tips;

        // Account for non-internal platform adjustments
        for (var item in currentItems) {
          if (item['is_internal'] == false) {
            final amt = (item['amount'] as num).toDouble();
            if (item['type'] == 'platform_earning')
              net += amt;
            else if (item['type'] == 'platform_deduction')
              net -= amt;
          }
        }

        // Detect changes before adding to update batch
        if ((p['total_fines'] as num? ?? 0).toDouble() != totalFines ||
            (p['total_expenses'] as num? ?? 0).toDouble() != totalEx ||
            (p['net_salary'] as num).toDouble() != net) {
          p['items'] = currentItems;
          p['net_salary'] = net;
          p['total_fines'] = totalFines;
          p['total_expenses'] = totalEx;

          if (p['status'] == 'error' && net >= 0) {
            p['status'] = 'matched';
            p['error_reason'] = null;
          } else if (net < 0) {
            p['status'] = 'error';
            p['error_reason'] =
                'Net salary negative (${net.toStringAsFixed(2)})';
          }

          updates.add({
            'id': p['id'],
            'items': currentItems,
            'net_salary': net,
            'status': p['status'],
            'error_reason': p['error_reason'],
            'total_fines': p['total_fines'],
            'total_expenses': p['total_expenses'],
          });
        }
      }

      // 2. Batch update the database if we found any changes
      if (updates.isNotEmpty) {
        for (var u in updates) {
          await _client.from('payslips').update(u).eq('id', u['id']);
        }
      }
    } catch (e) {
      print("Warning: Auto-sync deductions failed: $e");
    }
  }

  @override
  Future<void> syncBatch(String batchId) async {
    try {
      await ApiService.instance.syncBatch(batchId);
    } catch (e) {
      print("Error syncing batch via API: $e");
      rethrow;
    }
  }

  @override
  Future<void> editPayslipDeductionItem({
    required String payslipId,
    required int itemIndex,
    required double newAmount,
    String? expectedLabel,
    String? reason,
  }) async {
    await ApiService.instance.editPayslipDeductionItem(
      payslipId: payslipId,
      itemIndex: itemIndex,
      newAmount: newAmount,
      expectedLabel: expectedLabel,
      reason: reason,
    );
  }

  @override
  Future<Map<String, dynamic>> getPayslipGroupedDeductions(String payslipId) {
    return ApiService.instance.getPayslipGroupedDeductions(payslipId);
  }

  @override
  Future<Map<String, dynamic>> getBatchFlaggedPayslips(String batchId) {
    return ApiService.instance.getBatchFlaggedPayslips(batchId);
  }

  @override
  Future<Map<String, dynamic>> getBatchReviewSummary(String batchId) {
    return ApiService.instance.getBatchReviewSummary(batchId);
  }

  @override
  Future<Map<String, dynamic>> getCarryForwardOptions(String riderId) {
    return ApiService.instance.getCarryForwardOptions(riderId);
  }

  @override
  Future<Map<String, dynamic>> applyCarryForwardSelections(
    String payslipId,
    List<Map<String, dynamic>> selections,
  ) {
    return ApiService.instance.applyCarryForwardSelections(
      payslipId,
      selections,
    );
  }

  @override
  Future<void> recalculateDeductions(String payslipId, String riderId) async {
    try {
      final payslip = await _client
          .from('payslips')
          .select()
          .eq('id', payslipId)
          .single();
      final Map<String, dynamic> data = Map<String, dynamic>.from(payslip);

      final items = List<dynamic>.from(data['items'] ?? []);
      double totalFines = 0.0;
      double totalExpenses = 0.0;
      double net = 0.0;

      for (final raw in items) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final amt = (item['amount'] as num?)?.toDouble() ?? 0.0;
        final type = (item['type'] ?? '').toString().toLowerCase().trim();

        net += amt;
        if (type == 'fine') {
          totalFines += amt.abs();
        } else if (type == 'deduction') {
          totalExpenses += amt.abs();
        }
      }

      data['net_salary'] = net;
      data['total_fines'] = totalFines;
      data['total_expenses'] = totalExpenses;
      if (data['status'] == 'error' && net >= 0) {
        data['status'] = 'matched';
        data['error_reason'] = null;
      } else if (net < 0) {
        data['status'] = 'error';
        data['error_reason'] =
            'Net salary negative (${net.toStringAsFixed(2)})';
      }

      await _client
          .from('payslips')
          .update({
            'total_fines': data['total_fines'],
            'total_expenses': data['total_expenses'],
            'items': data['items'],
            'net_salary': data['net_salary'],
            'status': data['status'],
            'error_reason': data['error_reason'],
          })
          .eq('id', payslipId);
    } catch (e) {
      print('Error in recalculateDeductions: $e');
      rethrow;
    }
  }

  @override
  Future<void> finalizePayroll(
    List<PayslipDraftModel> drafts,
    String platform,
    DateTime month, {
    String? batchId,
  }) async {
    final normPlatform = platform.trim().toLowerCase();
    final batch = PayrollBatchModel(
      id: batchId ?? '',
      month: month,
      platform: normPlatform,
      status: PayrollBatchStatus.finalized,
      totalAmount: drafts.fold(0.0, (sum, i) => sum + i.netSalary),
    );
    if (batchId != null)
      await _client
          .from('payroll_batches')
          .update(batch.toJson())
          .eq('id', batchId);
    else
      await _client.from('payroll_batches').insert(batch.toJson());
    if (batchId != null)
      await _client
          .from('payslips')
          .update({'status': 'matched'})
          .eq('batch_id', batchId);
  }

  @override
  Future<void> updatePayslipData(
    String payslipId,
    Map<String, dynamic> data,
  ) async {
    try {
      await _client.from('payslips').update(data).eq('id', payslipId);
    } catch (e) {
      print("Error updating payslip data: $e");
      rethrow;
    }
  }

  @override
  Future<void> finalizeIndividualPayslip(
    String payslipId,
    String drawerId,
  ) async {
    try {
      final p = await _client
          .from('payslips')
          .select()
          .eq('id', payslipId)
          .single();
      if (p['status'] == 'error')
        throw Exception('Cannot finalize: payslip has errors.');

      final drawer = await _client
          .from('drawer')
          .select('balance')
          .eq('id', drawerId)
          .single();
      final net = (p['net_salary'] as num).toDouble();
      final String today = DateTime.now().toIso8601String().split('T').first;
      final String? userId = _client.auth.currentUser?.id;
      final riderId = p['rider_id']?.toString();
      final riderName = p['rider_name']?.toString() ?? 'Unknown';
      final batchId = p['batch_id']?.toString();

      // 1. Gross Salary Accrual
      final grossVal = (p['gross_salary'] as num).toDouble();
      await _createJournal(
        description: 'Salary accrual - $riderName',
        amount: grossVal.abs(),
        type: 'salary',
        riderId: riderId,
        userId: userId,
        date: today,
        payslipId: payslipId,
        lines: [
          {
            'account_id': 'salary_expense',
            'debit_amount': grossVal >= 0 ? grossVal : 0.0,
            'credit_amount': grossVal < 0 ? grossVal.abs() : 0.0,
          },
          {
            'account_id': 'rider_salary_payable',
            'debit_amount': grossVal < 0 ? grossVal.abs() : 0.0,
            'credit_amount': grossVal >= 0 ? grossVal : 0.0,
          },
        ],
      );

      // 2. Total Deductions
      final totalDeducted = (p['gross_salary'] as num).toDouble() - net;
      if (totalDeducted != 0) {
        final dVal = totalDeducted;
        await _createJournal(
          description: 'Payroll deductions - $riderName',
          amount: dVal.abs(),
          type: 'salary',
          riderId: riderId,
          userId: userId,
          date: today,
          payslipId: payslipId,
          lines: [
            {
              'account_id': 'rider_salary_payable',
              'debit_amount': dVal >= 0 ? dVal : 0.0,
              'credit_amount': dVal < 0 ? dVal.abs() : 0.0,
            },
            {
              'account_id': 'revenue_other',
              'debit_amount': dVal < 0 ? dVal.abs() : 0.0,
              'credit_amount': dVal >= 0 ? dVal : 0.0,
            },
          ],
        );
      }

      // 3. Net Payment
      String? journalId;
      if (net != 0) {
        final nVal = net;
        journalId = await _createJournal(
          description: 'Net salary payment - $riderName',
          amount: nVal.abs(),
          type: 'salary',
          riderId: riderId,
          userId: userId,
          date: today,
          drawerId: drawerId,
          payslipId: payslipId,
          lines: [
            {
              'account_id': 'rider_salary_payable',
              'debit_amount': nVal >= 0 ? nVal : 0.0,
              'credit_amount': nVal < 0 ? nVal.abs() : 0.0,
            },
            {
              'account_id': 'bank_drawer',
              'debit_amount': nVal < 0 ? nVal.abs() : 0.0,
              'credit_amount': nVal >= 0 ? nVal : 0.0,
              'drawer_id': drawerId,
            },
          ],
        );
      }

      // Update drawer balance
      final double currentBalance = (drawer['balance'] as num).toDouble();
      if (currentBalance < net)
        throw Exception('Insufficient funds in drawer.');
      await _client
          .from('drawer')
          .update({'balance': currentBalance - net})
          .eq('id', drawerId);

      // Mark as finalized and link journal
      await _client
          .from('payslips')
          .update({'status': 'finalized', 'journal_id': journalId})
          .eq('id', payslipId);

      // Keep batch totals/status consistent after each individual finalize.
      if (batchId != null && batchId.isNotEmpty) {
        final allPayslips = await _client
            .from('payslips')
            .select('status, net_salary')
            .eq('batch_id', batchId);

        final payslipRows = (allPayslips as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false);

        final hasPending = payslipRows.any(
          (row) => (row['status']?.toString() ?? '') != 'finalized',
        );

        final pendingTotal = payslipRows
            .where((row) => (row['status']?.toString() ?? '') != 'finalized')
            .fold<double>(
              0.0,
              (sum, row) => sum + ((row['net_salary'] as num?)?.toDouble() ?? 0.0),
            );

        await _client
            .from('payroll_batches')
            .update({
              'total_amount': pendingTotal,
              'status': hasPending ? 'draft' : 'finalized',
            })
            .eq('id', batchId);
      }
    } catch (e) {
      print('Error in finalizeIndividualPayslip: $e');
      rethrow;
    }
  }

  @override
  Future<void> finalizePayrollWithJournals(
    String batchId,
    String drawerId,
  ) async {
    try {
      await ApiService.instance.finalizePayrollBatch(batchId, drawerId);
    } catch (e) {
      print('Error finalizing payroll batch: $e');
      rethrow;
    }
  }

  Future<String> _createJournal({
    required String description,
    required double amount,
    required String type,
    String? riderId,
    String? userId,
    required String date,
    String? drawerId,
    String? payslipId,
    required List<Map<String, dynamic>> lines,
  }) async {
    final payload = <String, dynamic>{
      'entry_date': date,
      'description': description,
      'total_amount': amount,
      'base_amount': amount,
      'status': 'posted',
      'type': type,
      'payment_method': 'bank_transfer',
      'created_by_role': 'accountant',
      'receipt_url': payslipId != null ? 'payroll_link:$payslipId' : null,
      if (riderId != null) ...{
        'rider_id': riderId,
        'receivable_entity_type': 'rider',
        'receivable_entity_id': riderId,
        'party_type': 'rider',
        'party_id': riderId,
      },
      if (userId != null) 'created_by_user_id': userId,
      if (drawerId != null) 'drawer_id': drawerId,
      'lines': lines
          .map(
            (l) => <String, dynamic>{
              'account_id': l['account_id'],
              'debit_amount': l['debit_amount'] ?? 0,
              'credit_amount': l['credit_amount'] ?? 0,
              if (l['drawer_id'] != null) 'drawer_id': l['drawer_id'],
            },
          )
          .toList(),
    };

    final res = await ApiService.instance.createJournalRaw(payload);
    final journalId = (res['journal']?['id'] ?? '').toString();
    if (journalId.isEmpty) {
      throw Exception('Backend did not return journal id');
    }
    return journalId;
  }

  // ───────────────────────── RECONCILIATION HELPERS ─────────────────────

  // ignore: unused_element
  void _mapDynamicFinancials(
    String platform,
    Map<String, dynamic> raw,
    Map<String, dynamic> payslip,
    Set<String> handledKeys,
  ) {
    if (platform.toLowerCase() == 'talabat')
      _mapTalabatColumns(raw, payslip, handledKeys);
    else if (platform.toLowerCase() == 'keeta')
      _mapKeetaColumns(raw, payslip, handledKeys);

    // Safety filter to ignore non-monetary metadata (The Metadata Blacklist)
    final Set<String> blacklist = {
      'Month',
      'Year',
      'Platform',
      'Rider ID',
      'Status',
      'External ID',
      'ID',
      'Date',
      'Rider Name',
      'Courier Name',
      'Name',
      'C3 ID',
      'C3ID',
    };

    final List<dynamic> items = List<dynamic>.from(payslip['items'] ?? []);
    for (var entry in raw.entries) {
      final key = entry.key;
      if (handledKeys.contains(key) || blacklist.any((b) => key.contains(b)))
        continue;

      final valStr = entry.value?.toString().trim() ?? '';
      if (valStr.isEmpty) continue;

      final cleaned = valStr.replaceAll('AED', '').replaceAll(',', '').trim();
      final val = double.tryParse(cleaned);

      // Skip non-monetary or zero values
      if (val != null && val != 0 && key.length > 2) {
        items.add({
          'label': key,
          'amount': val.abs(),
          'type': val > 0 ? 'platform_earning' : 'platform_deduction',
          'is_internal': false,
        });
        handledKeys.add(key);
      }
    }
    payslip['items'] = items;
  }

  void _mapTalabatColumns(
    Map<String, dynamic> raw,
    Map<String, dynamic> payslip,
    Set<String> handledKeys,
  ) {
    payslip['gross_salary'] = _parseDouble(raw, [
      'Gross Salary',
      'Amount',
      'Total Pay',
    ], handledKeys);
    payslip['order_count'] = _parseInt(raw, [
      'Total Completed Deliveries',
      'Deliveries',
      'Orders',
    ], handledKeys);
    payslip['cod_deficit'] = _parseDouble(raw, ['COD Deficit'], handledKeys);
    payslip['clawback_deduction'] = _parseDouble(raw, [
      'Clawback Deduction',
      'Clawback',
    ], handledKeys);
    payslip['platform_deductions'] = _parseDouble(raw, [
      'Inventory Deduction',
      'Platform Deduction',
    ], handledKeys);
    payslip['arears'] = _parseDouble(raw, ['Arears', 'Arrears'], handledKeys);
    payslip['tds_bonus'] = _parseDouble(raw, ['TDS Bonus', 'TDS'], handledKeys);
    payslip['tips'] = _parseDouble(raw, ['Tips'], handledKeys);
  }

  void _mapKeetaColumns(
    Map<String, dynamic> raw,
    Map<String, dynamic> payslip,
    Set<String> handledKeys,
  ) {
    payslip['gross_salary'] = _parseDouble(raw, [
      'Total payable amount',
      'Courier earnings',
      'Amount',
    ], handledKeys);
    payslip['food_compensation'] = _parseDouble(raw, [
      'food compensation',
      'Food Compensation',
    ], handledKeys);
    payslip['tips'] = _parseDouble(raw, ['Tips'], handledKeys);
    payslip['order_count'] = _parseInt(raw, [
      'Online Days-Valid',
      'Online Days',
      'Orders',
    ], handledKeys);
    payslip['online_hours'] = _parseDouble(raw, [
      'Daily Onlines Hours-Valid',
      'Online Hours',
    ], handledKeys);
    payslip['platform_deductions'] = _parseDouble(raw, [
      'Deduction',
      'Deductions',
    ], handledKeys);
  }

  // ignore: unused_element
  Future<void> _injectInternalDeductions(
    String riderId,
    Map<String, dynamic> raw,
    Map<String, dynamic> payslip,
  ) async {
    try {
      final List<dynamic> items = List<dynamic>.from(payslip['items'] ?? []);
      items.removeWhere((i) => i['is_internal'] == true);
      final fines = await _client
          .from('traffic_fines')
          .select('id, amount, remaining_balance')
          .eq('rider_id', riderId)
          .inFilter('status', ['assigned', 'partially_recovered']);
      double totalFines = 0.0;
      for (var f in (fines as List)) {
        final rem = f['remaining_balance'] != null
            ? (f['remaining_balance'] as num).toDouble()
            : (f['amount'] as num).toDouble();
        if (rem > 0) {
          totalFines += rem;
          items.add({
            'label': 'Traffic Fine #${f['id'].toString().substring(0, 5)}',
            'amount': -rem,
            'type': 'fine',
            'is_internal': true,
          });
        }
      }
      final exps = await _client
          .from('expenses')
          .select('id, amount, expense_type')
          .eq('rider_id', riderId)
          .inFilter('status', ['approved', 'posted', 'paid'])
          .not('journal_id', 'is', null);
      double totalEx = 0.0;
      for (var ex in (exps as List)) {
        final amt = (ex['amount'] as num).toDouble();
        if (amt > 0) {
          totalEx += amt;
          items.add({
            'label': ex['expense_type']?.toString() ?? 'Company Expense',
            'amount': -amt,
            'type': 'deduction',
            'is_internal': true,
          });
        }
      }
      payslip['total_fines'] = totalFines;
      payslip['total_expenses'] = totalEx;
      payslip['items'] = items;
    } catch (_) {}
  }

  // ───────────────────────── PARSING UTILITIES ─────────────────────

  String _findValue(
    Map<String, dynamic> raw,
    List<String> keys, [
    Set<String>? handledKeys,
  ]) {
    for (final key in keys) {
      if (raw.containsKey(key) && raw[key] != null) {
        final val = raw[key].toString().trim();
        if (val.isNotEmpty) {
          handledKeys?.add(key);
          return val;
        }
      }
    }
    for (final key in keys) {
      for (final mapKey in raw.keys) {
        if (mapKey.toLowerCase().trim() == key.toLowerCase().trim()) {
          final val = raw[mapKey].toString().trim();
          if (val.isNotEmpty) {
            handledKeys?.add(mapKey);
            return val;
          }
        }
      }
    }
    return '';
  }

  double _parseDouble(
    Map<String, dynamic> raw,
    List<String> keys, [
    Set<String>? handledKeys,
  ]) {
    final val = _findValue(raw, keys, handledKeys);
    if (val.isEmpty) return 0.0;
    return double.tryParse(
          val.replaceAll('AED', '').replaceAll(',', '').trim(),
        ) ??
        0.0;
  }

  int _parseInt(
    Map<String, dynamic> raw,
    List<String> keys, [
    Set<String>? handledKeys,
  ]) {
    final val = _findValue(raw, keys, handledKeys);
    if (val.isEmpty) return 0;
    return double.tryParse(val.replaceAll(',', '').trim())?.toInt() ?? 0;
  }
}
