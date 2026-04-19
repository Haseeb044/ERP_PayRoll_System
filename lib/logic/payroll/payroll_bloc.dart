import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/payslip_item_model.dart';
import '../../data/models/payroll_model.dart';
import 'dart:io';
import '../../services/excel_service.dart';
import '../../data/models/payroll_upload_response.dart';
import 'package:intl/intl.dart';
import '../../data/repositories/payroll_repository.dart';
import '../../data/repositories/rider_repository.dart';
import '../../utils/user_friendly_error.dart';

// Events
abstract class PayrollEvent extends Equatable {
  const PayrollEvent();
  @override
  List<Object?> get props => [];
}

class LoadPayrollHistory extends PayrollEvent {}

class LoadPayrollDrafts extends PayrollEvent {
  final String platform;
  final DateTime month;
  const LoadPayrollDrafts({required this.platform, required this.month});
  @override
  List<Object?> get props => [platform, month];
}

class UploadPayrollSheet extends PayrollEvent {
  final dynamic file;
  final String platform;
  final DateTime month;

  const UploadPayrollSheet({
    required this.file,
    required this.platform,
    required this.month,
  });

  @override
  List<Object?> get props => [file, platform, month];
}

class UpdateDraftDeduction extends PayrollEvent {
  final String payslipId;
  final double amount;

  const UpdateDraftDeduction(this.payslipId, this.amount);

  @override
  List<Object?> get props => [payslipId, amount];
}

class FinalizeBatch extends PayrollEvent {
  final String batchId;
  final List<PayslipDraftModel> drafts;
  final String platform;
  final DateTime month;
  final String? drawerId;

  const FinalizeBatch({
    required this.batchId,
    required this.drafts,
    required this.platform,
    required this.month,
    this.drawerId,
  });

  @override
  List<Object?> get props => [batchId, drafts, platform, month, drawerId];
}

class ResolveMismatch extends PayrollEvent {
  final String draftId;
  final String riderId;
  final String riderName;

  const ResolveMismatch({
    required this.draftId,
    required this.riderId,
    required this.riderName,
  });

  @override
  List<Object?> get props => [draftId, riderId, riderName];
}

class UpdatePayslipAdjustments extends PayrollEvent {
  final String payslipId;
  final List<PayslipItemModel> items;
  final double netSalary;

  const UpdatePayslipAdjustments({
    required this.payslipId,
    required this.items,
    required this.netSalary,
  });

  @override
  List<Object?> get props => [payslipId, items, netSalary];
}

class GenerateIndividualPayslip extends PayrollEvent {
  final String payslipId;
  final String drawerId;

  const GenerateIndividualPayslip({
    required this.payslipId,
    required this.drawerId,
  });

  @override
  List<Object?> get props => [payslipId, drawerId];
}

class SyncPayrollBatch extends PayrollEvent {
  final String batchId;
  const SyncPayrollBatch(this.batchId);
  @override
  List<Object?> get props => [batchId];
}

class CancelPayrollDraft extends PayrollEvent {}

// States
abstract class PayrollState extends Equatable {
  final List<PayrollBatchModel> history;
  final Map<String, List<PayslipDraftModel>>
  batchDetails; // { batchId: payslips }

  const PayrollState({this.history = const [], this.batchDetails = const {}});

  @override
  List<Object?> get props => [history, batchDetails];
}

class PayrollInitial extends PayrollState {
  const PayrollInitial({super.history, super.batchDetails});
}

class PayrollLoading extends PayrollState {
  const PayrollLoading({super.history, super.batchDetails});
}

class PayrollHistoryLoaded extends PayrollState {
  const PayrollHistoryLoaded(
    List<PayrollBatchModel> history, {
    Map<String, List<PayslipDraftModel>> batchDetails = const {},
  }) : super(history: history, batchDetails: batchDetails);
}

class SearchPayroll extends PayrollEvent {
  final String query;
  const SearchPayroll(this.query);
  @override
  List<Object?> get props => [query];
}

