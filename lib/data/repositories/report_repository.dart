abstract class ReportRepository {
  Future<Map<String, dynamic>> fetchReportSummary(DateTime month);
  Future<Map<String, dynamic>> fetchFineAging();
}
