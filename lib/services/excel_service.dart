import 'dart:io';
import 'package:excel/excel.dart';
import 'package:csv/csv.dart' show CsvDecoder;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'api_service.dart';
import '../data/models/rider_model.dart';
import 'package:intl/intl.dart';
import '../data/models/fines_model.dart';

class ExcelService {
  static final ExcelService _instance = ExcelService._internal();
  static ExcelService get instance => _instance;
  ExcelService._internal();

  Future<Object?> parseFile(File file) async {
    final extension = file.path.split('.').last.toLowerCase();

    if (extension == 'csv' || extension == 'txt') {
      return await _parseCsv(file);
    } else {
      try {
        var bytes = await file.readAsBytes();
        var excel = Excel.decodeBytes(bytes);
        Map<String, dynamic>? aggregateResult;
        bool anyProcessed = false;
        List<String> sheetErrors = [];
        for (var table in excel.tables.keys) {
          if (table == "WC Employe") continue;
          var sheet = excel.tables[table];
          if (sheet == null || sheet.maxRows == 0) continue;

          var rows = sheet.rows
              .map((row) => row.map((e) => e?.value).toList())
              .toList();

          try {
            var res = await _processRows(rows);
            if (res != null) {
              anyProcessed = true;
              if (res is Map<String, dynamic>) {
                aggregateResult ??= {'success': 0, 'failed': 0, 'missing': []};
                aggregateResult['success'] =
                    (aggregateResult['success'] ?? 0) + (res['success'] ?? 0);
                aggregateResult['failed'] =
                    (aggregateResult['failed'] ?? 0) + (res['failed'] ?? 0);
                if (res['missing'] != null) {
                  aggregateResult['missing'] = [
                    ...((aggregateResult['missing'] as List?)?.cast<String>() ??
                        []),
                    ...(res['missing'] as List).cast<String>(),
                  ];
                }
              }
            }
          } catch (e) {
            print("WARNING: Failed to process sheet $table: $e");
            sheetErrors.add("$table: ${e.toString().replaceAll('Exception: ', '')}");
          }
        }
        
        if (aggregateResult == null && anyProcessed == false) {
           if (sheetErrors.isNotEmpty) {
             throw Exception("Could not process any sheets. Errors: ${sheetErrors.join('; ')}");
           }
           throw Exception("Could not identify file type. Please ensure the Excel contains valid column headers (e.g. Plate, Amount, Ticket).");
        }
        return aggregateResult;
      } catch (e) {
        bool isXls = extension == 'xls';
        try {
          return await _parseCsv(file);
        } catch (e2) {
          String msg = "Failed to parse file.";
          if (isXls)
            msg +=
                " Legacy .xls files are not fully supported. Please save as .xlsx or .csv.";
          else
            msg += " Please ensure it is a valid .xlsx or .csv file.";
          throw Exception("$msg (Excel Error: $e, CSV Error: $e2)");
        }
      }
    }
  }