class LoadBatchPayslips extends PayrollEvent {
  final String batchId;
  const LoadBatchPayslips(this.batchId);
  @override
  List<Object?> get props => [batchId];
}

class PayrollDraftReady extends PayrollState {
  final List<PayslipDraftModel> drafts; // Displayed (filtered)
  final List<PayslipDraftModel> allDrafts; // Source of truth
  final String platform;
  final DateTime month;
  final String searchQuery;
  final String? batchId;
  final String? lastUploadMessage;
  final List<String> lastUploadErrorLogs;

  const PayrollDraftReady({
    required this.drafts,
    required this.allDrafts,
    required this.platform,
    required this.month,
    this.batchId,
    this.searchQuery = '',
    this.lastUploadMessage,
    this.lastUploadErrorLogs = const [],
    super.history,
    super.batchDetails,
  });

  PayrollDraftReady copyWith({
    List<PayslipDraftModel>? drafts,
    List<PayslipDraftModel>? allDrafts,
    String? platform,
    DateTime? month,
    String? batchId,
    String? searchQuery,
    String? lastUploadMessage,
    List<String>? lastUploadErrorLogs,
    List<PayrollBatchModel>? history,
    Map<String, List<PayslipDraftModel>>? batchDetails,
  }) {
    return PayrollDraftReady(
      drafts: drafts ?? this.drafts,
      allDrafts: allDrafts ?? this.allDrafts,
      platform: platform ?? this.platform,
      month: month ?? this.month,
      batchId: batchId ?? this.batchId,
      searchQuery: searchQuery ?? this.searchQuery,
      lastUploadMessage: lastUploadMessage ?? this.lastUploadMessage,
      lastUploadErrorLogs: lastUploadErrorLogs ?? this.lastUploadErrorLogs,
      history: history ?? this.history,
      batchDetails: batchDetails ?? this.batchDetails,
    );
  }

  @override
  List<Object?> get props => [
    drafts,
    allDrafts,
    platform,
    month,
    batchId,
    searchQuery,
    lastUploadMessage,
    lastUploadErrorLogs,
    history,
    batchDetails,
  ];
}

class PayrollSuccess extends PayrollState {
  final String message;
  const PayrollSuccess(this.message, {super.history, super.batchDetails});
  @override
  List<Object?> get props => [message, history, batchDetails];
}

class PayrollError extends PayrollState {
  final String message;
  const PayrollError(this.message, {super.history, super.batchDetails});
  @override
  List<Object?> get props => [message, history, batchDetails];
}

class PayrollUploadSuccessState extends PayrollState {
  final PayrollUploadResponse response;
  const PayrollUploadSuccessState(this.response, {super.history, super.batchDetails});
  @override
  List<Object?> get props => [response, history, batchDetails];
}

class LoadBatchDetails extends PayrollEvent {
  final String batchId;
  final String? uploadMessage;
  final List<String> uploadErrorLogs;

  const LoadBatchDetails(this.batchId, {this.uploadMessage, this.uploadErrorLogs = const []});
  @override
  List<Object?> get props => [batchId, uploadMessage, uploadErrorLogs];
}

// Bloc
class PayrollBloc extends Bloc<PayrollEvent, PayrollState> {
  final PayrollRepository _repository;
  // ignore: unused_field
  final RiderRepository _riderRepository;

  PayrollBloc(this._repository, this._riderRepository)
    : super(const PayrollInitial()) {
    on<LoadPayrollHistory>(_onLoadHistory);
    on<LoadPayrollDrafts>(_onLoadDrafts);
    on<UploadPayrollSheet>(_onUploadSheet);
    on<LoadBatchDetails>(_onLoadBatchDetails);
    on<UpdateDraftDeduction>(_onUpdateDeduction);
    on<FinalizeBatch>(_onFinalizeBatch);
    on<ResolveMismatch>(_onResolveMismatch);
    on<CancelPayrollDraft>(_onCancelDraft);
    on<SearchPayroll>(_onSearchPayroll);
    on<LoadBatchPayslips>(_onLoadBatchPayslips);
    on<UpdatePayslipAdjustments>(_onUpdateAdjustments);
    on<GenerateIndividualPayslip>(_onGenerateIndividual);
    on<SyncPayrollBatch>(_onSyncBatch);
  }

