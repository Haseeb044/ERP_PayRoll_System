import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/rider_model.dart';
import '../data/models/fines_model.dart';
import '../data/models/expense_model.dart';
import '../data/models/payroll_upload_response.dart';
import '../data/models/journal_model.dart';
import '../data/models/journal_template_model.dart';

class ApiService {
  static const String baseUrl = 'http://127.0.0.1:8000';

  // Singleton pattern
  static final ApiService _instance = ApiService._internal();
  static ApiService get instance => _instance;
  ApiService._internal();

  Map<String, String> get _headers {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Creates a new Rider in the backend and returns the UUID
  Future<String?> createRider(RiderModel rider) async {
    final url = Uri.parse('$baseUrl/riders');

    try {
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode(rider.toJson()),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = jsonDecode(response.body);
        if (body['rider'] != null &&
            (body['rider']['rider_id'] != null ||
                body['rider']['id'] != null)) {
          return (body['rider']['rider_id'] ?? body['rider']['id']).toString();
        }
        return null;
      } else {
        throw Exception('Failed to create rider: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error connecting to backend: $e');
    }
  }

  /// Creates a new Rider and an action item for Accountant review
  Future<String?> createRiderWithActionItem(RiderModel rider) async {
    final url = Uri.parse('$baseUrl/riders_with_action_item');

    try {
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode(rider.toJson()),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = jsonDecode(response.body);
        if (body['rider'] != null &&
            (body['rider']['rider_id'] != null ||
                body['rider']['id'] != null)) {
          return (body['rider']['rider_id'] ?? body['rider']['id']).toString();
        }
        return null;
      } else {
        throw Exception(
          'Failed to create rider with action item: ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Error connecting to backend: $e');
    }
  }

  /// Fetches list of Riders from backend
  Future<List<RiderModel>> getRiders() async {
    final url = Uri.parse('$baseUrl/riders');
    try {
      final response = await http.get(url, headers: _headers);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> ridersJson = data['riders'];
        return ridersJson.map((json) => RiderModel.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load riders: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching riders: $e');
    }
  }

  /// Fetches list of Fines from backend
  Future<List<FineModel>> getFines() async {
    final url = Uri.parse('$baseUrl/fines');
    try {
      final response = await http.get(url, headers: _headers);

      if (response.statusCode == 200) {
        final List<dynamic> body = jsonDecode(response.body);
        return body.map((dynamic item) => FineModel.fromJson(item)).toList();
      } else {
        throw Exception('Failed to load fines');
      }
    } catch (e) {
      throw Exception('Error fetching fines: $e');
    }
  }

  /// Assigns a platform ID to a rider
  Future<void> assignPlatform(
    String riderId,
    String platform,
    String platformId,
  ) async {
    final lowerPlatform = platform.toLowerCase();

    final url = Uri.parse('$baseUrl/riders/$riderId/assign-$lowerPlatform');
    final body = jsonEncode({'platform_id': platformId});

    try {
      final response = await http.post(url, headers: _headers, body: body);

      if (response.statusCode != 200) {
        throw Exception('Failed to assign platform: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error assigning platform: $e');
    }
  }

  /// Assigns a bike to a rider using the new endpoint
  Future<void> assignBike(String riderId, String bikePlate) async {
    final url = Uri.parse('$baseUrl/riders/$riderId/assign-bike');
    final body = jsonEncode({'bike_plate': bikePlate});

    try {
      final response = await http.post(url, headers: _headers, body: body);

      if (response.statusCode != 200) {
        print('Failed to assign bike $bikePlate to $riderId: ${response.body}');
      }
    } catch (e) {
      print('Error assigning bike: $e');
    }
  }

  /// Fetches all bikes from the database (for dropdown selection)
  Future<List<BikeModel>> fetchBikes() async {
    try {
      final response = await Supabase.instance.client
          .from('bikes')
          .select()
          .order('bike_id');
      return (response as List).map((e) => BikeModel.fromJson(e)).toList();
    } catch (e) {
      print('Error fetching bikes: $e');
      return [];
    }
  }

  /// Uploads dynamic Excel rows to the backend for automated schema mapping
  Future<Map<String, dynamic>> uploadDynamicExcel(
    List<Map<String, dynamic>> rows,
  ) async {
    final url = Uri.parse('$baseUrl/excel/upload-dynamic');
    final body = jsonEncode({'rows': rows});

    try {
      final response = await http.post(url, headers: _headers, body: body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to upload dynamic excel: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error uploading dynamic excel: $e');
    }
  }

  /// Fetches list of Bike Assignments from backend (Bypassing RLS)
  Future<List<BikeAssignmentModel>> fetchBikeAssignments() async {
    final url = Uri.parse('$baseUrl/bike-assignments');
    try {
      final response = await http.get(url, headers: _headers);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> assignmentsJson = data['assignments'];
        return assignmentsJson
            .map((json) => BikeAssignmentModel.fromJson(json))
            .toList();
      } else {
        throw Exception('Failed to load assignments: ${response.body}');
      }
    } catch (e) {
      print('Error fetching bike assignments: $e');
      throw Exception('Error fetching bike assignments: $e');
    }
  }

  /// Uploads a single fine to the backend for processing
  Future<void> uploadFine(FineModel fine) async {
    final url = Uri.parse('$baseUrl/fines/upload-single');

    final body = jsonEncode({
      "ticket_number": fine.ticketNumber,
      "plate_number": fine.plateNumber,
      "violation_date": fine.violationDate.toIso8601String().split(
        'T',
      )[0], // YYYY-MM-DD
      "violation_time":
          "${fine.violationDate.hour.toString().padLeft(2, '0')}:${fine.violationDate.minute.toString().padLeft(2, '0')}", // HH:MM
      "amount": fine.amount,
      "description": fine.description,
      "city": fine.city ?? "Dubai",
      if (fine.riderName != null) "rider_name": fine.riderName,
      if (fine.riderId != null) "rider_id": fine.riderId,
    });

    try {
      final response = await http.post(url, headers: _headers, body: body);

      if (response.statusCode != 200) {
        throw Exception('Failed to upload fine: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error uploading fine: $e');
    }
  }

  /// Assigns a fine to a rider manually
  Future<void> assignFineManual(String fineId, String riderId) async {
    final url = Uri.parse('$baseUrl/fines/$fineId/assign');
    final body = jsonEncode({'rider_id': riderId});

    try {
      final response = await http.put(url, headers: _headers, body: body);
      if (response.statusCode != 200) {
        throw Exception('Failed to assign fine: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error assigning fine: $e');
    }
  }

  /// Fetches the assignment record that justifies a match
  Future<Map<String, dynamic>> getFineAssignmentProof(String fineId) async {
    final url = Uri.parse('$baseUrl/fines/$fineId/assignment-proof');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to fetch assignment proof: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching assignment proof: $e');
    }
  }

  /// Updates the status of multiple fines (e.g., to 'Ready')
  Future<void> bulkUpdateFineStatus(List<String> ids, String status) async {
    final url = Uri.parse('$baseUrl/fines/bulk-status');
    final body = jsonEncode({'ids': ids, 'status': status});

    try {
      final response = await http.put(url, headers: _headers, body: body);
      if (response.statusCode != 200) {
        throw Exception('Failed to update fines status: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error updating fines status: $e');
    }
  }

  /// Updates the deduction amount for a fine
  Future<void> updateFineAmount(String fineId, double newAmount) async {
    try {
      await Supabase.instance.client
          .from('traffic_fines')
          .update({'amount': newAmount})
          .eq('id', fineId);
    } catch (e) {
      throw Exception('Error updating fine amount: $e');
    }
  }

  // --- Expenses ---

  /// Fetches list of Expenses from backend
  Future<List<Expense>> getExpenses({String? createdByRole}) async {
    Uri url = Uri.parse('$baseUrl/expenses');

    if (createdByRole != null && createdByRole.isNotEmpty) {
      url = Uri.parse('$baseUrl/expenses?created_by_role=$createdByRole');
    }

    try {
      final response = await http.get(url, headers: _headers);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> expensesJson = data['expenses'];
        return expensesJson.map((json) => Expense.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load expenses: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching expenses: $e');
    }
  }

  /// Creates a new Expense (Atomic PRO flow: creates expense + journal + action item)
  Future<void> createExpense(Expense expense) async {
    final url = Uri.parse('$baseUrl/expenses');

    final bodyMap = expense.toJson();
    bodyMap.remove('id');
    bodyMap.remove('rider_name');

    try {
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode(bodyMap),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to create expense: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error creating expense: $e');
    }
  }

  /// Deletes an Expense
  Future<void> deleteExpense(String id) async {
    final url = Uri.parse('$baseUrl/expenses/$id');
    try {
      final response = await http.delete(url, headers: _headers);

      if (response.statusCode != 200) {
        throw Exception('Failed to delete expense: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error deleting expense: $e');
    }
  }

  /// Updates the status of an Expense (Approved/Rejected)
  Future<void> updateExpenseStatus(String id, String status) async {
    final url = Uri.parse('$baseUrl/expenses/$id/status');
    final body = jsonEncode({'status': status});

    try {
      final response = await http.put(url, headers: _headers, body: body);

      if (response.statusCode != 200) {
        throw Exception('Failed to update expense status: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error updating expense status: $e');
    }
  }

  // --- Payroll ---

  /// Uploads payroll JSON to backend
  Future<PayrollUploadResponse> uploadPayroll(
    String month,
    String platform,
    List<Map<String, dynamic>> rows,
  ) async {
    final body = jsonEncode({
      "month": month,
      "platform": platform,
      "rows": rows,
    });

    try {
      // Preferred path: async upload + status polling.
      final asyncUrl = Uri.parse('$baseUrl/payroll/upload/async');
      final asyncResponse = await http.post(
        asyncUrl,
        headers: _headers,
        body: body,
      );

      if (asyncResponse.statusCode == 200 || asyncResponse.statusCode == 201) {
        final asyncData = Map<String, dynamic>.from(
          jsonDecode(asyncResponse.body),
        );
        final jobId = (asyncData['job_id'] ?? '').toString();
        if (jobId.isEmpty) {
          throw Exception('Async payroll upload did not return a job_id');
        }

        const pollInterval = Duration(milliseconds: 750);
        const maxPolls = 800; // ~10 minutes at ~0.75s intervals
        for (int i = 0; i < maxPolls; i++) {
          if (i > 0) {
            await Future.delayed(pollInterval);
          }

          final statusUrl = Uri.parse('$baseUrl/payroll/upload/status/$jobId');
          final statusRes = await http.get(statusUrl, headers: _headers);
          if (statusRes.statusCode != 200) {
            throw Exception('Failed to fetch upload status: ${statusRes.body}');
          }

          final statusData = Map<String, dynamic>.from(
            jsonDecode(statusRes.body),
          );
          final status = (statusData['status'] ?? '').toString().toLowerCase();

          if (status == 'completed') {
            final result = Map<String, dynamic>.from(
              statusData['result'] as Map<String, dynamic>? ?? const {},
            );
            return PayrollUploadResponse.fromJson(result);
          }

          if (status == 'failed') {
            final error = (statusData['error'] ?? 'Unknown upload error')
                .toString();
            throw Exception('Payroll upload failed: $error');
          }
        }

        throw Exception(
          'Payroll upload timed out while waiting for completion',
        );
      }

      // Fallback path for older backend that may not expose async endpoint.
      if (asyncResponse.statusCode == 404) {
        final syncUrl = Uri.parse('$baseUrl/payroll/upload');
        final syncResponse = await http.post(
          syncUrl,
          headers: _headers,
          body: body,
        );

        if (syncResponse.statusCode == 200) {
          return PayrollUploadResponse.fromJson(jsonDecode(syncResponse.body));
        }
        throw Exception('Failed to upload payroll: ${syncResponse.body}');
      }

      throw Exception('Failed to queue payroll upload: ${asyncResponse.body}');
    } catch (e) {
      throw Exception('Error uploading payroll: $e');
    }
  }

  /// Fetches payroll history (batches)
  Future<List<Map<String, dynamic>>> getPayrollHistory() async {
    final url = Uri.parse('$baseUrl/payroll/history');
    try {
      final response = await http.get(url, headers: _headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['batches']);
      } else {
        throw Exception('Failed to load payroll history: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching payroll history: $e');
    }
  }

  /// Fetches payslips for a specific batch
  Future<Map<String, dynamic>> getPayrollPayslips(String batchId) async {
    final url = Uri.parse('$baseUrl/payroll/batch/$batchId/payslips');
    try {
      final response = await http.get(url, headers: _headers);

      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      } else {
        throw Exception('Failed to load payslips: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching payslips: $e');
    }
  }

  /// Triggers a server-side sync of a payroll batch to include new deductions
  Future<Map<String, dynamic>> syncBatch(String batchId) async {
    final url = Uri.parse('$baseUrl/payroll/sync/batch/$batchId');
    try {
      final response = await http.post(url, headers: _headers);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to sync batch: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error syncing batch: $e');
    }
  }

  Future<Map<String, dynamic>> finalizePayrollBatch(
    String batchId,
    String drawerId, {
    String paymentMethod = 'bank_transfer',
  }) async {
    final url = Uri.parse('$baseUrl/payroll/batch/$batchId/finalize');
    final body = jsonEncode({
      'drawer_id': drawerId,
      'payment_method': paymentMethod,
    });
    try {
      final response = await http.post(url, headers: _headers, body: body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      throw Exception('Failed to finalize batch: ${response.body}');
    } catch (e) {
      throw Exception('Error finalizing batch: $e');
    }
  }

  Future<Map<String, dynamic>> editPayslipDeductionItem({
    required String payslipId,
    required int itemIndex,
    required double newAmount,
    String? expectedLabel,
    String? reason,
  }) async {
    final url = Uri.parse('$baseUrl/payroll/payslip/$payslipId/deduction');
    final body = jsonEncode({
      'item_index': itemIndex,
      'new_amount': newAmount,
      if (expectedLabel != null) 'expected_label': expectedLabel,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });

    try {
      final response = await http.patch(url, headers: _headers, body: body);
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      throw Exception('Failed to edit payslip deduction: ${response.body}');
    } catch (e) {
      throw Exception('Error editing payslip deduction: $e');
    }
  }

  Future<Map<String, dynamic>> replacePayslipItems({
    required String payslipId,
    required List<Map<String, dynamic>> items,
    String? reason,
  }) async {
    final url = Uri.parse('$baseUrl/payroll/payslip/$payslipId/items');
    final body = jsonEncode({
      'items': items,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });

    try {
      final response = await http.patch(url, headers: _headers, body: body);
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      throw Exception('Failed to replace payslip items: ${response.body}');
    } catch (e) {
      throw Exception('Error replacing payslip items: $e');
    }
  }

  Future<Map<String, dynamic>> getPayslipGroupedDeductions(
    String payslipId,
  ) async {
    final url = Uri.parse('$baseUrl/payroll/payslip/$payslipId/deductions');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      throw Exception('Failed to fetch grouped deductions: ${response.body}');
    } catch (e) {
      throw Exception('Error fetching grouped deductions: $e');
    }
  }

  Future<Map<String, dynamic>> getBatchFlaggedPayslips(String batchId) async {
    final url = Uri.parse('$baseUrl/payroll/batch/$batchId/flagged-payslips');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      throw Exception('Failed to fetch flagged payslips: ${response.body}');
    } catch (e) {
      throw Exception('Error fetching flagged payslips: $e');
    }
  }

  Future<Map<String, dynamic>> getBatchReviewSummary(String batchId) async {
    final url = Uri.parse('$baseUrl/payroll/batch/$batchId/review-summary');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      throw Exception('Failed to fetch review summary: ${response.body}');
    } catch (e) {
      throw Exception('Error fetching review summary: $e');
    }
  }

  Future<Map<String, dynamic>> getCarryForwardOptions(String riderId) async {
    final url = Uri.parse(
      '$baseUrl/payroll/rider/$riderId/carry-forward-options',
    );
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      throw Exception(
        'Failed to fetch carry-forward options: ${response.body}',
      );
    } catch (e) {
      throw Exception('Error fetching carry-forward options: $e');
    }
  }

  Future<Map<String, dynamic>> applyCarryForwardSelections(
    String payslipId,
    List<Map<String, dynamic>> selections,
  ) async {
    final url = Uri.parse(
      '$baseUrl/payroll/payslip/$payslipId/carry-forward/apply',
    );
    final body = jsonEncode({'selections': selections});
    try {
      final response = await http.post(url, headers: _headers, body: body);
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      throw Exception(
        'Failed to apply carry-forward selections: ${response.body}',
      );
    } catch (e) {
      throw Exception('Error applying carry-forward selections: $e');
    }
  }

  // --- Drawers & Transactions ---

  /// Fetches drawer balances summary
  Future<Map<String, dynamic>> getDrawerSummary() async {
    final url = Uri.parse('$baseUrl/drawer');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to fetch drawer summary: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching drawer summary: $e');
    }
  }

  /// Tops up a drawer from bank
  Future<void> topupDrawer(String targetType, double amount) async {
    final url = Uri.parse('$baseUrl/drawer/topup');
    final body = jsonEncode({'target_type': targetType, 'amount': amount});

    try {
      final response = await http.post(url, headers: _headers, body: body);
      if (response.statusCode != 200) {
        throw Exception('Failed to topup drawer: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error topping up drawer: $e');
    }
  }

  /// Creates a new transaction
  Future<void> createTransaction({
    required String riderId,
    required String fromDrawer,
    required double amount,
    required String reason,
  }) async {
    final url = Uri.parse('$baseUrl/transactions');
    final body = jsonEncode({
      'rider_id': riderId,
      'from_drawer': fromDrawer,
      'amount': amount,
      'reason': reason,
    });

    try {
      final response = await http.post(url, headers: _headers, body: body);
      if (response.statusCode != 200) {
        throw Exception('Failed to create transaction: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error creating transaction: $e');
    }
  }

  /// Lists transactions
  Future<List<dynamic>> listTransactions({String status = "pending"}) async {
    final url = Uri.parse('$baseUrl/transactions?status=$status');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['transactions'] as List<dynamic>;
      } else {
        throw Exception('Failed to list transactions: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error listing transactions: $e');
    }
  }

  /// Fetches financial report summary
  Future<Map<String, dynamic>> getReportSummary() async {
    final url = Uri.parse('$baseUrl/reports/summary');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to fetch report: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching report: $e');
    }
  }

  // --- Journals ---

  /// Fetches all journals (with nested journal_lines)
  Future<List<JournalModel>> getJournals() async {
    final url = Uri.parse('$baseUrl/journals');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> journalsJson = data['journals'];
        return journalsJson
            .map((json) => JournalModel.fromJson(json as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception('Failed to load journals: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching journals: $e');
    }
  }

  /// Creates a new journal with journal_lines
  Future<JournalModel> createJournal(JournalModel journal) async {
    final url = Uri.parse('$baseUrl/journals');
    try {
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode(journal.toJson()),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return JournalModel.fromJson(data['journal'] as Map<String, dynamic>);
      } else {
        throw Exception('Failed to create journal: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error creating journal: $e');
    }
  }

  /// Creates a new journal using a raw payload and returns full backend response.
  Future<Map<String, dynamic>> createJournalRaw(
    Map<String, dynamic> payload,
  ) async {
    final url = Uri.parse('$baseUrl/journals');
    try {
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      throw Exception('Failed to create journal: ${response.body}');
    } catch (e) {
      throw Exception('Error creating journal: $e');
    }
  }

  /// Approves a journal (Draft → Posted) with Accountant fields
  Future<void> approveJournal({
    required String journalId,
    required String drawerId,
    required String paymentMethod,
    bool isReceivable = false,
    double? receivableAmount,
    List<Map<String, dynamic>> lines = const [],
  }) async {
    final url = Uri.parse('$baseUrl/journals/$journalId/approve');

    final body = jsonEncode({
      'drawer_id': drawerId,
      'payment_method': paymentMethod,
      'is_receivable': isReceivable,
      if (receivableAmount != null) 'receivable_amount': receivableAmount,
      'lines': lines,
    });

    try {
      final response = await http.post(url, headers: _headers, body: body);
      if (response.statusCode != 200) {
        throw Exception('Failed to approve journal: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error approving journal: $e');
    }
  }

  /// Reverses a posted journal (Posted → Reversed) and creates a mirror entry
  Future<JournalModel?> reverseJournal(String journalId, String reason) async {
    final url = Uri.parse('$baseUrl/journals/$journalId/reverse');
    try {
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({'reason': reason}),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['journal'] != null) {
          return JournalModel.fromJson(data['journal'] as Map<String, dynamic>);
        }
        return null;
      } else {
        throw Exception('Failed to reverse journal: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error reversing journal: $e');
    }
  }

  /// Settles a posted vendor pay-later journal by creating a payment journal.
  Future<Map<String, dynamic>> payVendorJournal({
    required String journalId,
    required double amount,
    required String drawerId,
    required String paymentMethod,
    String? entryDate,
    String? description,
  }) async {
    final url = Uri.parse('$baseUrl/journals/$journalId/pay-vendor');
    final body = jsonEncode({
      'amount': amount,
      'drawer_id': drawerId,
      'payment_method': paymentMethod,
      if (entryDate != null) 'entry_date': entryDate,
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
    });

    try {
      final response = await http.post(url, headers: _headers, body: body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      throw Exception('Failed to pay vendor journal: ${response.body}');
    } catch (e) {
      throw Exception('Error paying vendor journal: $e');
    }
  }

  /// Fetches vendors from backend.
  Future<List<Map<String, dynamic>>> getVendors({
    String? search,
    String? status,
  }) async {
    final query = <String, String>{
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
    };
    final url = Uri.parse('$baseUrl/vendors').replace(queryParameters: query.isEmpty ? null : query);
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(response.body));
        final rows = (data['vendors'] as List<dynamic>? ?? const []);
        return rows
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      throw Exception('Failed to load vendors: ${response.body}');
    } catch (e) {
      throw Exception('Error fetching vendors: $e');
    }
  }

  /// Creates a vendor through backend.
  Future<Map<String, dynamic>> createVendor({
    required String name,
    String? phone,
    String? email,
    String? address,
    String? vatNo,
    bool vatApplicable = true,
    String status = 'active',
  }) async {
    final url = Uri.parse('$baseUrl/vendors');
    final body = jsonEncode({
      'name': name,
      'phone': phone,
      'email': email,
      'address': address,
      'vat_no': vatNo,
      'vat_applicable': vatApplicable,
      'status': status,
    });
    try {
      final response = await http.post(url, headers: _headers, body: body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      throw Exception('Failed to create vendor: ${response.body}');
    } catch (e) {
      throw Exception('Error creating vendor: $e');
    }
  }

  /// Fetches suppliers from backend.
  Future<List<Map<String, dynamic>>> getSuppliers({
    String? search,
    String? status,
  }) async {
    final query = <String, String>{
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
    };
    final url = Uri.parse('$baseUrl/suppliers').replace(queryParameters: query.isEmpty ? null : query);
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(response.body));
        final rows = (data['suppliers'] as List<dynamic>? ?? const []);
        return rows
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      throw Exception('Failed to load suppliers: ${response.body}');
    } catch (e) {
      throw Exception('Error fetching suppliers: $e');
    }
  }

  /// Creates a supplier through backend.
  Future<Map<String, dynamic>> createSupplier({
    required String name,
    String? phone,
    String? email,
    String? address,
    String status = 'active',
  }) async {
    final url = Uri.parse('$baseUrl/suppliers');
    final body = jsonEncode({
      'name': name,
      'phone': phone,
      'email': email,
      'address': address,
      'status': status,
    });
    try {
      final response = await http.post(url, headers: _headers, body: body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      throw Exception('Failed to create supplier: ${response.body}');
    } catch (e) {
      throw Exception('Error creating supplier: $e');
    }
  }

  /// Returns open credit summary for vendor.
  Future<Map<String, dynamic>> getVendorOpenCreditSummary(String vendorId) async {
    final url = Uri.parse('$baseUrl/vendors/$vendorId/open-credit-summary');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }
      throw Exception('Failed to fetch vendor open credit summary: ${response.body}');
    } catch (e) {
      throw Exception('Error fetching vendor open credit summary: $e');
    }
  }

  // --- Ledger ---

  // --- Journal Templates ---

  /// Fetches all journal templates
  Future<List<JournalTemplateModel>> getJournalTemplates() async {
    final url = Uri.parse('$baseUrl/journal-templates');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> templatesJson = data['templates'] ?? [];
        return templatesJson
            .map(
              (json) =>
                  JournalTemplateModel.fromJson(json as Map<String, dynamic>),
            )
            .toList();
      } else {
        throw Exception('Failed to load templates: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching templates: $e');
    }
  }

  /// Creates a new journal template
  Future<void> createJournalTemplate(JournalTemplateModel template) async {
    final url = Uri.parse('$baseUrl/journal-templates');
    try {
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode(template.toJson()),
      );
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to create template: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error creating template: $e');
    }
  }

