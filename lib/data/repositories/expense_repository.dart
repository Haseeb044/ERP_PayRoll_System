import '../models/expense_model.dart';
import '../models/expense_category_model.dart';

abstract class ExpenseRepository {
  Future<List<Expense>> fetchExpenses({String? createdByRole});
  Future<List<ExpenseCategoryModel>> fetchCategories();
  Future<void> createExpense(Expense expense);
  Future<void> updateExpenseStatus(String id, String status, {String? resolutionNotes});
  Future<void> deleteExpense(String id);
  Future<num?> fetchVatRateByCategory(String categoryId);
  Future<void> createExpenseWithActionItem(Expense expense, Map<String, dynamic> actionItem);
}