  Future<void> _onLoadHistory(
    LoadPayrollHistory event,
    Emitter<PayrollState> emit,
  ) async {
    emit(PayrollLoading(history: state.history, batchDetails: state.batchDetails));
    try {
      final history = await _repository.fetchPayrollHistory();
      emit(PayrollHistoryLoaded(history, batchDetails: state.batchDetails));
    } catch (e) {
      emit(
        PayrollError(
          toUserFriendlyErrorMessage(e, fallback: 'Failed to load payroll history.'),
          history: state.history,
          batchDetails: state.batchDetails,
        ),
      );
    }
  }

  Future<void> _onLoadDrafts(
    LoadPayrollDrafts event,
    Emitter<PayrollState> emit,
  ) async {
    try {
      emit(
        PayrollDraftReady(
          drafts: const [],
          allDrafts: const [],
          platform: event.platform,
          month: event.month,
          history: state.history,
        ),
      );
    } catch (e) {
      emit(
        PayrollError(
          toUserFriendlyErrorMessage(e, fallback: 'Failed to prepare payroll draft.'),
          history: state.history,
        ),
      );
    }
  }

  Future<void> _onUploadSheet(
    UploadPayrollSheet event,
    Emitter<PayrollState> emit,
  ) async {
    emit(PayrollLoading(history: state.history));
    await Future.delayed(const Duration(milliseconds: 300));

    try {
      File fileToParse;
      if (event.file is File) {
        fileToParse = event.file;
      } else {
        fileToParse = File(event.file.toString());
      }
      final rows = await ExcelService.instance.parsePayrollRows(fileToParse);
      final response = await _repository.uploadPayroll(
        DateFormat('yyyy-MM').format(event.month),
        event.platform,
        rows,
      );

      final history = await _repository.fetchPayrollHistory();
      
      emit(PayrollUploadSuccessState(response, history: history, batchDetails: state.batchDetails));
      
      if (response.batchId.isNotEmpty) {
        add(LoadBatchDetails(response.batchId, uploadMessage: response.message, uploadErrorLogs: response.errorLogs));
      } else {
        emit(PayrollError(response.message, history: history, batchDetails: state.batchDetails));
      }
    } catch (e) {
      if (e.toString().contains('uq_batch_month_platform') ||
          e.toString().contains('duplicate key value')) {
        emit(
          PayrollError(
            "A salary sheet for this month and platform has already been uploaded.",
            history: state.history,
            batchDetails: state.batchDetails,
          ),
        );
      } else {
        emit(
          PayrollError(
            toUserFriendlyErrorMessage(e, fallback: 'Failed to upload payroll sheet.'),
            history: state.history,
            batchDetails: state.batchDetails,
          ),
        );
      }
    }
  }