  Future<Object?> _parseCsv(File file) async {
    try {
      final input = file.openRead();
      final chunks = await input
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const CsvDecoder())
          .toList();

      final List<List<dynamic>> rows = chunks.expand((chunk) => chunk).toList();
      return await _processRows(rows);
    } catch (e) {
      try {
        final bytes = await file.readAsBytes();
        final content = utf8.decode(bytes, allowMalformed: true);
        var converter = const CsvDecoder();
        if (content.contains('\t') && !content.contains(',')) {
          converter = const CsvDecoder(fieldDelimiter: '\t');
        }
        final rows = converter.convert(content);
        return await _processRows(rows);
      } catch (e2) {
        throw Exception("Could not decode file as CSV or text: $e2");
      }
    }
  }

  Future<Object?> _processRows(List<List<dynamic>> rows) async {
    if (rows.isEmpty) return null;

    for (int i = 0; i < rows.length && i < 50; i++) { // Check first 50 rows for headers
      final rawRow = rows[i].map((e) => e?.toString() ?? '').toList();
      if (rawRow.every((e) => e.trim().isEmpty)) continue;

      final cleanRow = rawRow.map((e) => _cleanHeader(e)).toList();
      bool hasCol(List<String> synonyms) {
        return synonyms.any((syn) {
          final cleanSyn = _cleanHeader(syn);
          return cleanRow.any((col) => col == cleanSyn || col.contains(cleanSyn));
        });
      }

      // 1. Rider Master keywords
      final isRiderID = hasCol(["Emirates ID", "Rider ID", "Rider Code", "Courier ID", "Staff No", "Company Number", "Code", "Work ID", "Partner ID", "EID"]);
      final isName = hasCol(["Name", "Full Name", "Rider Name", "Courier Name"]);
      
      if (isRiderID && isName) {
        return await parseRiderMaster(rows.sublist(i));
      }

      // 2. Bike History / Assignment keywords
      final isBike = hasCol(["Bike", "Vehicle", "Plate", "Registration", "Motorcycle", "Bike No", "Reg"]);
      final isAssigned = hasCol(["Giving", "Assign", "Handover", "Out", "Start", "Date", "Delivery"]);
      final hasRiderCol = hasCol(["Emirates ID", "Rider ID", "Rider Code", "Courier ID", "Staff No", "Company Number", "Code", "Work ID", "Partner ID", "EID"]);

      if (isBike && isAssigned && hasRiderCol) {
        return await parseBikeHistory(rows.sublist(i));
      }

      // 3. Fines / Traffic Violations keywords
      bool hasPlate = hasCol(["Plate", "Vehicle", "Bike", "No", "Tag", "Registration"]);
      bool hasAmount = hasCol(["Amount", "Fee", "Value", "Sum", "Payment", "Debit", "AED"]);
      bool hasTicket = hasCol(["Ticket", "Fine", "Notice", "Challan", "Violation", "Offense"]);

      if ((hasTicket && (hasPlate || hasAmount)) || (hasPlate && hasAmount)) {
        try {
          return await parseFines(rows.sublist(i));
        } catch (e) {
          print("Note: Row $i looked like a Fine header but failed: $e. Searching deeper...");
          continue;
        }
      }

      // 4. Payroll keywords
      if (hasCol(["Courier ID", "Code", "Partner ID", "Staff No"]) &&
          (hasCol(["Salary", "Amount", "Earnings", "Total Pay", "Net Pay", "Net Salary", "Total Salary"]))) {
        return null; // Signals sheet recognized but handled by PayrollBloc
      }
    }

    throw Exception("Could not identify this sheet. Please ensure columns like 'Rider ID', 'Name', 'Plate', or 'Amount' are clearly labeled in the first few rows.");
  }

  Future<Map<String, dynamic>> parseRiderMaster(List<List<dynamic>> rows) async {
    if (rows.isEmpty || rows.length < 2) return {'success': 0, 'failed': 0, 'error': 'Empty sheet'};

    final headerRow = rows.first.map((e) => e?.toString() ?? '').toList();
    List<Map<String, dynamic>> dynamicRows = [];

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || row.every((e) => _parseString(e).trim().isEmpty)) continue;

      Map<String, dynamic> rowData = {};
      for (var j = 0; j < headerRow.length; j++) {
        if (j < row.length) {
          String header = headerRow[j];
          String value = _parseString(row[j]);
          if (header.isNotEmpty && value.isNotEmpty) rowData[header] = value;
        }
      }
      if (rowData.isNotEmpty) dynamicRows.add(rowData);
    }

    if (dynamicRows.isNotEmpty) {
      try {
        final res = await ApiService.instance.uploadDynamicExcel(dynamicRows);
        final stats = (res['stats'] as Map?)?.cast<String, dynamic>() ?? {};
        final riders = (stats['riders'] as num?)?.toInt() ?? 0;
        final bikes = (stats['bikes'] as num?)?.toInt() ?? 0;
        final assignments = (stats['assignments'] as num?)?.toInt() ?? 0;
        final inserted = (res['inserted_rows'] as num?)?.toInt() ?? (riders + bikes + assignments);
        final errors = (stats['errors'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
        return {
          'success': inserted,
          'failed': errors.length,
          'message': res['message'],
          'logs': errors,
          'stats': stats,
        };
      } catch (e) {
        throw Exception("Rider upload failed: $e");
      }
    }
    return {'success': 0, 'failed': 0, 'message': 'No valid rider data found in sheet.'};
  }

  Future<Map<String, dynamic>> parseBikeHistory(List<List<dynamic>> rows) async {
    if (rows.isEmpty || rows.length < 2) return {'success': 0, 'failed': 0};

    final headerRow = rows.first.map((e) => e?.toString() ?? '').toList();
    List<Map<String, dynamic>> dynamicRows = [];

    for (var i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty || row.every((e) => _parseString(e).trim().isEmpty)) continue;

        Map<String, dynamic> rowData = {};
        for (var j = 0; j < headerRow.length; j++) {
          if (j < row.length) {
            String header = headerRow[j];
            String value = _parseString(row[j]);
            if (header.isNotEmpty && value.isNotEmpty) rowData[header] = value;
          }
        }
        if (rowData.isNotEmpty) dynamicRows.add(rowData);
    }

    if (dynamicRows.isNotEmpty) {
      try {
        final res = await ApiService.instance.uploadDynamicExcel(dynamicRows);
        return {
          'success': res['stats']['assignments'] ?? 0,
          'failed': (res['stats']['errors'] as List?)?.length ?? 0,
          'message': res['message'],
          'logs': (res['stats']['errors'] as List?)?.map((e) => e.toString()).toList() ?? [],
          'stats': res['stats'],
        };
      } catch (e) {
        throw Exception("Bike assignment upload failed: $e");
      }
    }
    return {'success': 0, 'failed': 0, 'message': 'No valid bike data found in sheet.'};
  }

  Future<List<RiderModel>> _fetchRiders() async {
    try {
      final response = await Supabase.instance.client.from('riders').select();
      return (response as List).map((e) => RiderModel.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<BikeAssignmentModel>> _fetchAssignments() async {
    try {
      final response = await Supabase.instance.client
          .from('bike_assignment')
          .select('*, bikes(bike_id, chassis_number)');
      return (response as List)
          .map((e) => BikeAssignmentModel.fromJson(e))
          .toList();
    } catch (e) {
      return [];
    }
  }

  RiderModel? _findRider(
    String plate,
    DateTime date,
    List<RiderModel> riders,
    List<BikeAssignmentModel> assignments,
  ) {
    if (plate.isEmpty) return null;
    final normPlate = _normalizeVehicleKey(plate);
    
    // Find all assignments for this bike
    final bikeAssignments = assignments.where((a) {
      final aPlate = _normalizeVehicleKey(a.plateNumber ?? '');
      final aChassis = _normalizeVehicleKey(a.chassisNumber);
      return aPlate == normPlate || aChassis == normPlate;
    }).toList();

    List<RiderModel> matchedRiders = [];
    for (var assignment in bikeAssignments) {
      // Check if the fine/event happened WITHIN the assignment period
      bool started = assignment.assignedAt.isBefore(date) ||
                     assignment.assignedAt.isAtSameMomentAs(date);
      bool ended = assignment.returnedAt != null &&
                   assignment.returnedAt!.isBefore(date);
      
      if (started && !ended) {
        final match = riders.firstWhere(
          (r) => r.id == assignment.riderId,
          orElse: () => const RiderModel(id: '', name: 'Unknown', status: RiderStatus.active),
        );
        if (match.id.isNotEmpty) matchedRiders.add(match);
      }
    }

    if (matchedRiders.length == 1) return matchedRiders.first;
    if (matchedRiders.length > 1) {
      print("WARNING: Multiple riders found for plate $normPlate on $date. Possible overlapping assignments in database.");
    }
    return null;
  }

  String _normalizeVehicleKey(String value) {
    return value
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '')
        .trim();
  }

  String _cleanHeader(String value) => value.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]'), '');
  String _parseString(dynamic value) => value?.toString().trim() ?? '';
  
  double _cleanAmount(dynamic value) {
    if (value == null) return 0.0;
    String s = _parseString(value).toUpperCase();
    if (s.isEmpty) return 0.0;
    // Remove currency symbols, commas, and whitespace
    s = s.replaceAll('AED', '').replaceAll(',', '').trim();
    final result = double.tryParse(s);
    if (result == null && s.isNotEmpty) {
      throw Exception("Invalid amount format: '$s'. Entire upload stopped to ensure data integrity.");
    }
    return result ?? 0.0;
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    
    // 1. Handle Excel-specific cell types (v4+ of excel package)
    // DateCellValue and DateTimeCellValue are the new standard
    if (value.toString().contains('DateCellValue') || value.toString().contains('DateTimeCellValue')) {
      try {
        final val = (value as dynamic).value;
        if (val is DateTime) return val;
      } catch (_) {}
    }

    // 2. Handle Excel OADate (serial numbers)
    if (value is num || value is IntCellValue || value is DoubleCellValue) {
      double d = (value is num) ? value.toDouble() : 
                 (value is IntCellValue) ? value.value.toDouble() : (value as DoubleCellValue).value;
      
      // Typical Excel date range (1900 to 2100)
      if (d > 30000 && d < 60000) {
        // Excel's 1900 leap year bug means we start from 1899-12-30
        return DateTime(1899, 12, 30).add(Duration(milliseconds: (d * 24 * 60 * 60 * 1000).round()));
      }
    }

    String s = _parseString(value).trim();
    if (s.isEmpty) return null;

    // 3. Try common formats (Expanded list)
    final formats = [
      DateFormat('dd/MM/yyyy'),
      DateFormat('MM/dd/yyyy'),
      DateFormat('yyyy-MM-dd'),
      DateFormat('dd-MM-yyyy'),
      DateFormat('dd-MMM-yyyy'), // 25-Mar-2024
      DateFormat('MM-dd-yyyy'),
      DateFormat('yyyy/MM/dd'),
      DateFormat('MMM dd, yyyy'), // Mar 25, 2024
    ];

    for (var f in formats) {
      try { return f.parse(s); } catch (_) {}
    }

    // 4. Last resort manual parse
    try { 
      // Handle cases like "2024.03.25"
      if (s.contains('.')) {
        final parts = s.split('.');
        if (parts.length == 3) {
          if (parts[0].length == 4) return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
          if (parts[2].length == 4) return DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
        }
      }
      return DateTime.tryParse(s); 
    } catch (_) {}
    
    return null;
  }

  DateTime _mergeDateTime(DateTime date, dynamic timeValue) {
    if (timeValue == null) return date;
    try {
      if (timeValue is num || timeValue is DoubleCellValue) {
        double faction = (timeValue is num) ? timeValue.toDouble() : (timeValue as DoubleCellValue).value;
        if (faction >= 0 && faction < 1) {
          int totalMinutes = (faction * 24 * 60).round();
          return DateTime(date.year, date.month, date.day, totalMinutes ~/ 60, totalMinutes % 60);
        }
      } else if (timeValue is String && timeValue.contains(':')) {
        final parts = timeValue.split(':');
        int h = int.tryParse(parts[0].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        int m = int.tryParse(parts[1].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        if (timeValue.toLowerCase().contains('pm') && h < 12) h += 12;
        if (timeValue.toLowerCase().contains('am') && h == 12) h = 0;
        return DateTime(date.year, date.month, date.day, h % 24, m % 60);
      }
    } catch (_) {}
    return date;
  }

  int _findColumnIndex(
    List<String> headers,
    List<String> keywords, {
    bool failOnAmbiguity = false,
  }) {
    List<int> matches = [];
    for (var kw in keywords) {
        final target = _cleanHeader(kw);
        for (int i = 0; i < headers.length; i++) {
            final h = _cleanHeader(headers[i]);
            if (h.contains(target)) {
                matches.add(i);
            }
        }
        if (matches.isNotEmpty) break; // Found best match group for highest priority keyword
    }
    if (matches.isEmpty) return -1;
    if (matches.length > 1 && failOnAmbiguity) {
        throw Exception("Found multiple matching columns for $keywords. Please rename columns to avoid ambiguity.");
    }
    return matches.first;
  }

  int _findTimeColumnIndex(List<String> headers, int dateIndex) {
    if (dateIndex == -1 || dateIndex + 1 >= headers.length) return -1;
    final next = _cleanHeader(headers[dateIndex + 1]);
    if (next.contains("time") || next.contains("clock") || next.contains("at")) return dateIndex + 1;
    return -1;
  }

  // High-level entry point used by PayrollBloc
  Future<List<Map<String, dynamic>>> parsePayrollRows(File file) async {
    final extension = file.path.split('.').last.toLowerCase();
    List<List<dynamic>> rows = [];
    if (extension == 'csv' || extension == 'txt') {
      final input = file.openRead();
      rows = await input
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const CsvDecoder())
          .toList();
    } else {
      var bytes = await file.readAsBytes();
      var excel = Excel.decodeBytes(bytes);
      for (var table in excel.tables.keys) {
        if (table == "WC Employe") continue;
        var sheet = excel.tables[table];
        if (sheet != null && sheet.maxRows > 0) {
          rows = sheet.rows.map((row) => row.map((e) => e?.value).toList()).toList();
          break;
        }
      }
    }
    return _extractPayrollData(rows);
  }

  List<Map<String, dynamic>> _extractPayrollData(List<List<dynamic>> rows) {
    if (rows.isEmpty) return [];

    // Header Detection (Scanning more robustly)
    List<String> headerRow = [];
    int headerIndex = 0;

    for (int i = 0; i < rows.length && i < 30; i++) {
        final r = rows[i].map((e) => _parseString(e).toLowerCase().trim()).toList();
        bool hasId = r.any((h) => h.contains("rider id") || h.contains("courier id") || h == "code" || h == "id");
        bool hasAmt = r.any((h) => h.contains("salary") || h.contains("amount") || h.contains("earnings") || h.contains("pay"));
        if (hasId && hasAmt) {
          headerRow = rows[i].map((e) => _parseString(e)).toList();
          headerIndex = i;
          break;
        }
    }

    if (headerRow.isEmpty) throw Exception("Could not find Rider ID or Salary columns.");

    int idIndex = _findColumnIndex(headerRow, ["rider id", "courier id", "partner id", "code", "id"]);
    int salIndex = _findColumnIndex(headerRow, ["salary", "amount", "total pay", "net pay", "earnings", "gross salary"]);

    List<Map<String, dynamic>> result = [];
    for (int i = headerIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length <= idIndex || row.length <= salIndex) continue;
      String id = _parseString(row[idIndex]);
      if (id.isEmpty) continue;

      Map<String, dynamic> rawData = {};
      for (int c = 0; c < row.length && c < headerRow.length; c++) {
        rawData[headerRow[c]] = _parseString(row[c]);
      }

      result.add({
        "external_id": id,
        "gross_salary": _cleanAmount(row[salIndex]),
        "raw_data": rawData,
      });
    }
    return result;
  }
}

