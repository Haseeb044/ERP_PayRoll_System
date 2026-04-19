import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/models/drawer_model.dart';
import '../../data/models/journal_model.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/drawer_repository.dart';
import '../../data/repositories/journal_repository.dart';
import '../../utils/user_friendly_error.dart';

// Events
abstract class DrawerEvent extends Equatable {
  const DrawerEvent();
  @override
  List<Object?> get props => [];
}

class LoadDrawers extends DrawerEvent {
  final String? filterDrawerId;
  const LoadDrawers({this.filterDrawerId});
  @override
  List<Object?> get props => [filterDrawerId];
}

class TransferFunds extends DrawerEvent {
  final String sourceDrawerId;
  final String targetDrawerId;
  final double amount;
  final String description;

  const TransferFunds({
    required this.sourceDrawerId,
    required this.targetDrawerId,
    required this.amount,
    required this.description,
  });

  @override
  List<Object> get props => [
    sourceDrawerId,
    targetDrawerId,
    amount,
    description,
  ];
}

class ProcessTransaction extends DrawerEvent {
  final String drawerId;
  final double amount;
  final String description;

  const ProcessTransaction({
    required this.drawerId,
    required this.amount,
    required this.description,
  });

  @override
  List<Object> get props => [drawerId, amount, description];
}

// States
abstract class DrawerState extends Equatable {
  const DrawerState();
  @override
  List<Object?> get props => [];
}

class DrawerInitial extends DrawerState {}

class DrawerLoading extends DrawerState {}

class DrawerLoaded extends DrawerState {
  final List<DrawerModel> drawers;
  final List<DrawerTransactionModel> transactions;
  final String? selectedDrawerId;

  const DrawerLoaded({
    required this.drawers,
    required this.transactions,
    this.selectedDrawerId,
  });

  @override
  List<Object?> get props => [drawers, transactions, selectedDrawerId];
}

class DrawerError extends DrawerState {
  final String message;
  const DrawerError(this.message);
  @override
  List<Object> get props => [message];
}

// Bloc
class DrawerBloc extends Bloc<DrawerEvent, DrawerState> {
  final DrawerRepository _repository;
  final JournalRepository _journalRepository;

  DrawerBloc(this._repository, this._journalRepository) : super(DrawerInitial()) {
    on<LoadDrawers>(_onLoadDrawers);
    on<TransferFunds>(_onTransferFunds);
    on<ProcessTransaction>(_onProcessTransaction);
  }

  Future<void> _onLoadDrawers(
    LoadDrawers event,
    Emitter<DrawerState> emit,
  ) async {
    emit(DrawerLoading());
    try {
      final drawers = await _repository.fetchDrawers();
      final transactions = await _repository.fetchTransactions(
        event.filterDrawerId,
      );

      emit(
        DrawerLoaded(
          drawers: drawers,
          transactions: transactions,
          selectedDrawerId: event.filterDrawerId,
        ),
      );
    } catch (e) {
      emit(DrawerError(toUserFriendlyError(e)));
    }
  }

  Future<void> _onTransferFunds(
    TransferFunds event,
    Emitter<DrawerState> emit,
  ) async {
    final currentState = state;
    if (currentState is DrawerLoaded) {
      emit(DrawerLoading());

      try {
        // Resolve target COA accounts
        String mapDrawerToAccount(String idOrUuid) {
          try {
            final drawer = currentState.drawers.firstWhere(
              (d) => d.id == idOrUuid,
            );
            if (drawer.type == DrawerType.bank ||
                drawer.name.toLowerCase().contains('bank'))
              return 'CASH-BANK';
            if (drawer.type == DrawerType.cash ||
                drawer.name.toLowerCase().contains('cash'))
              return 'CASH-MAIN';
            if (drawer.type == DrawerType.wallet ||
                drawer.name.toLowerCase().contains('noqodi'))
              return 'CASH-NOQODI';
          } catch (_) {}

          // Fallback for legacy IDs
          if (idOrUuid.toLowerCase().contains('bank') || idOrUuid == 'DR-002')
            return 'CASH-BANK';
          if (idOrUuid.toLowerCase().contains('petty_cash') ||
              idOrUuid.toLowerCase().contains('cash') ||
              idOrUuid == 'DR-001')
            return 'CASH-MAIN';
          if (idOrUuid.toLowerCase().contains('noqodi') || idOrUuid == 'DR-003')
            return 'CASH-NOQODI';
          return 'CASH-BANK'; // Fallback
        }

        final sourceAccountId = mapDrawerToAccount(event.sourceDrawerId);
        final targetAccountId = mapDrawerToAccount(event.targetDrawerId);

        String mapDrawerToPaymentMethod(String idOrUuid) {
          try {
            final drawer = currentState.drawers.firstWhere((d) => d.id == idOrUuid);
            if (drawer.type == DrawerType.wallet || drawer.name.toLowerCase().contains('noqodi')) {
              return 'wallet';
            }
            if (drawer.type == DrawerType.bank || drawer.name.toLowerCase().contains('bank')) {
              return 'bank_transfer';
            }
            return 'cash';
          } catch (_) {
            if (idOrUuid.toLowerCase().contains('noqodi') || idOrUuid == 'DR-003') {
              return 'wallet';
            }
            if (idOrUuid.toLowerCase().contains('bank') || idOrUuid == 'DR-002') {
              return 'bank_transfer';
            }
            return 'cash';
          }
        }

        final sourcePaymentMethod = mapDrawerToPaymentMethod(event.sourceDrawerId);

        // Create a journal for this transfer (journal-first accounting)
        final journal = JournalModel(
          id: '', // Backend generates UUID
          date: DateTime.now(),
          description: 'Transfer: ${event.description}',
          amount: event.amount,
          status: JournalStatus.posted, // Transfers are auto-posted
          type: JournalType.manualAdjustment,
          createdByRole: UserRole.accountant,
          paymentMethod: sourcePaymentMethod,
          drawerId: event.sourceDrawerId,
          entries: [
            JournalEntryModel(
              accountId: targetAccountId,
              debitAmount: event.amount,
            ),
            JournalEntryModel(
              accountId: sourceAccountId,
              creditAmount: event.amount,
            ),
          ],
        );

        await _journalRepository.createJournal(journal);
        await _repository.transferFunds(
          sourceDrawerId: event.sourceDrawerId,
          targetDrawerId: event.targetDrawerId,
          amount: event.amount,
          description: event.description,
        );

        // Reload UI state
        final drawers = await _repository.fetchDrawers();
        final transactions = await _repository.fetchTransactions(
          currentState.selectedDrawerId,
        );

        emit(
          DrawerLoaded(
            drawers: drawers,
            transactions: transactions,
            selectedDrawerId: currentState.selectedDrawerId,
          ),
        );
      } catch (e) {
        emit(DrawerError(toUserFriendlyError(e)));
        add(LoadDrawers(filterDrawerId: currentState.selectedDrawerId));
      }
    }
  }

