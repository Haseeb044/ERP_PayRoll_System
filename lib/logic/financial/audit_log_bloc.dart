import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/models/audit_log_model.dart';
import '../../data/repositories/audit_log_repository.dart';
import '../../utils/user_friendly_error.dart';

// ─── Events ───────────────────────────────────────────────

abstract class AuditLogEvent extends Equatable {
  const AuditLogEvent();
  @override
  List<Object?> get props => [];
}

class LoadAuditLog extends AuditLogEvent {
  final String? tableName;
  final String? recordId;
  final int limit;

  const LoadAuditLog({this.tableName, this.recordId, this.limit = 200});

  @override
  List<Object?> get props => [tableName, recordId, limit];
}

class FilterAuditLogByTable extends AuditLogEvent {
  final String? tableName;
  const FilterAuditLogByTable(this.tableName);

  @override
  List<Object?> get props => [tableName];
}

// ─── States ───────────────────────────────────────────────

abstract class AuditLogState extends Equatable {
  const AuditLogState();
  @override
  List<Object?> get props => [];
}

class AuditLogInitial extends AuditLogState {}

class AuditLogLoading extends AuditLogState {}

class AuditLogLoaded extends AuditLogState {
  final List<AuditLogModel> entries;
  final String? selectedTable;

  const AuditLogLoaded(this.entries, {this.selectedTable});

  /// Distinct table names present in the loaded entries.
  List<String> get tableNames {
    final set = <String>{};
    for (final e in entries) {
      set.add(e.tableName);
    }
    final sorted = set.toList()..sort();
    return sorted;
  }

  @override
  List<Object?> get props => [entries, selectedTable];
}

class AuditLogError extends AuditLogState {
  final String message;
  const AuditLogError(this.message);

  @override
  List<Object> get props => [message];
}

// ─── Bloc ──────────────────────────────────────────────────

class AuditLogBloc extends Bloc<AuditLogEvent, AuditLogState> {
  final AuditLogRepository _repository;

  AuditLogBloc(this._repository) : super(AuditLogInitial()) {
    on<LoadAuditLog>(_onLoad);
    on<FilterAuditLogByTable>(_onFilterByTable);
  }

  Future<void> _onLoad(LoadAuditLog event, Emitter<AuditLogState> emit) async {
    emit(AuditLogLoading());
    try {
      final entries = await _repository.fetchLogs(
        tableName: event.tableName,
        recordId: event.recordId,
        limit: event.limit,
      );
      emit(AuditLogLoaded(entries, selectedTable: event.tableName));
    } catch (e) {
      emit(AuditLogError(toUserFriendlyError(e)));
    }
  }

  void _onFilterByTable(
    FilterAuditLogByTable event,
    Emitter<AuditLogState> emit,
  ) {
    // Re-dispatch LoadAuditLog with the selected table
    add(LoadAuditLog(tableName: event.tableName));
  }
}