extension ExcelServicePart2 on ExcelService {
  Future<Map<String, dynamic>> parseFines(List<List<dynamic>> rows) async {
    if (rows.isEmpty) return {'success': 0, 'failed': 0, 'missing': []};

    final headerRow = rows.first.map((e) => _parseString(e)).toList();
    
    // Comprehensive keywords for Dubai/UAE traffic fine formats
    final plateKeywords = ["plate number", "plate no", "plate", "vehicle plate", "vehicle no", "bike no", "tag", "reg number", "motorcycle", "chassis"];
    final amountKeywords = ["fine amount", "amount", "total", "fee", "sum", "value", "payment", "aed", "debit"];
    final ticketKeywords = ["ticket", "fine no", "challan", "notice", "violation no", "offense no", "ref"];
    final dateKeywords = ["date", "violation", "day", "time"];

    final plateIndex = _findColumnIndex(headerRow, plateKeywords);
    final amountIndex = _findColumnIndex(headerRow, amountKeywords);
    final ticketIndex = _findColumnIndex(headerRow, ticketKeywords);
    final dateIndex = _findColumnIndex(headerRow, dateKeywords);
    final riderIdIndex = _findColumnIndex(headerRow, ["rider id", "courier id", "partner id", "code", "id", "rider"]);
    final riderNameIndex = _findColumnIndex(
      headerRow,
      ["rider name", "courier name", "full name", "driver name", "name", "rider"],
    );
    
    final timeIndex = _findTimeColumnIndex(headerRow, dateIndex);

    if (plateIndex == -1 || amountIndex == -1 || (plateIndex == amountIndex && plateIndex != -1)) {
      String msg = "Could not find required columns ";
      if (plateIndex == -1) msg += "(Plate) ";
      if (amountIndex == -1) msg += "(Amount) ";
      if (plateIndex == amountIndex && plateIndex != -1) msg += "(Plate and Amount matched the same cell - likely a title row) ";
      msg += "in sheet. Found headers: $headerRow";
      throw Exception(msg);
    }

    // Fetch Riders and Aliases for platform resolution
    final allRiders = await _fetchRiders();
    final allAssignments = await _fetchAssignments();
    final allAliasData = await Supabase.instance.client.from('rider_aliases').select('rider_id, platform_rider_id');
    
    Map<String, String> idMap = {};
    for (var a in (allAliasData as List)) {
      idMap[a['platform_rider_id'].toString()] = a['rider_id'].toString();
    }

    List<Map<String, dynamic>> recordsToUpsert = [];
    List<String> missingRiders = [];

    bool _looksLikePersonName(String value) {
      final v = value.trim();
      if (v.isEmpty) return false;
      final lower = v.toLowerCase();
      if (lower == 'unknown' || lower == 'na' || lower == 'n/a' || lower == '-') return false;
      if (RegExp(r'^\d+$').hasMatch(v)) return false;
      if (v.contains('(') || v.contains(')')) return false;
      if (v.length > 40) return false;
      if (RegExp(r'\d{4}-\d{2}-\d{2}|\d{1,2}/\d{1,2}/\d{2,4}').hasMatch(v)) return false;
      if (RegExp(r'^[a-z]{1,3}[-\s]?[a-z]?[-\s]?\d{2,}$', caseSensitive: false).hasMatch(v)) return false;
      if (RegExp(r'\b(violation|offense|fine|ticket|lane|speed|parking|signal|radar|dubai|abu\s*dhabi|sharjah)\b', caseSensitive: false).hasMatch(v)) {
        return false;
      }
      final letterCount = RegExp(r'[A-Za-z]').allMatches(v).length;
      final words = v.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (words.length < 2 || words.length > 4) return false;
      return letterCount >= 3;
    }

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || row.every((e) => e == null || _parseString(e).isEmpty)) continue;

