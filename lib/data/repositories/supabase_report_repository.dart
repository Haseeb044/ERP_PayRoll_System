
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'report_repository.dart';

class SupabaseReportRepository implements ReportRepository {
  final SupabaseClient _client = Supabase.instance.client;

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  bool _isDeductionType(String type) {
    final lower = type.toLowerCase();
    return lower == 'deduction' ||
        lower == 'fine' ||
      lower == 'loan' ||
        lower == 'platform_deduction' ||
        lower == 'platformdeduction';
  }

  @override
  Future<Map<String, dynamic>> fetchReportSummary(DateTime month) async {
    try {
      final startDate = DateTime(month.year, month.month, 1)
        .toIso8601String()
        .split('T')
        .first;
      final endDate = DateTime(month.year, month.month + 1, 0)
        .toIso8601String()
        .split('T')
        .first;
      final monthKey =
        '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';

        // 1) Revenue/Net Pay: only finalized payslips from finalized batches in selected month.
      final batchRes = await _client
          .from('payroll_batches')
          .select('id')
          .eq('status', 'finalized')
          .eq('month', monthKey);

      double totalRevenue = 0;
      double totalNetPay = 0;
      Map<String, Map<String, dynamic>> deductionGroups = {};
      Map<String, double> extraEarningGroups = {};
      List<Map<String, dynamic>> realTimeDeductions = [];

      final batchIds = (batchRes as List)
          .map((b) => (b as Map)['id'].toString())
          .toList();

      if (batchIds.isNotEmpty) {
        final payslipRes = await _client
            .from('payslips')
            .select('gross_salary, net_salary, items, status, created_at')
            .inFilter('batch_id', batchIds)
            .eq('status', 'finalized');

        final now = DateTime.now();
        for (var p in payslipRes) {
          final row = Map<String, dynamic>.from(p as Map);
          final gross = _toDouble(row['gross_salary']);
          final net = _toDouble(row['net_salary']);
          totalRevenue += gross;
          totalNetPay += net;

          // Group deductions from items
          final items = row['items'];
          if (items is List) {
            for (var item in items) {
              final type = item['type']?.toString() ?? '';
              if (_isDeductionType(type)) {
                final label = item['label']?.toString() ?? type;
                final amt = _toDouble(item['amount']);
                if (deductionGroups.containsKey(label)) {
                  deductionGroups[label]!['amount'] =
                      (deductionGroups[label]!['amount'] as double) + amt;
                  deductionGroups[label]!['count'] =
                      (deductionGroups[label]!['count'] as int) + 1;
                } else {
                  deductionGroups[label] = {'amount': amt, 'count': 1};
                }
                // Real-time deductions (last 30 days)
                final createdAt = DateTime.tryParse(row['created_at']?.toString() ?? '');
                if (createdAt != null && now.difference(createdAt).inDays <= 30) {
                  realTimeDeductions.add({
                    'label': label,
                    'amount': amt,
                    'type': type,
                    'created_at': createdAt.toIso8601String(),
                  });
                }
              } else {
                final label = (item['label'] ?? '').toString().trim();
                final lowerLabel = label.toLowerCase();
                final amount = _toDouble(item['amount']);
                // Extra earnings should exclude base salary/gross and only show additional earnings.
                final isBaseSalaryLike =
                    lowerLabel == 'basic gross' ||
                    lowerLabel == 'gross' ||
                    lowerLabel == 'gross salary' ||
                    lowerLabel == 'basic salary' ||
                    lowerLabel == 'base salary';
                if (!isBaseSalaryLike && amount != 0) {
                  final normalized = label.isEmpty ? 'Other Extra Earning' : label;
                  extraEarningGroups[normalized] =
                      (extraEarningGroups[normalized] ?? 0) + amount;
                }
              }
            }
          }
        }
      }

      // 2) Journal rows for selected month.
      final journalRes = await _client
          .from('journals')
          .select(
            'type, description, total_amount, base_amount, receivable_amount, outstanding_amount, settled_amount, is_receivable, is_payable, party_type, payment_timing, linked_journal_id',
          )
          .eq('status', 'posted')
          .gte('entry_date', startDate)
          .lte('entry_date', endDate);

      double nonRecoverableExpense = 0;
      double recoverableExpenses = 0;
      double recoverableFines = 0;
      double recoverableCreated = 0;
      double recoverableOutstanding = 0;
      double recoverableCollected = 0;
      double recoverableJournalsAmount = 0;
      Map<String, double> categories = {};
      for (var e in journalRes) {
        final row = Map<String, dynamic>.from(e as Map);
        final journalType = (row['type'] ?? '').toString().toLowerCase();
        final description = (row['description'] ?? '').toString();
        final lowerDescription = description.toLowerCase();
        final isReceivable = row['is_receivable'] == true;
        final isPayable = row['is_payable'] == true;
        final partyType = (row['party_type'] ?? '').toString().toLowerCase();
        final paymentTiming =
          (row['payment_timing'] ?? '').toString().toLowerCase();
        final linkedJournalId = (row['linked_journal_id'] ?? '').toString();

        // Salary journals must never participate in expense reporting calculations.
        if (journalType == 'salary') {
          continue;
        }

        if (isReceivable && (journalType == 'expense' || journalType == 'loan')) {
          // Recoverable expenses/loans must use base amount.
          final base = _toDouble(row['base_amount']) > 0
              ? _toDouble(row['base_amount'])
              : _toDouble(row['total_amount']);
          recoverableExpenses += base;
          recoverableJournalsAmount += base;

          final receivable = _toDouble(row['receivable_amount']);
          final outstandingRaw = row['outstanding_amount'];
          final settledRaw = row['settled_amount'];
          final outstanding = outstandingRaw == null
              ? receivable
              : _toDouble(outstandingRaw).clamp(0.0, receivable);
          final settled = settledRaw == null
              ? (receivable - outstanding)
              : _toDouble(settledRaw).clamp(0.0, receivable);
          recoverableCreated += receivable;
          recoverableOutstanding += outstanding;
          recoverableCollected += settled;
          continue;
        }

        final isFineLike =
            journalType == 'fine' ||
            lowerDescription.contains('traffic fine') ||
            lowerDescription.startsWith('fine') ||
            lowerDescription.contains('fines:');
        if (isFineLike) {
          // Fine-like journals must always stay in recoverable section.
          recoverableFines += _toDouble(row['total_amount']);
          continue;
        }

        bool includeInNonRecoverable = false;
        final isVendorSettlementPayment =
            journalType == 'manual_adjustment' &&
            linkedJournalId.isNotEmpty &&
            partyType == 'vendor';
        if (partyType == 'vendor' && isPayable) {
          // Vendor accruals (pay_later) should not hit P&L until paid.
          final isVendorPayNow = paymentTiming == 'pay_now';
          includeInNonRecoverable = isVendorPayNow || isVendorSettlementPayment;
        } else {
          // Only business expense/loan journals belong to non-recoverable here.
          final isExpenseLike = journalType == 'expense' || journalType == 'loan';
          includeInNonRecoverable = !isReceivable && isExpenseLike;
        }

        if (includeInNonRecoverable) {
          // Non-recoverable includes only eligible paid/vendor and non-receivable journals.
          final amt = _toDouble(row['total_amount']);
          nonRecoverableExpense += amt;

          final desc = description.trim();
          final cat = isVendorSettlementPayment
              ? 'Vendor Payment (Pay Later Settlement)'
              : ((desc == null || desc.isEmpty) ? 'Expense' : desc);
          categories[cat] = (categories[cat] ?? 0) + amt;
        }
      }

      final hasFinalizedBatch = batchIds.isNotEmpty;
        final recoverableTotal = recoverableExpenses + recoverableFines;
      final companyExpenses = hasFinalizedBatch
          ? (nonRecoverableExpense + recoverableTotal)
          : 0.0;
      final netProfit = totalRevenue - totalNetPay - companyExpenses;

      final expenseBreakdown = categories.entries.map((e) => {
        'label': e.key,
        'amount': e.value,
          },).toList();

      final deductions = deductionGroups.entries.map((e) => {
        'label': e.key,
        'amount': e.value['amount'],
        'count': e.value['count'],
          },).toList();

      final extraEarningsBreakdown = extraEarningGroups.entries
          .map((e) => {
                'label': e.key,
                'amount': e.value,
              })
          .toList();
      final extraEarningsTotal =
          extraEarningGroups.values.fold(0.0, (sum, value) => sum + value);

      // Return a map with explicit keys for UI mapping
      return {
        // Total revenue from finalized payslips (gross)
        'total_revenue': totalRevenue,
        // Net pay (finalized)
        'total_net_pay': totalNetPay,
        // Company expenses: non-recoverable + recoverable (expenses + fines)
        'company_expenses': companyExpenses,
        // Net profit: revenue - net pay - company expenses
        'net_profit': netProfit,
        // Non-recoverable expenses only (P&L impact)
        'non_recoverable_expense': nonRecoverableExpense,
        // Recoverable amounts for section totals
        'recoverable_outstanding': recoverableOutstanding,
        // Recoverable expenses from journals (base amounts)
        'recoverable_journals': recoverableJournalsAmount,
        // Recoverable fines from posted fine journals
        'recoverable_fines': recoverableFines,
        // Recoverable amounts collected this month
        'recoverable_collected': recoverableCollected,
        // Recoverable amounts created this month
        'recoverable_created': recoverableCreated,
        // Expense breakdown by category
        'expense_breakdown': expenseBreakdown,
        // Deductions breakdown from payslips
        'deductions': deductions,
        // Extra earnings (tips/bonus) from finalized payslips
        'extra_earnings_total': extraEarningsTotal,
        'extra_earnings_breakdown': extraEarningsBreakdown,
        // Real-time deductions (last 30 days)
        'real_time_deductions': realTimeDeductions,
        // Legacy keys for backward compatibility (can be removed if UI is updated)
        'total_expense': companyExpenses,
        'recoverable_amount': recoverableTotal,
      };
    } catch (e) {
      print('Error fetching report summary: $e');
      return {
        'total_revenue': 0.0,
        'total_expense': 0.0,
        'net_profit': 0.0,
        'recoverable_amount': 0.0,
        'recoverable_journals': 0.0,
        'non_recoverable_expense': 0.0,
        'recoverable_outstanding': 0.0,
        'recoverable_collected': 0.0,
        'recoverable_created': 0.0,
        'extra_earnings_total': 0.0,
        'extra_earnings_breakdown': [],
        'expense_breakdown': [],
        'deductions': [],
      };
    }
  }

