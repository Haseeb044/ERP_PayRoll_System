import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/models/expense_model.dart';
import '../../data/models/expense_category_model.dart';
import '../../data/repositories/expense_repository.dart';
import '../../utils/user_friendly_error.dart';

// Events
abstract class ExpenseEvent extends Equatable {
  const ExpenseEvent();
  @override
  List<Object?> get props => [];
}

class LoadExpenses extends ExpenseEvent {
  final String? createdByRole;
  const LoadExpenses({this.createdByRole});

  @override
  List<Object?> get props => [createdByRole];
}

class LoadCategories extends ExpenseEvent {
  const LoadCategories();
}

class UpdateExpenseStatus extends ExpenseEvent {
  final String id;
  final String status;
  final String? reason;
  const UpdateExpenseStatus({required this.id, required this.status, this.reason});
  @override
  List<Object?> get props => [id, status, reason];
}

class CreateExpense extends ExpenseEvent {
  final Expense expense;
  const CreateExpense(this.expense);
  @override
  List<Object> get props => [expense];
}

class DeleteExpense extends ExpenseEvent {
  final String id;
  const DeleteExpense(this.id);
  @override
  List<Object> get props => [id];
}

class CreateExpenseWithAction extends ExpenseEvent {
  final Expense expense;
  final Map<String, dynamic> actionItem;
  const CreateExpenseWithAction({required this.expense, required this.actionItem});
  @override
  List<Object> get props => [expense, actionItem];
}

// States
abstract class ExpenseState extends Equatable {
  const ExpenseState();
  @override
  List<Object?> get props => [];
}

class ExpenseInitial extends ExpenseState {}

class ExpenseLoading extends ExpenseState {
  final List<ExpenseCategoryModel> categories;
  const ExpenseLoading({this.categories = const []});

  @override
  List<Object?> get props => [categories];
}

class ExpenseLoaded extends ExpenseState {
  final List<Expense> expenses;
  final List<ExpenseCategoryModel> categories;

  const ExpenseLoaded(this.expenses, {this.categories = const []});

  @override
  List<Object> get props => [expenses, categories];
}

class ExpenseError extends ExpenseState {
  final String message;
  const ExpenseError(this.message);
  @override
  List<Object> get props => [message];
}

// Bloc
class ExpenseBloc extends Bloc<ExpenseEvent, ExpenseState> {
  final ExpenseRepository _repository;

  ExpenseBloc(this._repository) : super(ExpenseInitial()) {
    on<LoadExpenses>(_onLoadExpenses);
    on<LoadCategories>(_onLoadCategories);
    on<UpdateExpenseStatus>(_onUpdateExpenseStatus);
    on<CreateExpense>(_onCreateExpense);
    on<DeleteExpense>(_onDeleteExpense);
    on<CreateExpenseWithAction>(_onCreateExpenseWithAction);
  }

  Future<void> _onLoadExpenses(
    LoadExpenses event,
    Emitter<ExpenseState> emit,
  ) async {
    final List<ExpenseCategoryModel> currentCategories = 
        state is ExpenseLoaded ? (state as ExpenseLoaded).categories : [];
        
    emit(ExpenseLoading(categories: currentCategories));
    try {
      final expenses = await _repository.fetchExpenses(
        createdByRole: event.createdByRole,
      );
      emit(ExpenseLoaded(expenses, categories: currentCategories));
    } catch (e) {
      emit(ExpenseError(toUserFriendlyError(e)));
    }
  }

  Future<void> _onLoadCategories(
    LoadCategories event,
    Emitter<ExpenseState> emit,
  ) async {
    try {
      final categories = await _repository.fetchCategories();
      if (state is ExpenseLoaded) {
        emit(ExpenseLoaded((state as ExpenseLoaded).expenses, categories: categories));
      } else {
        // If not loaded yet, just update the categories placeholder if needed
        // but typically we load expenses first or concurrently.
        emit(ExpenseLoaded(const [], categories: categories));
      }
    } catch (e) {
      print("Warning: Failed to load expense categories: $e");
    }
  }

  Future<void> _onUpdateExpenseStatus(
    UpdateExpenseStatus event,
    Emitter<ExpenseState> emit,
  ) async {
    try {
      await _repository.updateExpenseStatus(event.id, event.status, resolutionNotes: event.reason);
      add(const LoadExpenses()); // Refresh list
    } catch (e) {
      emit(ExpenseError(toUserFriendlyError(e)));
    }
  }

  Future<void> _onCreateExpense(
    CreateExpense event,
    Emitter<ExpenseState> emit,
  ) async {
    try {
      await _repository.createExpense(event.expense);
      add(const LoadExpenses()); // Refresh list
    } catch (e) {
      emit(ExpenseError(toUserFriendlyError(e)));
    }
  }

  Future<void> _onDeleteExpense(
    DeleteExpense event,
    Emitter<ExpenseState> emit,
  ) async {
    try {
      await _repository.deleteExpense(event.id);
      add(const LoadExpenses()); // Refresh list
    } catch (e) {
      emit(ExpenseError(toUserFriendlyError(e)));
    }
  }

  Future<void> _onCreateExpenseWithAction(
    CreateExpenseWithAction event,
    Emitter<ExpenseState> emit,
  ) async {
    try {
      await _repository.createExpenseWithActionItem(event.expense, event.actionItem);
      add(const LoadExpenses()); // Refresh list
    } catch (e) {
      emit(ExpenseError(toUserFriendlyError(e)));
    }
  }
}