      // Plate normalization: allow alphanumeric but remove symbols and extra spaces
      String plate = _normalizeVehicleKey(_parseString(row[plateIndex]));
      if (plate.isEmpty) continue;

      double amount = _cleanAmount(row[amountIndex]);
      String ticketNo = ticketIndex != -1 ? _parseString(row[ticketIndex]) : "FIN-${DateTime.now().millisecondsSinceEpoch}-$i";

      DateTime? violationDate;
      if (dateIndex != -1 && row.length > dateIndex) {
        violationDate = _parseDateTime(row[dateIndex]);
        if (violationDate == null) {
          throw Exception("Row ${i + 1}: Could not parse violation date '${row[dateIndex]}'. Match failed to ensure accuracy.");
        }
        if (timeIndex != -1 && row.length > timeIndex) {
          violationDate = _mergeDateTime(violationDate, row[timeIndex]);
        }
      } else {
        throw Exception("Row ${i + 1}: Violation date column is missing or empty.");
      }

      String riderNameFromSheet = '';
      if (riderNameIndex != -1 && row.length > riderNameIndex) {
        riderNameFromSheet = _parseString(row[riderNameIndex]);
      }
      // Extra fallback for sheets with unusual rider-name headers.
      if (riderNameFromSheet.isEmpty) {
        for (int c = 0; c < headerRow.length && c < row.length; c++) {
          final h = _cleanHeader(headerRow[c]);
          if (!h.contains('rider') && !h.contains('driver') && !h.contains('courier') && !h.contains('name')) {
            continue;
          }
          if (h.contains('id') || h.contains('code') || h.contains('partner')) {
            continue;
          }
          final candidate = _parseString(row[c]);
          if (candidate.isNotEmpty) {
            riderNameFromSheet = candidate;
            break;
          }
        }
      }

