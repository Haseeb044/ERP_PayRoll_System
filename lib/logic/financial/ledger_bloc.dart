import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/models/ledger_entry_model.dart';
import '../../data/repositories/ledger_repository.dart';
import '../../utils/user_friendly_error.dart';

// --- Events ---

abstract class LedgerEvent extends Equatable {
  const LedgerEvent();
  @override
  List<Object?> get props => [];
}

class LoadLedger extends LedgerEvent {
  final String? account;
  final String? fromDate;
  final String? toDate;

  const LoadLedger({this.account, this.fromDate, this.toDate});

  @override
  List<Object?> get props => [account, fromDate, toDate];
}

class LoadLedgerSummary extends LedgerEvent {}

class LoadLedgerAccounts extends LedgerEvent {}

class FilterLedgerByAccount extends LedgerEvent {
  final String? account;
  const FilterLedgerByAccount(this.account);

  @override
  List<Object?> get props => [account];
}

class FilterLedgerByDateRange extends LedgerEvent {
  final String? fromDate;
  final String? toDate;
  const FilterLedgerByDateRange({this.fromDate, this.toDate});

  @override
  List<Object?> get props => [fromDate, toDate];
}

class LoadRiderStatement extends LedgerEvent {
  final String riderId;
  const LoadRiderStatement(this.riderId);

  @override
  List<Object?> get props => [riderId];
}

// --- States ---

abstract class LedgerState extends Equatable {
  const LedgerState();
  @override
  List<Object?> get props => [];
}

class LedgerInitial extends LedgerState {}

class LedgerLoading extends LedgerState {}

class LedgerLoaded extends LedgerState {
  final List<LedgerEntryModel> entries;
  final List<Map<String, dynamic>> summary;
  final List<Map<String, String>> accounts;
  final String? selectedAccount;
  final String? fromDate;
  final String? toDate;
  final List<LedgerEntryModel> riderEntries;
  final String? selectedRiderId;

  const LedgerLoaded({
    required this.entries,
    this.summary = const [],
    this.accounts = const [],
    this.selectedAccount,
    this.fromDate,
    this.toDate,
    this.riderEntries = const [],
    this.selectedRiderId,
  });

  double get totalDebit => entries.fold(0.0, (sum, e) => sum + e.debit);

  double get totalCredit => entries.fold(0.0, (sum, e) => sum + e.credit);

  LedgerLoaded copyWith({
    List<LedgerEntryModel>? entries,
    List<Map<String, dynamic>>? summary,
    List<Map<String, String>>? accounts,
    String? selectedAccount,
    String? fromDate,
    String? toDate,
    bool clearAccount = false,
    List<LedgerEntryModel>? riderEntries,
    String? selectedRiderId,
  }) {
    return LedgerLoaded(
      entries: entries ?? this.entries,
      summary: summary ?? this.summary,
      accounts: accounts ?? this.accounts,
      selectedAccount: clearAccount
          ? null
          : (selectedAccount ?? this.selectedAccount),
      fromDate: fromDate ?? this.fromDate,
      toDate: toDate ?? this.toDate,
      riderEntries: riderEntries ?? this.riderEntries,
      selectedRiderId: selectedRiderId ?? this.selectedRiderId,
    );
  }

  @override
  List<Object?> get props => [
    entries,
    summary,
    accounts,
    selectedAccount,
    fromDate,
    toDate,
    riderEntries,
    selectedRiderId,
  ];
}

class LedgerError extends LedgerState {
  final String message;
  const LedgerError(this.message);

  @override
  List<Object?> get props => [message];
}

// --- Bloc ---

class LedgerBloc extends Bloc<LedgerEvent, LedgerState> {
  final LedgerRepository _repository;

  LedgerBloc(this._repository) : super(LedgerInitial()) {
    on<LoadLedger>(_onLoadLedger);
    on<LoadLedgerSummary>(_onLoadSummary);
    on<LoadLedgerAccounts>(_onLoadAccounts);
    on<FilterLedgerByAccount>(_onFilterByAccount);
    on<FilterLedgerByDateRange>(_onFilterByDateRange);
    on<LoadRiderStatement>(_onLoadRiderStatement);
  }

  Future<void> _onLoadLedger(
    LoadLedger event,
    Emitter<LedgerState> emit,
  ) async {
    emit(LedgerLoading());
    try {
      final results = await Future.wait([
        _repository.fetchEntries(
          account: event.account,
          fromDate: event.fromDate,
          toDate: event.toDate,
        ),
        _repository.fetchSummary(),
        _repository.fetchAccounts(),
      ]);

      final entries = results[0] as List<LedgerEntryModel>;
      final summary = results[1] as List<Map<String, dynamic>>;
      final accounts = results[2] as List<Map<String, String>>;

      emit(
        LedgerLoaded(
          entries: entries,
          summary: summary,
          accounts: accounts,
          selectedAccount: event.account,
          fromDate: event.fromDate,
          toDate: event.toDate,
        ),
      );
    } catch (e) {
      emit(LedgerError(toUserFriendlyError(e)));
    }
  }

  Future<void> _onLoadSummary(
    LoadLedgerSummary event,
    Emitter<LedgerState> emit,
  ) async {
    final current = state;
    try {
      final summary = await _repository.fetchSummary();
      if (current is LedgerLoaded) {
        emit(current.copyWith(summary: summary));
      }
    } catch (_) {
      // Keep current state on summary refresh failure
    }
  }

  Future<void> _onLoadAccounts(
    LoadLedgerAccounts event,
    Emitter<LedgerState> emit,
  ) async {
    final current = state;
    try {
      final accounts = await _repository.fetchAccounts();
      if (current is LedgerLoaded) {
        emit(current.copyWith(accounts: accounts));
      }
    } catch (_) {}
  }

  Future<void> _onFilterByAccount(
    FilterLedgerByAccount event,
    Emitter<LedgerState> emit,
  ) async {
    final current = state;
    if (current is LedgerLoaded) {
      add(
        LoadLedger(
          account: event.account,
          fromDate: current.fromDate,
          toDate: current.toDate,
        ),
      );
    }
  }

  Future<void> _onFilterByDateRange(
    FilterLedgerByDateRange event,
    Emitter<LedgerState> emit,
  ) async {
    final current = state;
    if (current is LedgerLoaded) {
      add(
        LoadLedger(
          account: current.selectedAccount,
          fromDate: event.fromDate,
          toDate: event.toDate,
        ),
      );
    }
  }

  Future<void> _onLoadRiderStatement(
    LoadRiderStatement event,
    Emitter<LedgerState> emit,
  ) async {
    final current = state;
    if (current is LedgerLoaded) {
      // Don't emit loading for the whole page, just update the statement part
      // Alternatively, we could add a specific loading state for the statement
      try {
        final riderEntries = await _repository.fetchRiderStatement(event.riderId);
        emit(current.copyWith(
          riderEntries: riderEntries,
          selectedRiderId: event.riderId,
        ));
      } catch (e) {
        emit(LedgerError(toUserFriendlyError(e)));
      }
    } else {
        // If not loaded at all, we initially load the ledger as well
        emit(LedgerLoading());
        try {
            final riderEntries = await _repository.fetchRiderStatement(event.riderId);
            final accounts = await _repository.fetchAccounts();
            emit(LedgerLoaded(
                entries: const [],
                accounts: accounts,
                riderEntries: riderEntries,
                selectedRiderId: event.riderId,
            ));
        } catch(e) {
          emit(LedgerError(toUserFriendlyError(e)));
        }
    }
  }
}
