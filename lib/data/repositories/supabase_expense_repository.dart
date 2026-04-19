import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/expense_model.dart';
import '../models/expense_category_model.dart';
import 'expense_repository.dart';

class SupabaseExpenseRepository implements ExpenseRepository {
  final SupabaseClient _client = Supabase.instance.client;

  @override
  Future<List<Expense>> fetchExpenses({String? createdByRole}) async {
    try {
      final currentUser = _client.auth.currentUser;
      if (currentUser == null) return [];

      var query = _client.from('expenses').select('*, riders(created_by_user_id), journals(created_by_user_id)');

      if (createdByRole == 'pro') {
        // PRO filtering per precise requirement
        final response = await query.eq('created_by_role', 'pro').order('created_at', ascending: false);
        return (response as List).map((e) => Expense.fromJson(e)).toList();
      } else if (createdByRole != null) {
        query = query.eq('created_by_role', createdByRole);
      }

      final response = await query.order('expense_date', ascending: false);
      return (response as List).map((e) => Expense.fromJson(e)).toList();
    } catch (e) {
      print("Error fetching expenses: $e");
      return [];
    }
  }

  @override
  Future<List<ExpenseCategoryModel>> fetchCategories() async {
    try {
      const allowed = {'expense', 'fine'};
      final response = await _client
          .from('expense_categories')
          .select()
          .eq('is_active', true)
          .order('name');
      final categories = (response as List)
          .map((e) => ExpenseCategoryModel.fromJson(e))
          .where((c) => allowed.contains(c.name.trim().toLowerCase()))
          .toList();

      final present = categories
          .map((c) => c.name.trim().toLowerCase())
          .toSet();

      if (!present.contains('expense')) {
        categories.add(
          const ExpenseCategoryModel(
            id: '',
            name: 'Expense',
            description: 'Fallback category when master row is missing',
          ),
        );
      }

      if (!present.contains('fine')) {
        categories.add(
          const ExpenseCategoryModel(
            id: '',
            name: 'Fine',
            description: 'Fallback category when master row is missing',
          ),
        );
      }

      categories.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return categories;
    } catch (e) {
      print("Error fetching expense categories: $e");
      return const [
        ExpenseCategoryModel(id: '', name: 'Expense'),
        ExpenseCategoryModel(id: '', name: 'Fine'),
      ];
    }
  }

  @override
  Future<void> createExpense(Expense expense) async {
    try {
      // Ensure we don't send the ID if it's null (let DB generate)
      final data = expense.toJson();
      if (data['id'] == null) data.remove('id');
      // Use dynamic status value, fallback to model default if needed
      data['status'] = expense.status ?? ExpenseStatusValues.pending;
      await _client.from('expenses').insert(data);
    } catch (e) {
      print("Error creating expense: $e");
      throw e;
    }
  }

  @override
  Future<void> updateExpenseStatus(String id, String status, {String? resolutionNotes}) async {
    try {
      // Only allow valid status values
      final allowed = ExpenseStatusValues.all;
      final safeStatus = status.toLowerCase();
      if (!allowed.contains(safeStatus)) {
        throw Exception('Invalid expense status: $status');
      }
      await _client.from('expenses').update({'status': safeStatus}).eq('id', id);

      // If there's an action_item related to this expense, mark it resolved when rejecting or approving
      if (safeStatus == ExpenseStatusValues.rejected || safeStatus == ExpenseStatusValues.approved) {
        try {
          final currentUserId = _client.auth.currentUser?.id;
          await _client.from('action_items').update({
            'resolved_by': currentUserId,
            'resolved_at': DateTime.now().toIso8601String(),
            'resolution_notes': resolutionNotes ?? (safeStatus == ExpenseStatusValues.rejected ? 'Rejected by accountant' : 'Resolved by accountant'),
          }).eq('reference_id', id);
        } catch (e) {
          print('Error updating related action_items for expense $id: $e');
          rethrow;
        }
      }
    } catch (e) {
      print("Error updating expense status: $e");
      throw e;
    }
  }

  @override
  Future<void> deleteExpense(String id) async {
    try {
      await _client.from('expenses').delete().eq('id', id);
    } catch (e) {
      print("Error deleting expense: $e");
      throw e;
    }
  }

  @override
  Future<num?> fetchVatRateByCategory(String categoryId) async {
    try {
      final response = await _client
          .from('journal_templates')
          .select('vat_rate')
          .eq('category_id', categoryId)
          .maybeSingle();
      if (response != null) {
        return response['vat_rate'] as num?;
      }
      return 0;
    } catch (e) {
      print("Error fetching VAT rate for category $categoryId: $e");
      return 0;
    }
  }

  @override
  Future<void> createExpenseWithActionItem(Expense expense, Map<String, dynamic> actionItem) async {
    try {
      // Step one: Insert expense and get back the generated ID
      final expenseData = expense.toJson();
      if (expenseData['id'] == null) expenseData.remove('id');
      expenseData['status'] = 'pending';
      expenseData['created_by_role'] = 'pro';
      
      final expenseResponse = await _client.from('expenses').insert(expenseData).select('id').single();
      final expenseId = expenseResponse['id'];

      // Step two: Insert action item referencing the new expense
      final aiData = Map<String, dynamic>.from(actionItem);
      aiData['reference_id'] = expenseId;
      await _client.from('action_items').insert(aiData);
    } catch (e) {
      print("Error in createExpenseWithActionItem: $e");
      throw e;
    }
  }
}