      // Final heuristic fallback: infer likely person name from row values.
      if (riderNameFromSheet.isEmpty) {
        String? heuristicName;
        for (int c = 0; c < headerRow.length && c < row.length; c++) {
          if (c == plateIndex || c == amountIndex || c == ticketIndex || c == dateIndex || c == timeIndex || c == riderIdIndex) {
            continue;
          }
          final value = _parseString(row[c]);
          if (_looksLikePersonName(value)) {
            final header = _cleanHeader(headerRow[c]);
            if (header.contains('description') || header.contains('violation') || header.contains('offense') || header.contains('reason') || header.contains('city') || header.contains('location')) {
              continue;
            }
            if (header.contains('name') || header.contains('rider') || header.contains('driver') || header.contains('courier')) {
              heuristicName = value;
              break;
            }
          }
        }
        if (heuristicName != null && heuristicName.isNotEmpty) {
          riderNameFromSheet = heuristicName;
        }
      }

      // 1. Try resolution by provided Rider ID if present in the Excel
      RiderModel? rider;
      if (riderIdIndex != -1 && row.length > riderIdIndex) {
        String rawRiderId = _parseString(row[riderIdIndex]);
        if (rawRiderId.isNotEmpty) {
          String? riderUuid = idMap[rawRiderId];
          if (riderUuid != null) {
            rider = allRiders.firstWhere(
              (r) => r.id == riderUuid,
              orElse: () => const RiderModel(id: '', name: 'Unknown', status: RiderStatus.active),
            );
          }
        }
      }

