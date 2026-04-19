import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/models/journal_model.dart';
import '../../data/models/payroll_model.dart';
import '../../data/repositories/journal_repository.dart';
import '../../data/models/user_model.dart';
import '../drawers/drawer_bloc.dart';
import '../actions/action_bloc.dart';
import '../financial/expense_bloc.dart';
import '../../utils/user_friendly_error.dart';

// Events
abstract class JournalEvent extends Equatable {
  const JournalEvent();
  @override
  List<Object?> get props => [];
}

class LoadJournals extends JournalEvent {
  final UserRole? role;
  final String? userId;
  final JournalStatus? status;
  const LoadJournals({this.role, this.userId, this.status});
  @override
  List<Object?> get props => [role, userId, status];
}

class CreateJournal extends JournalEvent {
  final JournalModel journal;
  const CreateJournal(this.journal);
  @override
  List<Object?> get props => [journal];
}

class CreateExpense extends JournalEvent {
  final JournalModel journal;
  const CreateExpense(this.journal);
  @override
  List<Object?> get props => [journal];
}

class ApproveJournal extends JournalEvent {
  final String id;
  final List<Map<String, dynamic>> lines;
  final String drawerId;
  final String paymentMethod;
  final bool isReceivable;
  final double? receivableAmount;
  final String? riderId;

  const ApproveJournal(
    this.id, {
    required this.lines,
    required this.drawerId,
    required this.paymentMethod,
    this.isReceivable = false,
    this.receivableAmount,
    this.riderId,
  });

  @override
  List<Object?> get props => [id, lines, drawerId, paymentMethod, isReceivable, receivableAmount, riderId];
}

class ReverseJournal extends JournalEvent {
  final String id;
  final String reason;
  const ReverseJournal(this.id, {required this.reason});
  @override
  List<Object?> get props => [id, reason];
}

class GeneratePayrollJournals extends JournalEvent {
  final List<PayslipDraftModel> drafts;
  final String platform;
  final DateTime month;

  const GeneratePayrollJournals({
    required this.drafts,
    required this.platform,
    required this.month,
  });

  @override
  List<Object?> get props => [drafts, platform, month];
}

// State
abstract class JournalState extends Equatable {
  const JournalState();
  @override
  List<Object?> get props => [];
}

class JournalInitial extends JournalState {}
class JournalLoading extends JournalState {}
class JournalLoaded extends JournalState {
  final List<JournalModel> journals;
  const JournalLoaded(this.journals);
  @override
  List<Object?> get props => [journals];
}
class JournalError extends JournalState {
  final String message;
  const JournalError(this.message);
  @override
  List<Object?> get props => [message];
}

class JournalSuccess extends JournalState {
  final String message;
  const JournalSuccess(this.message);
  @override
  List<Object?> get props => [message];
}

// Bloc
class JournalBloc extends Bloc<JournalEvent, JournalState> {
  final JournalRepository _repository;
  final DrawerBloc drawerBloc;
  final ActionBloc? actionBloc;
  final ExpenseBloc? expenseBloc;

  JournalBloc(
    this._repository, {
    required this.drawerBloc,
    this.actionBloc,
    this.expenseBloc,
  }) : super(JournalInitial()) {
    on<LoadJournals>(_onLoadJournals);
    on<CreateJournal>(_onCreateJournal);
    on<CreateExpense>(_onCreateExpense);
    on<ApproveJournal>(_onApproveJournal);
    on<ReverseJournal>(_onReverseJournal);
    on<GeneratePayrollJournals>(_onGeneratePayrollJournals);
  }

  Future<void> _onLoadJournals(LoadJournals event, Emitter<JournalState> emit) async {
    emit(JournalLoading());
    try {
      final journals = await _repository.fetchJournals(
        role: event.role,
        userId: event.userId,
        status: event.status,
      );
      emit(JournalLoaded(journals));
    } catch (e) {
      emit(JournalError(toUserFriendlyError(e)));
    }
  }

  Future<void> _onCreateJournal(CreateJournal event, Emitter<JournalState> emit) async {
    try {
      await _repository.createJournal(event.journal);
      add(LoadJournals(role: event.journal.createdByRole, userId: event.journal.createdByUserId));
    } catch (e) {
      emit(JournalError(toUserFriendlyError(e)));
    }
  }

  Future<void> _onCreateExpense(CreateExpense event, Emitter<JournalState> emit) async {
    try {
      await _repository.createJournal(event.journal);
      add(LoadJournals(role: event.journal.createdByRole, userId: event.journal.createdByUserId));
    } catch (e) {
      emit(JournalError(toUserFriendlyError(e)));
    }
  }

  Future<void> _onApproveJournal(ApproveJournal event, Emitter<JournalState> emit) async {
    try {
      await _repository.approveJournal(
        journalId: event.id,
        drawerId: event.drawerId,
        paymentMethod: event.paymentMethod,
        isReceivable: event.isReceivable,
        receivableAmount: event.receivableAmount,
        riderId: event.riderId,
        lines: event.lines,
      );
      
      drawerBloc.add(const LoadDrawers());
      actionBloc?.add(ScanSystem());
      expenseBloc?.add(const LoadExpenses());
      add(const LoadJournals());
      emit(const JournalSuccess("Journal approved successfully"));
    } catch (e) {
      emit(JournalError(toUserFriendlyError(e)));
    }
  }

  Future<void> _onReverseJournal(ReverseJournal event, Emitter<JournalState> emit) async {
    try {
      await _repository.reverseJournal(event.id, event.reason);
      drawerBloc.add(const LoadDrawers());
      add(const LoadJournals());
    } catch (e) {
      emit(JournalError(toUserFriendlyError(e)));
    }
  }

  Future<void> _onGeneratePayrollJournals(GeneratePayrollJournals event, Emitter<JournalState> emit) async {
    try {
      // Placeholder for actual generation logic
      emit(const JournalSuccess("Payroll journals generated"));
    } catch (e) {
      emit(JournalError(toUserFriendlyError(e)));
    }
  }
}