  /// Deletes a journal template
  Future<void> deleteJournalTemplate(String id) async {
    final url = Uri.parse('$baseUrl/journal-templates/$id');
    try {
      final response = await http.delete(url, headers: _headers);
      if (response.statusCode != 200) {
        throw Exception('Failed to delete template: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error deleting template: $e');
    }
  }

  // --- Ledger Entries ---

  /// Fetches ledger entries with optional filters
  Future<List<dynamic>> getLedgerEntries({
    String? account,
    String? fromDate,
    String? toDate,
  }) async {
    final params = <String, String>{};
    if (account != null && account.isNotEmpty) params['account'] = account;
    if (fromDate != null && fromDate.isNotEmpty) params['from_date'] = fromDate;
    if (toDate != null && toDate.isNotEmpty) params['to_date'] = toDate;

    final uri = Uri.parse(
      '$baseUrl/ledger',
    ).replace(queryParameters: params.isNotEmpty ? params : null);
    try {
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['ledger'] ?? data['entries'] ?? []) as List<dynamic>;
      } else {
        throw Exception('Failed to load ledger: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching ledger: $e');
    }
  }

  // --- Actions Engine (Step 6) ---

  /// Permanently dismisses an action card using the backend tracking table
  Future<void> dismissAction(String actionId, {String? reason}) async {
    final url = Uri.parse('$baseUrl/actions/dismiss');
    try {
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'action_id': actionId,
          'reason': reason ?? "Dismissed by user",
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to dismiss action: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error dismissing action: $e');
    }
  }