      // 2. Resolve by Plate + Date if not already resolved
      if (rider == null || rider.id.isEmpty) {
        rider = _findRider(plate, violationDate, allRiders, allAssignments);
      }
      
      // Resolving status
      final rStatus = rider != null ? 'matched' : 'unmatched';
      final resolvedRiderName =
          (rider != null && rider.name.isNotEmpty && rider.name.toLowerCase() != 'unknown')
          ? rider.name
          : (riderNameFromSheet.isNotEmpty ? riderNameFromSheet : null);
      
      final Map<String, dynamic> record = {
        'ticket_number': ticketNo,
        'plate_number': plate,
        'violation_date': violationDate.toIso8601String(),
        'amount': amount,
        'remaining_balance': amount, // Ensure report visibility
        'rider_id': rider?.id,
        'rider_name': resolvedRiderName,
        'status': rStatus,
        'city': 'Dubai', // Default fallback
      };

      // DYNAMIC EXTRA COLUMNS: Search for extra fields (City, Description, Location, etc.)
      final extraValidKeys = {
        'city': ['city', 'region', 'emirate', 'location'],
        'description': ['description', 'violation details', 'offense', 'reason'],
        'location': ['location', 'place', 'street'],
        'fine_source': ['source', 'authority', 'issuer'],
      };

