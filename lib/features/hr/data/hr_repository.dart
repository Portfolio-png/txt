import 'dart:convert';
import 'package:http/http.dart' as http;

/// Thin HTTP client for the HR/Payroll backend. The payroll routes return raw
/// snake_case rows, so we pass plain maps around rather than minting a model
/// class per table (ponytail: the UI reads a handful of keys off each row).
class HrRepository {
  HrRepository({http.Client? client, this.baseUrl = 'http://localhost:18080'})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Map<String, String> get _h => {'Content-Type': 'application/json'};

  Map<String, dynamic> _ok(http.Response res) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw HrApiException('HTTP ${res.statusCode}: ${res.body}');
    }
    if (res.statusCode >= 200 && res.statusCode < 300 && data['success'] != false) {
      return data;
    }
    throw HrApiException(data['error']?.toString() ?? 'HTTP ${res.statusCode}');
  }

  Future<List<Map<String, dynamic>>> _list(String path, String key) async {
    final res = await _client.get(Uri.parse('$baseUrl$path'), headers: _h);
    final list = _ok(res)[key] as List? ?? const [];
    return list.cast<Map<String, dynamic>>();
  }

  // ---- Masters ----
  Future<List<Map<String, dynamic>>> employees() => _list('/api/employees', 'employees');
  Future<List<Map<String, dynamic>>> components() => _list('/api/payroll/components', 'components');
  Future<List<Map<String, dynamic>>> leaveTypes() => _list('/api/leave/types', 'types');

  Future<void> createComponent({
    required String name,
    required String type, // 'earning' | 'deduction'
    required String calculationMethod, // 'fixed' | 'percent_of_basic'
    bool isStatutory = false,
  }) async {
    final res = await _client.post(Uri.parse('$baseUrl/api/payroll/components'),
        headers: _h,
        body: jsonEncode({
          'name': name,
          'type': type,
          'calculation_method': calculationMethod,
          'is_statutory': isStatutory ? 1 : 0,
        }));
    _ok(res);
  }

  Future<void> createLeaveType({required String name, bool paid = true}) async {
    final res = await _client.post(Uri.parse('$baseUrl/api/leave/types'),
        headers: _h, body: jsonEncode({'name': name, 'paid': paid ? 1 : 0}));
    _ok(res);
  }

  // ---- Salary structure ----
  Future<Map<String, dynamic>> getStructure(int employeeId) async {
    final res = await _client.get(
        Uri.parse('$baseUrl/api/payroll/employees/$employeeId/salary-structure'),
        headers: _h);
    return _ok(res); // { structure, lines }
  }

  /// [lines] = [{ component_id, amount_or_formula }]
  Future<void> saveStructure({
    required int employeeId,
    required String effectiveDate,
    required List<Map<String, dynamic>> lines,
  }) async {
    final res = await _client.put(
        Uri.parse('$baseUrl/api/payroll/employees/$employeeId/salary-structure'),
        headers: _h,
        body: jsonEncode({'effective_date': effectiveDate, 'lines': lines}));
    _ok(res);
  }

  // ---- Payroll runs ----
  Future<List<Map<String, dynamic>>> runs() => _list('/api/payroll/runs', 'runs');

  Future<int> createRun({required int month, required int year}) async {
    final res = await _client.post(Uri.parse('$baseUrl/api/payroll/runs'),
        headers: _h, body: jsonEncode({'month': month, 'year': year, 'client_id': 0}));
    return _ok(res)['id'] as int;
  }

  Future<Map<String, dynamic>> processRun(int id) async {
    final res = await _client.post(
        Uri.parse('$baseUrl/api/payroll/runs/$id/process'), headers: _h);
    return _ok(res);
  }

  Future<void> finalizeRun(int id) async {
    final res = await _client.post(
        Uri.parse('$baseUrl/api/payroll/runs/$id/finalize'), headers: _h);
    _ok(res);
  }

  Future<Map<String, dynamic>> runDetails(int id) async {
    final res =
        await _client.get(Uri.parse('$baseUrl/api/payroll/runs/$id'), headers: _h);
    return _ok(res); // { run, details }
  }

  // ---- Attendance ----
  Future<List<Map<String, dynamic>>> attendance({
    required int employeeId,
    required int month,
    required int year,
  }) =>
      _list('/api/attendance?employeeId=$employeeId&month=$month&year=$year', 'records');

  Future<void> upsertAttendance({
    required int employeeId,
    required String date, // YYYY-MM-DD
    required String status,
    double hoursWorked = 0,
  }) async {
    final res = await _client.post(Uri.parse('$baseUrl/api/attendance'),
        headers: _h,
        body: jsonEncode({
          'employee_id': employeeId,
          'date': date,
          'status': status,
          'hours_worked': hoursWorked,
        }));
    _ok(res);
  }

  // ---- Leave ----
  Future<List<Map<String, dynamic>>> leaveBalances(int employeeId) =>
      _list('/api/leave/balances?employeeId=$employeeId', 'balances');

  Future<void> saveBalance({
    required int employeeId,
    required int leaveTypeId,
    double opening = 0,
    double credited = 0,
    double availed = 0,
  }) async {
    final res = await _client.put(Uri.parse('$baseUrl/api/leave/balances'),
        headers: _h,
        body: jsonEncode({
          'employee_id': employeeId,
          'leave_type_id': leaveTypeId,
          'opening': opening,
          'credited': credited,
          'availed': availed,
        }));
    _ok(res);
  }

  Future<List<Map<String, dynamic>>> leaveRequests() =>
      _list('/api/leave/requests', 'requests');

  Future<void> createLeaveRequest({
    required int employeeId,
    required int leaveTypeId,
    required String fromDate,
    required String toDate,
    required double days,
    String reason = '',
  }) async {
    final res = await _client.post(Uri.parse('$baseUrl/api/leave/requests'),
        headers: _h,
        body: jsonEncode({
          'employee_id': employeeId,
          'leave_type_id': leaveTypeId,
          'from_date': fromDate,
          'to_date': toDate,
          'days': days,
          'reason': reason,
        }));
    _ok(res);
  }

  Future<void> decideLeaveRequest(int id, String status) async {
    final res = await _client.put(Uri.parse('$baseUrl/api/leave/requests/$id'),
        headers: _h, body: jsonEncode({'status': status}));
    _ok(res);
  }

  // ---- Statutory config ----
  Future<Map<String, dynamic>?> statutory() async {
    final res = await _client.get(Uri.parse('$baseUrl/api/statutory-config'),
        headers: _h);
    return _ok(res)['config'] as Map<String, dynamic>?;
  }

  Future<void> saveStatutory(Map<String, dynamic> cfg) async {
    final res = await _client.put(Uri.parse('$baseUrl/api/statutory-config'),
        headers: _h, body: jsonEncode(cfg));
    _ok(res);
  }
}

class HrApiException implements Exception {
  const HrApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
