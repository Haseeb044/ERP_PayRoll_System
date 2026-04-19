import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/models/financial_report_model.dart';
import '../../data/repositories/report_repository.dart';
import '../../utils/user_friendly_error.dart';

// Events
abstract class ReportEvent extends Equatable {
  const ReportEvent();
  @override
  List<Object> get props => [];
}

class LoadMonthlyReport extends ReportEvent {
  final DateTime month;
  const LoadMonthlyReport(this.month);
  @override
  List<Object> get props => [month];
}

class RefreshReport extends ReportEvent {}

// States
abstract class ReportState extends Equatable {
  const ReportState();
  @override
  List<Object> get props => [];
}

class ReportInitial extends ReportState {}
class ReportLoading extends ReportState {}

class ReportLoaded extends ReportState {
  final FinancialReportModel report;
  final DateTime month;

  const ReportLoaded({required this.report, required this.month});

  @override
  List<Object> get props => [report, month];
}

class ReportError extends ReportState {
  final String message;
  const ReportError(this.message);
  @override
  List<Object> get props => [message];
}

// Bloc
class ReportBloc extends Bloc<ReportEvent, ReportState> {
  final ReportRepository _repository;

  ReportBloc(this._repository) : super(ReportInitial()) {
    on<LoadMonthlyReport>(_onLoadMonthlyReport);
    on<RefreshReport>(_onRefreshReport);
  }

  double _asDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  Future<void> _onLoadMonthlyReport(
    LoadMonthlyReport event,
    Emitter<ReportState> emit,
  ) async {
    emit(ReportLoading());
    try {
      final data = await _repository.fetchReportSummary(event.month);
      final agingRes = await _repository.fetchFineAging();
      final Map<String, double> agingData = {};
      if (agingRes['aging'] != null) {
        Map<String, dynamic>.from(agingRes['aging'] as Map).forEach((key, value) {
          agingData[key] = (value as num).toDouble();
        });
      }

      final report = FinancialReportModel(
        totalRevenue: _asDouble(data['total_revenue']),
        totalExpense: _asDouble(data['total_expense']),
        netProfit: _asDouble(data['net_profit']),
        totalNetPay: _asDouble(data['total_net_pay']),
        totalCompanyExpense: _asDouble(data['company_expenses']),
        recoverableAmount: _asDouble(data['recoverable_amount']),
        recoverableJournals: _asDouble(data['recoverable_journals']),
        recoverableFines: _asDouble(data['recoverable_fines']),
        nonRecoverableExpense: _asDouble(data['non_recoverable_expense']),
        recoverableOutstanding: _asDouble(data['recoverable_outstanding']),
        recoverableCollected: _asDouble(data['recoverable_collected']),
        recoverableCreated: _asDouble(data['recoverable_created']),
        extraEarningsTotal: _asDouble(data['extra_earnings_total']),
        expenseBreakdown: (data['expense_breakdown'] as List).map((item) {
          final safeItem = Map<String, dynamic>.from(item as Map);
          final String label = safeItem['label'] ?? 'Other';
          return CategoryBreakdown(
            categoryName: label,
            amount: _asDouble(safeItem['amount']),
            color: _getCategoryColor(label),
          );
        }).toList(),
        extraEarningsBreakdown: (data['extra_earnings_breakdown'] as List? ?? const [])
            .map((item) {
          final safeItem = Map<String, dynamic>.from(item as Map);
          final String label = safeItem['label'] ?? 'Other';
          return CategoryBreakdown(
            categoryName: label,
            amount: _asDouble(safeItem['amount']),
            color: _getExtraEarningColor(label),
          );
        }).toList(),
        deductions: (data['deductions'] as List).map((item) {
          final safeItem = Map<String, dynamic>.from(item as Map);
          final String label = safeItem['label'] ?? '';
          return DeductionItem(
            label: label,
            amount: _asDouble(safeItem['amount']),
            count: (_asDouble(safeItem['count'])).toInt(),
            color: _getDeductionColor(label),
          );
        }).toList(),
        realTimeDeductions: (data['real_time_deductions'] as List?)?.map((item) => Map<String, dynamic>.from(item as Map)).toList() ?? [],
        agingData: agingData,
      );

      emit(ReportLoaded(report: report, month: event.month));
    } catch (e) {
      emit(ReportError(toUserFriendlyErrorMessage(e, fallback: 'Failed to load monthly report.')));
    }
  }

  Future<void> _onRefreshReport(
    RefreshReport event,
    Emitter<ReportState> emit,
  ) async {
    emit(ReportLoading());
    try {
      final data = await _repository.fetchReportSummary(DateTime.now());
      final report = FinancialReportModel(
        totalRevenue: _asDouble(data['total_revenue']),
        totalExpense: _asDouble(data['total_expense']),
        netProfit: _asDouble(data['net_profit']),
        totalNetPay: _asDouble(data['total_net_pay']),
        totalCompanyExpense: _asDouble(data['company_expenses']),
        recoverableAmount: _asDouble(data['recoverable_amount']),
        recoverableJournals: _asDouble(data['recoverable_journals']),
        recoverableFines: _asDouble(data['recoverable_fines']),
        nonRecoverableExpense:
            _asDouble(data['non_recoverable_expense']),
        recoverableOutstanding:
            _asDouble(data['recoverable_outstanding']),
        recoverableCollected:
            _asDouble(data['recoverable_collected']),
        recoverableCreated:
          _asDouble(data['recoverable_created']),
        extraEarningsTotal:
          _asDouble(data['extra_earnings_total']),
        expenseBreakdown: (data['expense_breakdown'] as List).map((item) {
          final safeItem = Map<String, dynamic>.from(item as Map);
          final String label = safeItem['label'] ?? 'Other';
          return CategoryBreakdown(
            categoryName: label,
            amount: _asDouble(safeItem['amount']),
            color: _getCategoryColor(label),
          );
        }).toList(),
        extraEarningsBreakdown: (data['extra_earnings_breakdown'] as List? ?? const [])
            .map((item) {
          final safeItem = Map<String, dynamic>.from(item as Map);
          final String label = safeItem['label'] ?? 'Other';
          return CategoryBreakdown(
            categoryName: label,
            amount: _asDouble(safeItem['amount']),
            color: _getExtraEarningColor(label),
          );
        }).toList(),
        deductions: (data['deductions'] as List).map((item) {
          final safeItem = Map<String, dynamic>.from(item as Map);
          final String label = safeItem['label'] ?? '';
          return DeductionItem(
            label: label,
            amount: _asDouble(safeItem['amount']),
            count: (_asDouble(safeItem['count'])).toInt(),
            color: _getDeductionColor(label),
          );
        }).toList(),
        agingData: {},
      );
      emit(ReportLoaded(report: report, month: DateTime.now()));
    } catch (e) {
      emit(ReportError(toUserFriendlyErrorMessage(e, fallback: 'Failed to refresh report.')));
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Fuel':
        return Colors.blue;
      case 'Maintenance':
        return Colors.orange;
      case 'Salaries':
        return Colors.green;
      case 'Insurance':
        return Colors.purple;
      case 'Platform Fee':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  Color _getDeductionColor(String label) {
    if (label.toLowerCase().contains("fine")) return Colors.orange;
    if (label.toLowerCase().contains("fuel")) return Colors.green;
    if (label.toLowerCase().contains("maint")) return Colors.blue;
    return Colors.grey;
  }

  Color _getExtraEarningColor(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('bonus')) return Colors.deepPurple;
    if (lower.contains('tip')) return Colors.teal;
    return Colors.indigo;
  }
}