  /// Retrieves the list of permanently dismissed action IDs
  Future<List<String>> getActionDismissals() async {
    final url = Uri.parse('$baseUrl/actions/dismissals');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['dismissed_action_ids'] as List<dynamic>? ?? [];
        return list.map((e) => e.toString()).toList();
      } else {
        throw Exception('Failed to load dismissals: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching dismissals: $e');
    }
  }

  /// Fetches DB-driven action items (e.g., journal_pending_approval)
  Future<List<Map<String, dynamic>>> getActionItems() async {
    final url = Uri.parse('$baseUrl/action-items');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['action_items'] as List<dynamic>? ?? [];
        return list.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Failed to load action items: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching action items: $e');
    }
  }

  /// Resolves an action item in the DB
  Future<void> resolveActionItem(String actionId) async {
    final url = Uri.parse('$baseUrl/action-items/$actionId/resolve');
    try {
      final response = await http.post(url, headers: _headers);
      if (response.statusCode != 200) {
        throw Exception('Failed to resolve action item: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error resolving action item: $e');
    }
  }

  /// Fetches distinct account names from ledger
  Future<List<String>> getLedgerAccounts() async {
    final url = Uri.parse('$baseUrl/ledger/accounts');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['accounts'] as List<dynamic>)
            .map((e) => e.toString())
            .toList();
      } else {
        throw Exception('Failed to fetch ledger accounts: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching ledger accounts: $e');
    }
  }

  /// Fetches trial balance summary (debit/credit totals per account)
  Future<List<dynamic>> getLedgerSummary() async {
    final url = Uri.parse('$baseUrl/ledger/summary');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['summary'] as List<dynamic>;
      } else {
        throw Exception('Failed to fetch ledger summary: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching ledger summary: $e');
    }
  }

  // --- Audit Log ---

  /// Fetches audit log entries
  Future<List<dynamic>> getAuditLog({
    String? tableName,
    String? recordId,
    int limit = 100,
  }) async {
    final params = <String, String>{};
    if (tableName != null) params['table_name'] = tableName;
    if (recordId != null) params['record_id'] = recordId;
    params['limit'] = limit.toString();

    final uri = Uri.parse(
      '$baseUrl/audit-log',
    ).replace(queryParameters: params);
    try {
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['audit_log'] as List<dynamic>;
      } else {
        throw Exception('Failed to fetch audit log: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching audit log: $e');
    }
  }

  // ─── Rider Aliases ───────────────────────────────────────

  /// Fetch all aliases for a rider (newest first).
  Future<List<dynamic>> getRiderAliases(String riderId) async {
    final url = Uri.parse('$baseUrl/riders/$riderId/aliases');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['aliases'] ?? [];
      } else {
        throw Exception('Failed to load aliases: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching rider aliases: $e');
    }
  }

  /// Create a new alias (auto-deactivates previous active on same platform).
  Future<Map<String, dynamic>?> createRiderAlias({
    required String riderId,
    required String platform,
    required String platformRiderId,
    String? validFrom,
  }) async {
    final url = Uri.parse('$baseUrl/riders/$riderId/aliases');
    try {
      final body = {
        'rider_id': riderId,
        'platform': platform,
        'platform_rider_id': platformRiderId,
      };
      if (validFrom != null) body['valid_from'] = validFrom;

      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['alias'];
      } else {
        throw Exception('Failed to create alias: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error creating rider alias: $e');
    }
  }

  /// Update an alias (e.g. set valid_to to deactivate).
  Future<Map<String, dynamic>?> updateRiderAlias({
    required String riderId,
    required String aliasId,
    String? platformRiderId,
    String? validFrom,
    String? validTo,
  }) async {
    final url = Uri.parse('$baseUrl/riders/$riderId/aliases/$aliasId');
    try {
      final body = <String, dynamic>{};
      if (platformRiderId != null) body['platform_rider_id'] = platformRiderId;
      if (validFrom != null) body['valid_from'] = validFrom;
      if (validTo != null) body['valid_to'] = validTo;

      final response = await http.patch(
        url,
        headers: _headers,
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['alias'];
      } else {
        throw Exception('Failed to update alias: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error updating rider alias: $e');
    }
  }

  /// Hard-delete an alias.
  Future<void> deleteRiderAlias({
    required String riderId,
    required String aliasId,
  }) async {
    final url = Uri.parse('$baseUrl/riders/$riderId/aliases/$aliasId');
    try {
      final response = await http.delete(url, headers: _headers);
      if (response.statusCode != 200) {
        throw Exception('Failed to delete alias: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error deleting rider alias: $e');
    }
  }

  // ─── Transaction Approve / Reject ────────────────────────

  /// Approve a pending transaction
  Future<void> approveTransaction(String transactionId) async {
    final url = Uri.parse('$baseUrl/transactions/$transactionId/approve');
    try {
      final response = await http.post(url, headers: _headers);
      if (response.statusCode != 200) {
        throw Exception('Failed to approve transaction: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error approving transaction: $e');
    }
  }

  /// Reject a pending transaction
  Future<void> rejectTransaction(String transactionId) async {
    final url = Uri.parse('$baseUrl/transactions/$transactionId/reject');
    try {
      final response = await http.post(url, headers: _headers);
      if (response.statusCode != 200) {
        throw Exception('Failed to reject transaction: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error rejecting transaction: $e');
    }
  }

  // ─── Bikes CRUD ──────────────────────────────────────────

  /// Create a new bike
  Future<Map<String, dynamic>> createBike(
    String bikeId, {
    String? model,
  }) async {
    final url = Uri.parse('$baseUrl/bikes');
    try {
      final body = <String, dynamic>{'bike_id': bikeId};
      if (model != null && model.isNotEmpty) body['model'] = model;
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode(body),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to create bike: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error creating bike: $e');
    }
  }

  /// List all bikes
  Future<List<dynamic>> getBikes() async {
    final url = Uri.parse('$baseUrl/bikes');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['bikes'] as List<dynamic>;
      } else {
        throw Exception('Failed to fetch bikes: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching bikes: $e');
    }
  }

  /// Delete a bike
  Future<void> deleteBike(String bikeId) async {
    final url = Uri.parse('$baseUrl/bikes/$bikeId');
    try {
      final response = await http.delete(url, headers: _headers);
      if (response.statusCode != 200) {
        throw Exception('Failed to delete bike: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error deleting bike: $e');
    }
  }

  /// Return a bike (mark as available)
  Future<void> returnBike(String bikeId) async {
    final url = Uri.parse('$baseUrl/bikes/$bikeId/return');
    try {
      final response = await http.post(url, headers: _headers);
      if (response.statusCode != 200) {
        throw Exception('Failed to return bike: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error returning bike: $e');
    }
  }

  // ─── Bulk Fine Upload ────────────────────────────────────

  /// Upload multiple fines at once
  Future<Map<String, dynamic>> uploadBulkFines(
    List<Map<String, dynamic>> fines,
  ) async {
    final url = Uri.parse('$baseUrl/fines/upload-bulk');
    try {
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({'fines': fines}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to upload bulk fines: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error uploading bulk fines: $e');
    }
  }

  /// Fetches aging buckets for unpaid fines
  Future<Map<String, dynamic>> getFineAging() async {
    final url = Uri.parse('$baseUrl/reports/aging');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to fetch aging: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching aging: $e');
    }
  }

  /// Fetches rider statement of account
  Future<List<dynamic>> getRiderStatement(String riderId) async {
    final url = Uri.parse('$baseUrl/reports/rider/$riderId');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['statement'] as List<dynamic>;
      } else {
        throw Exception('Failed to fetch statement: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching statement: $e');
    }
  }

  /// Fetches pending riders for Accountant review
  Future<List<Map<String, dynamic>>> getPendingRiders() async {
    final url = Uri.parse('$baseUrl/action_items');

    try {
      final response = await http.get(url, headers: _headers);

      if (response.statusCode == 200) {
        final List<dynamic> body = jsonDecode(response.body);
        return body
            .where(
              (item) =>
                  item['type'] == 'rider_pending_approval' &&
                  item['responsible_role'] == 'accountant' &&
                  item['resolved_at'] == null,
            )
            .toList()
            .cast<Map<String, dynamic>>();
      } else {
        throw Exception('Failed to fetch pending riders: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching pending riders: $e');
    }
  }

  Future<void> approveRider(String riderId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/riders/approve'),
      body: jsonEncode({'rider_id': riderId}),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to approve rider');
    }
  }

  Future<void> rejectRider(String riderId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/riders/reject'),
      body: jsonEncode({'rider_id': riderId}),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to reject rider');
    }
  }

  Future<Map<String, dynamic>> getRiderStatementSummary(String riderId) async {
    final url = Uri.parse('$baseUrl/reports/rider/$riderId/summary');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return (data['summary'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      }
      throw Exception('Failed to fetch rider summary: ${response.body}');
    } catch (e) {
      throw Exception('Error fetching rider summary: $e');
    }
  }

  Future<List<dynamic>> getRiderStatusHistory(String riderId) async {
    final url = Uri.parse('$baseUrl/riders/$riderId/status-history');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return (data['history'] as List<dynamic>?) ?? <dynamic>[];
      }
      throw Exception('Failed to fetch rider status history: ${response.body}');
    } catch (e) {
      throw Exception('Error fetching rider status history: $e');
    }
  }

  Future<void> updateRiderStatus({
    required String riderId,
    required String status,
    String? reason,
    String? effectiveFrom,
    String? expectedReturnDate,
  }) async {
    final url = Uri.parse('$baseUrl/riders/$riderId/status');
    final body = <String, dynamic>{
      'status': status,
      if (reason != null) 'reason': reason,
      if (effectiveFrom != null) 'effective_from': effectiveFrom,
      if (expectedReturnDate != null) 'expected_return_date': expectedReturnDate,
    };
    try {
      final response = await http.post(url, headers: _headers, body: jsonEncode(body));
      if (response.statusCode != 200) {
        throw Exception('Failed to update rider status: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error updating rider status: $e');
    }
  }

  Future<List<dynamic>> getRiderHoldHistory(String riderId) async {
    final url = Uri.parse('$baseUrl/riders/$riderId/hold-history');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return (data['history'] as List<dynamic>?) ?? <dynamic>[];
      }
      throw Exception('Failed to fetch rider hold history: ${response.body}');
    } catch (e) {
      throw Exception('Error fetching rider hold history: $e');
    }
  }

  Future<void> updateRiderReleaseHold({
    required String riderId,
    required String releaseHold,
    String? reason,
    String? holdUntil,
  }) async {
    final url = Uri.parse('$baseUrl/riders/$riderId/release-hold');
    final body = <String, dynamic>{
      'release_hold': releaseHold,
      if (reason != null) 'reason': reason,
      if (holdUntil != null) 'hold_until': holdUntil,
    };
    try {
      final response = await http.post(url, headers: _headers, body: jsonEncode(body));
      if (response.statusCode != 200) {
        throw Exception('Failed to update rider release/hold: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error updating rider release/hold: $e');
    }
  }

  Future<Map<String, dynamic>> getRiderDocumentAlerts(String riderId) async {
    final url = Uri.parse('$baseUrl/riders/$riderId/document-alerts');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw Exception('Failed to fetch rider document alerts: ${response.body}');
    } catch (e) {
      throw Exception('Error fetching rider document alerts: $e');
    }
  }

  Future<Map<String, dynamic>> previewRiderAliasConflicts({
    required String riderId,
    required String platform,
    required String platformRiderId,
    String? validFrom,
  }) async {
    final url = Uri.parse('$baseUrl/riders/$riderId/alias-conflicts/preview');
    final body = <String, dynamic>{
      'platform': platform,
      'platform_rider_id': platformRiderId,
      if (validFrom != null) 'valid_from': validFrom,
    };

    try {
      final response = await http.post(url, headers: _headers, body: jsonEncode(body));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return (data['preview'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      }
      throw Exception('Failed to preview rider alias conflicts: ${response.body}');
    } catch (e) {
      throw Exception('Error previewing rider alias conflicts: $e');
    }
  }
}
