import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/models/action_item_model.dart';
import '../../data/models/fines_model.dart';

import '../../logic/fines/fines_bloc.dart';
import '../../logic/financial/expense_bloc.dart';
import '../../logic/auth/auth_bloc.dart';
import '../../data/repositories/action_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Events
abstract class ActionEvent extends Equatable {
  const ActionEvent();
  @override
  List<Object> get props => [];
}

class ScanSystem extends ActionEvent {}

class DismissAction extends ActionEvent {
  final String id;
  const DismissAction(this.id);
  @override
  List<Object> get props => [id];
}

// States
abstract class ActionState extends Equatable {
  const ActionState();
  @override
  List<Object> get props => [];
}

class ActionInitial extends ActionState {}

class ActionLoading extends ActionState {}

class ActionLoaded extends ActionState {
  final List<ActionItemModel> actions;
  const ActionLoaded(this.actions);
  @override
  List<Object> get props => [actions];
}

// Bloc
class ActionBloc extends Bloc<ActionEvent, ActionState> {
  final ActionRepository repository;
  final FinesBloc finesBloc;
  final ExpenseBloc expenseBloc;
  final AuthBloc authBloc;
  StreamSubscription? _finesSubscription;
  StreamSubscription? _expenseSubscription;
  StreamSubscription? _authSubscription;
  RealtimeChannel? _actionItemsChannel;
  Timer? _scanTimer;

  // Realtime websocket can be noisy/unstable on some desktop setups.
  // Keep it opt-in and rely on periodic refresh by default.
  static const bool _enableActionRealtime = bool.fromEnvironment(
    'ENABLE_ACTION_REALTIME',
    defaultValue: false,
  );

  String? _responsibleRole;

  ActionBloc({
    required this.repository,
    required this.finesBloc,
    required this.expenseBloc,
    required this.authBloc,
  }) : super(ActionInitial()) {
    on<ScanSystem>(_onScanSystem);
    on<DismissAction>(_onDismissAction);

    // Initial Scan
    add(ScanSystem());

    // Listen to Fines changes
    _finesSubscription = finesBloc.stream.listen((state) {
      add(ScanSystem());
    });

    // Listen to Expense changes
    _expenseSubscription = expenseBloc.stream.listen((state) {
      add(ScanSystem());
    });

    // Watch auth state so we can filter action_items by responsible role
    _authSubscription = authBloc.stream.listen((state) {
      if (state is AuthAuthenticated) {
        _responsibleRole = state.user.role.name;
      } else {
        _responsibleRole = null;
      }
      add(ScanSystem());
    });

    // Periodic fallback scan keeps action list current even when realtime is disabled.
    _scanTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      add(ScanSystem());
    });

    if (_enableActionRealtime) {
      _actionItemsChannel = Supabase.instance.client
          .channel('action_items_changes')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'action_items',
            callback: (payload) {
              add(ScanSystem());
            },
          )
          .subscribe();
    }
  }

  Future<void> _onScanSystem(
    ScanSystem event,
    Emitter<ActionState> emit,
  ) async {
    emit(ActionLoading());
    final actions = <ActionItemModel>[];
    final now = DateTime.now();
    final window24h = now.subtract(const Duration(hours: 24));

    // 0. Fetch dismissed actions (if any persistent logic exists)
    List<String> dismissedIds = [];
    try {
      dismissedIds = await repository.fetchDismissedActionIds();
    } catch (e) {
      print("Failed to fetch dismissals: $e");
    }

    // 1. Scan Fines from FinesBloc state (Unmatched in last 24h)
    final finesList = finesBloc.state.fines;
    final recentUnmatchedFines = finesList.where((f) {
      return f.status == FineStatus.unmatched &&
          f.violationDate.isAfter(window24h);
    }).toList();

    for (var fine in recentUnmatchedFines) {
      final String actionId = 'ACT-FINE-${fine.id}';
      if (!dismissedIds.contains(actionId)) {
        actions.add(
          ActionItemModel(
            id: actionId,
            type: ActionType.fine_unmatched,
            title: 'Unmatched Fine: ${fine.plateNumber}',
            subtitle: '${fine.ticketNumber} • ${fine.amount} AED',
            severity: ActionSeverity.blocker,
            route: '/fines',
            argumentId: fine.id,
          ),
        );
      }
    }

    // (Legacy expense-derived synthetic actions removed.)

    // 3. Fetch DB-driven action items from Supabase (Repository Direct)
    try {
      final dbActions = await repository.fetchActionItems(responsibleRole: _responsibleRole);
      for (var item in dbActions) {
        if (!dismissedIds.contains(item.id)) {
          if (!actions.any((a) => a.id == item.id)) {
            actions.add(item);
          }
        }
      }
    } catch (e) {
      print("Failed to fetch action items from repository: $e");
    }

    emit(ActionLoaded(actions));
  }

  Future<void> _onDismissAction(
    DismissAction event,
    Emitter<ActionState> emit,
  ) async {
    final currentState = state;
    if (currentState is ActionLoaded) {
      // 1. Optimistic UI update
      final updatedList = currentState.actions
          .where((a) => a.id != event.id)
          .toList();
      emit(ActionLoaded(updatedList));

      // 2. Persist to repository
      try {
        await repository.dismissAction(event.id);
      } catch (e) {
        print("Failed to persist action dismissal: $e");
      }
    }
  }

  @override
  Future<void> close() {
    _scanTimer?.cancel();
    _finesSubscription?.cancel();
    _expenseSubscription?.cancel();
    _authSubscription?.cancel();
    try {
      _actionItemsChannel?.unsubscribe();
    } catch (_) {}
    return super.close();
  }
}