  Future<void> _onProcessTransaction(
    ProcessTransaction event,
    Emitter<DrawerState> emit,
  ) async {
    final currentState = state;
    emit(DrawerLoading());

    try {
      // Create double-entry journal immediately instead of calling legacy API
      String mapDrawerToAccount(String idOrUuid) {
        try {
          // If state is DrawerLoaded, try to match by UUID
          if (currentState is DrawerLoaded) {
            final drawer = currentState.drawers.firstWhere(
              (d) => d.id == idOrUuid,
            );
            if (drawer.type == DrawerType.bank ||
                drawer.name.toLowerCase().contains('bank'))
              return 'CASH-BANK';
            if (drawer.type == DrawerType.cash ||
                drawer.name.toLowerCase().contains('cash'))
              return 'CASH-MAIN';
            if (drawer.type == DrawerType.wallet ||
                drawer.name.toLowerCase().contains('noqodi'))
              return 'CASH-NOQODI';
          }
        } catch (_) {}

        // Fallback for legacy IDs
        if (idOrUuid.toLowerCase().contains('bank') || idOrUuid == 'DR-002')
          return 'CASH-BANK';
        if (idOrUuid.toLowerCase().contains('petty_cash') ||
            idOrUuid.toLowerCase().contains('cash') ||
            idOrUuid == 'DR-001')
          return 'CASH-MAIN';
        if (idOrUuid.toLowerCase().contains('noqodi') || idOrUuid == 'DR-003')
          return 'CASH-NOQODI';
        return 'CASH-BANK'; // Fallback
      }

      final drawerAccountId = mapDrawerToAccount(event.drawerId);
      final isCredit = event.amount > 0;
      final absAmount = event.amount.abs();

      String mapDrawerToPaymentMethod(String idOrUuid) {
        try {
          if (currentState is DrawerLoaded) {
            final drawer = currentState.drawers.firstWhere((d) => d.id == idOrUuid);
            if (drawer.type == DrawerType.wallet || drawer.name.toLowerCase().contains('noqodi')) {
              return 'wallet';
            }
            if (drawer.type == DrawerType.bank || drawer.name.toLowerCase().contains('bank')) {
              return 'bank_transfer';
            }
            return 'cash';
          }
        } catch (_) {}

        if (idOrUuid.toLowerCase().contains('noqodi') || idOrUuid == 'DR-003') {
          return 'wallet';
        }
        if (idOrUuid.toLowerCase().contains('bank') || idOrUuid == 'DR-002') {
          return 'bank_transfer';
        }
        return 'cash';
      }

      final paymentMethod = mapDrawerToPaymentMethod(event.drawerId);

      // Determine counterpart (if credit -> money arriving -> debit cash, credit general revenue)
      // (if debit -> money leaving -> credit cash, debit general expense)
      final counterpartAccount = isCredit
          ? 'GENERAL-REVENUE'
          : 'GENERAL-EXPENSE';

      final journal = JournalModel(
        id: '',
        date: DateTime.now(),
        description: event.description,
        amount: absAmount,
        status: JournalStatus.posted,
        type: JournalType.manualAdjustment,
        createdByRole: UserRole.accountant,
        paymentMethod: paymentMethod,
        drawerId: event.drawerId,
        entries: [
          JournalEntryModel(
            accountId: isCredit ? drawerAccountId : counterpartAccount,
            debitAmount: absAmount,
          ),
          JournalEntryModel(
            accountId: isCredit ? counterpartAccount : drawerAccountId,
            creditAmount: absAmount,
          ),
        ],
      );

      await _journalRepository.createJournal(journal);
      await _repository.addTransaction(
        DrawerTransactionModel(
          id: '',
          drawerId: event.drawerId,
          amount: absAmount,
          isCredit: isCredit,
          description: event.description,
          date: DateTime.now(),
        ),
      );

      // Refresh data
      final drawers = await _repository.fetchDrawers();
      String? filterId;
      if (currentState is DrawerLoaded) {
        filterId = currentState.selectedDrawerId;
      }

      final transactions = await _repository.fetchTransactions(filterId);

      emit(
        DrawerLoaded(
          drawers: drawers,
          transactions: transactions,
          selectedDrawerId: filterId,
        ),
      );
    } catch (e) {
      emit(DrawerError(toUserFriendlyError(e)));
      if (currentState is DrawerLoaded) {
        add(LoadDrawers(filterDrawerId: currentState.selectedDrawerId));
      } else {
        add(const LoadDrawers());
      }
    }
  }
}