  @override
  Future<Map<String, dynamic>> fetchFineAging() async {
    try {
      final response = await _client
          .from('traffic_fines')
          .select('status, amount, violation_date, created_at');
      Map<String, double> aging = {
        '0-30 days': 0,
        '31-60 days': 0,
        '61-90 days': 0,
        '90+ days': 0,
      };

      final now = DateTime.now();
      for (var f in response) {
        final safeF = Map<String, dynamic>.from(f as Map);
        final dateSource = safeF['violation_date']?.toString() ??
            safeF['created_at']?.toString();
        if (dateSource == null || dateSource.isEmpty) continue;

        final sourceDate = DateTime.tryParse(dateSource);
        if (sourceDate == null) continue;

        final diff = now.difference(sourceDate).inDays;
        final amount = (safeF['amount'] as num?)?.toDouble() ?? 0.0;

        if (diff <= 30) aging['0-30 days'] = (aging['0-30 days'] ?? 0) + amount;
        else if (diff <= 60) aging['31-60 days'] = (aging['31-60 days'] ?? 0) + amount;
        else if (diff <= 90) aging['61-90 days'] = (aging['61-90 days'] ?? 0) + amount;
        else aging['90+ days'] = (aging['90+ days'] ?? 0) + amount;
      }

      return {'aging': aging};
    } catch (e) {
      print('Error fetching fine aging: $e');
      return {'aging': {}};
    }
  }
}