      for (var col in extraValidKeys.entries) {
        final targetDbCol = col.key;
        final synonyms = col.value;
        final idx = _findColumnIndex(headerRow, synonyms);
        if (idx != -1 && idx < row.length) {
           final val = _parseString(row[idx]);
           if (val.isNotEmpty) record[targetDbCol] = val;
        }
      }
      
      recordsToUpsert.add(record);
      
      if (rider == null) missingRiders.add(plate);
    }

    int success = 0;
    if (recordsToUpsert.isNotEmpty) {
      try {
        await Supabase.instance.client
            .from('traffic_fines')
            .upsert(recordsToUpsert, onConflict: 'ticket_number');
        success = recordsToUpsert.length;
      } catch (e) {
        throw Exception("Database update failed for fines: $e");
      }
    }

    return {'success': success, 'failed': recordsToUpsert.length - success, 'missing': missingRiders};
  }

  Future<Map<String, dynamic>> parseEarnings(
    List<List<dynamic>> rows,
    List<dynamic> firstRow,
  ) async {
    // Note: Payroll sheets are primarily handled by PayrollBloc using parsePayrollRows.
    // This is a partial fallback/aggregation reporter.
    final data = _extractPayrollData(rows);
    return {'success': data.length, 'failed': 0, 'missing': []};
  }

  Future<Map<String, dynamic>> parseSalikSheet(File file) async {
    // Salik is usually just traffic fines from a different source.
    // We can reuse the parsePayrollRows logic to get a List<List<dynamic>> then pass to parseFines.
    final extension = file.path.split('.').last.toLowerCase();
    List<List<dynamic>> rows = [];
    if (extension == 'csv' || extension == 'txt') {
      final input = file.openRead();
      rows = await input.transform(const Utf8Decoder(allowMalformed: true)).transform(const CsvDecoder()).toList();
    } else {
      var bytes = await file.readAsBytes();
      var excel = Excel.decodeBytes(bytes);
      for (var table in excel.tables.keys) {
        var sheet = excel.tables[table];
        if (sheet != null && sheet.maxRows > 0) {
          rows = sheet.rows.map((row) => row.map((e) => e?.value).toList()).toList();
          break;
        }
      }
    }
    return await parseFines(rows);
  }
}