  Future<void> _onLoadBatchDetails(
    LoadBatchDetails event,
    Emitter<PayrollState> emit,
  ) async {
    emit(PayrollLoading(history: state.history, batchDetails: state.batchDetails));
    try {
      final response = await _repository.fetchPayslips(event.batchId);
      final rawPayslips = response['payslips'] as List<dynamic>;
      final batchData = response['batch'] as Map<String, dynamic>?;

      List<PayslipDraftModel> drafts = rawPayslips.map((dynamic item) {
        final p = item as Map<String, dynamic>;
        final rider = p['riders'];

        String rName = p['rider_name']?.toString() ?? 'Unknown';
        String rId = p['external_id']?.toString() ?? '';

        if (rider is Map) {
          rName = rider['name']?.toString() ?? rName;
          final pId = rider['rider_code']?.toString();
          if (pId != null && pId.isNotEmpty) {
            rId = pId;
          }
        }

        List<PayslipItemModel> items = (p['items'] as List<dynamic>?)
                ?.map((e) => PayslipItemModel.fromJson(e))
          .where((it) => it.amount.abs() > 0.0001)
                .toList() ??
            [];

        return PayslipDraftModel(
          id: p['id'].toString(),
          riderId: p['rider_id']?.toString(),
          batchId: p['batch_id']?.toString(),
          riderAliasId: p['rider_alias_id']?.toString(),
          riderName: rName,
          externalId: rId,
          grossSalary: (p['gross_salary'] as num? ?? 0.0).toDouble(),
          netSalary: (p['net_salary'] as num? ?? 0.0).toDouble(),
          totalExpenses: (p['total_expenses'] as num? ?? 0.0).toDouble(),
          totalFines: (p['total_fines'] as num? ?? 0.0).toDouble(),
          internalFines: (p['internal_fines'] as num? ?? 0.0).toDouble(),
          internalExpenses: (p['internal_expenses'] as num? ?? 0.0).toDouble(),
          platformDeductions: (p['platform_deductions'] as num? ?? 0.0)
              .toDouble(),
          otherDeductions: (p['other_deductions'] as num? ?? 0.0).toDouble(),
          arrears: (p['arears'] as num? ?? 0.0).toDouble(),
          tdsBonus: (p['tds_bonus'] as num? ?? 0.0).toDouble(),
          tips: (p['tips'] as num? ?? 0.0).toDouble(),
          codDeficit: (p['cod_deficit'] as num? ?? 0.0).toDouble(),
          clawbackDeduction: (p['clawback_deduction'] as num? ?? 0.0).toDouble(),
          foodCompensation: (p['food_compensation'] as num? ?? 0.0).toDouble(),
          items: items,
          status: p['status'] == 'finalized'
              ? PayslipDraftStatus.finalized
              : (p['status'] == 'matched' ||
                      p['status'] == 'Draft' ||
                      p['status'] == 'Processed')
                  ? PayslipDraftStatus.matched
                  : PayslipDraftStatus.error,
          errorReason: p['error_reason']?.toString(),
          onlineHours: (p['online_hours'] as num? ?? 0.0).toDouble(),
          orderCount: (p['order_count'] as num?)?.toInt() ?? 0,
          platform: batchData?['platform']?.toString(),
          reviewRequired: p['review_required'] == true,
          issueCodes: (p['issue_codes'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const [],
        );
      }).toList();

      final batchInfo = state.history.cast<PayrollBatchModel?>().firstWhere(
            (b) => b?.id == event.batchId,
            orElse: () => null,
          ) ??
          (batchData != null ? PayrollBatchModel.fromJson(batchData) : null);

      final updatedBatchDetails = Map<String, List<PayslipDraftModel>>.from(
        state.batchDetails,
      );
      updatedBatchDetails[event.batchId] = drafts;

      final updatedHistory = _mergeBatchIntoHistory(
        history: state.history,
        batchId: event.batchId,
        drafts: drafts,
        batchData: batchData,
      );

      emit(
        PayrollDraftReady(
          drafts: drafts,
          allDrafts: drafts,
          batchId: event.batchId,
          platform: batchInfo?.platform ?? "Payroll Run",
          month: batchInfo?.month ?? DateTime.now(),
          lastUploadMessage: event.uploadMessage,
          lastUploadErrorLogs: event.uploadErrorLogs,
          history: updatedHistory,
          batchDetails: updatedBatchDetails,
        ),
      );
    } catch (e) {
      emit(
        PayrollError(
          toUserFriendlyErrorMessage(e, fallback: 'Failed to load batch details.'),
          history: state.history,
          batchDetails: state.batchDetails,
        ),
      );
    }
  }

  void _onSearchPayroll(SearchPayroll event, Emitter<PayrollState> emit) {
    if (state is PayrollDraftReady) {
      final currentState = state as PayrollDraftReady;
      final query = event.query.toLowerCase();

      final filtered = currentState.allDrafts.where((draft) {
        return draft.riderName.toLowerCase().contains(query) ||
            draft.externalId.toLowerCase().contains(query);
      }).toList();

      emit(currentState.copyWith(drafts: filtered, searchQuery: event.query));
    }
  }

  void _onUpdateDeduction(
    UpdateDraftDeduction event,
    Emitter<PayrollState> emit,
  ) {
    if (state is PayrollDraftReady) {
      final currentState = state as PayrollDraftReady;

      final updatedAllDrafts = currentState.allDrafts.map((d) {
        if (d.id == event.payslipId) {
          List<PayslipItemModel> updatedItems = List.from(d.items);
          final index = updatedItems.indexWhere(
            (i) => i.label == 'Company Deduction',
          );

          if (index != -1) {
            updatedItems[index] = updatedItems[index].copyWith(
              amount: -event.amount,
            );
          } else {
            updatedItems.add(
              PayslipItemModel(
                label: 'Company Deduction',
                amount: -event.amount,
                type: PayslipItemType.deduction,
              ),
            );
          }

          final totalDeductions = updatedItems.fold(
            0.0,
            (sum, item) => sum + item.amount.abs(),
          );
          final newNetSalary = d.grossSalary - totalDeductions;

          return d.copyWith(items: updatedItems, netSalary: newNetSalary);
        }
        return d;
      }).toList();

      final query = currentState.searchQuery.toLowerCase();
      final filtered = updatedAllDrafts.where((draft) {
        return draft.riderName.toLowerCase().contains(query) ||
            draft.externalId.toLowerCase().contains(query);
      }).toList();

      emit(
        currentState.copyWith(drafts: filtered, allDrafts: updatedAllDrafts),
      );
    }
  }

  Future<void> _onResolveMismatch(
    ResolveMismatch event,
    Emitter<PayrollState> emit,
  ) async {
    if (state is PayrollDraftReady) {
      final currentState = state as PayrollDraftReady;
      emit(PayrollLoading(history: currentState.history));

      try {
        await Supabase.instance.client.from('payslips').update({
          'rider_id': event.riderId,
          'rider_name': event.riderName,
        }).eq('id', event.draftId);

        await _repository.recalculateDeductions(event.draftId, event.riderId);
        add(LoadBatchDetails(currentState.batchId!));
      } catch (e) {
        emit(
          PayrollError(
            toUserFriendlyErrorMessage(e, fallback: 'Failed to resolve rider mismatch.'),
            history: currentState.history,
            batchDetails: currentState.batchDetails,
          ),
        );
        emit(currentState);
      }
    }
  }

  Future<void> _onFinalizeBatch(
    FinalizeBatch event,
    Emitter<PayrollState> emit,
  ) async {
    if (state is! PayrollDraftReady) {
      emit(
        PayrollError(
          'Payroll draft is not ready for finalization. Please reload and try again.',
          history: state.history,
          batchDetails: state.batchDetails,
        ),
      );
      return;
    }

    final currentState = state as PayrollDraftReady;
    emit(
      PayrollLoading(
        history: currentState.history,
        batchDetails: currentState.batchDetails,
      ),
    );
    try {
      if (event.drawerId != null && event.drawerId!.isNotEmpty) {
        await _repository.finalizePayrollWithJournals(
          event.batchId,
          event.drawerId!,
        );
      } else {
        await _repository.finalizePayroll(
          event.drafts,
          event.platform,
          event.month,
          batchId: event.batchId,
        );
      }

      // Important: refresh history BEFORE emitting success
      final history = await _repository.fetchPayrollHistory();

      emit(
        PayrollSuccess(
          "Payroll finalized and posted successfully",
          history: history,
          batchDetails: currentState.batchDetails,
        ),
      );
    } catch (e) {
      final msg = _toUserFriendlyPayrollError(e.toString());
      emit(
        PayrollError(
          msg,
          history: currentState.history,
          batchDetails: currentState.batchDetails,
        ),
      );
      // Return to the previous draft state so the screen does not stay blocked on loading.
      emit(currentState);
    }
  }

  String _toUserFriendlyPayrollError(String raw) {
    final lower = raw.toLowerCase();

    if (lower.contains('insufficient funds') || lower.contains('insufficient balance')) {
      final detail = RegExp(r'Insufficient funds[^\\n\\r]*', caseSensitive: false)
          .firstMatch(raw)
          ?.group(0);
      if (detail != null && detail.isNotEmpty) {
        return detail;
      }
      return 'Insufficient wallet balance for payroll posting. Please top up the selected drawer and try again.';
    }

    if (lower.contains('failed to finalize batch')) {
      return 'Payroll could not be posted. Please check drawer balance and batch data, then retry.';
    }

    return 'Payroll posting failed. Please try again.';
  }

  Future<void> _onCancelDraft(
    CancelPayrollDraft event,
    Emitter<PayrollState> emit,
  ) async {
    emit(PayrollLoading(history: state.history, batchDetails: state.batchDetails));
    try {
      final history = await _repository.fetchPayrollHistory();
      emit(PayrollHistoryLoaded(history, batchDetails: state.batchDetails));
    } catch (e) {
      emit(
        PayrollError(
          toUserFriendlyErrorMessage(e, fallback: 'Failed to cancel draft view.'),
          history: state.history,
          batchDetails: state.batchDetails,
        ),
      );
    }
  }

  Future<void> _onLoadBatchPayslips(
    LoadBatchPayslips event,
    Emitter<PayrollState> emit,
  ) async {
    try {
      final response = await _repository.fetchPayslips(event.batchId);
      final rawPayslips = response['payslips'] as List<dynamic>;

      final List<PayslipDraftModel> drafts = rawPayslips.map((dynamic item) {
        final p = item as Map<String, dynamic>;
        return PayslipDraftModel.fromJson(p);
      }).toList();

      final updatedDetails = Map<String, List<PayslipDraftModel>>.from(
        state.batchDetails,
      );
      updatedDetails[event.batchId] = drafts;
      final updatedHistory = _mergeBatchIntoHistory(
        history: state.history,
        batchId: event.batchId,
        drafts: drafts,
      );

      if (state is PayrollHistoryLoaded) {
        emit(PayrollHistoryLoaded(updatedHistory, batchDetails: updatedDetails));
      } else if (state is PayrollDraftReady) {
        emit(
          (state as PayrollDraftReady).copyWith(
            history: updatedHistory,
            batchDetails: updatedDetails,
          ),
        );
      }
    } catch (e) {
      emit(
        PayrollError(
          toUserFriendlyErrorMessage(e, fallback: 'Failed to load payslips.'),
          history: state.history,
          batchDetails: state.batchDetails,
        ),
      );
    }
  }

  Future<void> _onUpdateAdjustments(
    UpdatePayslipAdjustments event,
    Emitter<PayrollState> emit,
  ) async {
    if (state is PayrollDraftReady) {
      final currentState = state as PayrollDraftReady;
      emit(PayrollLoading(history: currentState.history));
      try {
        await _repository.replacePayslipItems(
          payslipId: event.payslipId,
          items: event.items.map((e) => e.toJson()).toList(),
          reason: 'UI adjustment',
        );

        add(LoadBatchDetails(currentState.batchId!));
      } catch (e) {
        emit(
          PayrollError(
            toUserFriendlyErrorMessage(e, fallback: 'Failed to save adjustments.'),
            history: currentState.history,
            batchDetails: currentState.batchDetails,
          ),
        );
        emit(currentState);
      }
    }
  }

  Future<void> _onGenerateIndividual(
    GenerateIndividualPayslip event,
    Emitter<PayrollState> emit,
  ) async {
    if (state is PayrollDraftReady) {
      final currentState = state as PayrollDraftReady;
      emit(PayrollLoading(history: currentState.history));
      try {
        await _repository.finalizeIndividualPayslip(
          event.payslipId,
          event.drawerId,
        );
        add(LoadBatchDetails(currentState.batchId!));
      } catch (e) {
        emit(
          PayrollError(
            toUserFriendlyErrorMessage(e, fallback: 'Failed to generate payslip.'),
            history: currentState.history,
            batchDetails: currentState.batchDetails,
          ),
        );
        emit(currentState);
      }
    }
  }

  Future<void> _onSyncBatch(
    SyncPayrollBatch event,
    Emitter<PayrollState> emit,
  ) async {
    if (state is PayrollDraftReady) {
      final currentState = state as PayrollDraftReady;
      emit(
        PayrollLoading(
          history: currentState.history,
          batchDetails: state.batchDetails,
        ),
      );
      try {
        await _repository.syncBatch(event.batchId);
        add(LoadBatchDetails(event.batchId));
      } catch (e) {
        emit(
          PayrollError(
            toUserFriendlyErrorMessage(e, fallback: 'Failed to sync payroll batch.'),
            history: state.history,
            batchDetails: state.batchDetails,
          ),
        );
        emit(currentState);
      }
    }
  }

  List<PayrollBatchModel> _mergeBatchIntoHistory({
    required List<PayrollBatchModel> history,
    required String batchId,
    required List<PayslipDraftModel> drafts,
    Map<String, dynamic>? batchData,
  }) {
    final fullTotal = drafts.fold<double>(0.0, (sum, d) => sum + d.netSalary);
    final pendingTotal = drafts
        .where((d) => d.status != PayslipDraftStatus.finalized)
        .fold<double>(0.0, (sum, d) => sum + d.netSalary);
    final batchStatusRaw = batchData?['status']?.toString();
    final batchStatus = batchStatusRaw == null
        ? null
        : PayrollBatchStatus.values.firstWhere(
            (e) => e.toString().split('.').last == batchStatusRaw,
            orElse: () => PayrollBatchStatus.draft,
          );

    final updated = history.map((b) {
      if (b.id != batchId) {
        return b;
      }

      final allFinalized = drafts.isNotEmpty &&
          drafts.every((d) => d.status == PayslipDraftStatus.finalized);
      final nextStatus = batchStatus ??
          (b.status == PayrollBatchStatus.posted
              ? PayrollBatchStatus.posted
              : (allFinalized
                  ? PayrollBatchStatus.finalized
                  : PayrollBatchStatus.draft));

      return b.copyWith(
        totalAmount: nextStatus == PayrollBatchStatus.draft
            ? pendingTotal
            : fullTotal,
        status: nextStatus,
      );
    }).toList(growable: false);

    final exists = updated.any((b) => b.id == batchId);
    if (exists) {
      return updated;
    }

    String monthStr = (batchData?['month']?.toString() ?? '').trim();
    if (monthStr.length == 7 && monthStr.contains('-')) {
      monthStr = '$monthStr-01';
    }
    final parsedMonth =
        DateTime.tryParse(monthStr) ?? DateTime.now();
    final platformFromBatch = (batchData?['platform']?.toString() ?? '').trim();
    final platformFromDraft = drafts.isNotEmpty
        ? (drafts.first.platform ?? '').trim()
        : '';
    final inferredStatus = batchStatus ??
        (drafts.isNotEmpty &&
                drafts.every((d) => d.status == PayslipDraftStatus.finalized)
            ? PayrollBatchStatus.finalized
            : PayrollBatchStatus.draft);

    return [
      ...updated,
      PayrollBatchModel(
        id: batchId,
        month: parsedMonth,
        platform: platformFromBatch.isNotEmpty
            ? platformFromBatch
            : (platformFromDraft.isNotEmpty ? platformFromDraft : 'Payroll Run'),
        status: inferredStatus,
        totalAmount: inferredStatus == PayrollBatchStatus.draft
            ? pendingTotal
            : fullTotal,
      ),
    ];
  }
}
