const fs = require('fs');

let apiCode = fs.readFileSync('packages/core_erp/lib/features/auth/data/auth_api.dart', 'utf8');
apiCode = apiCode.replace(
  `Future<void> resetDemoData() async {`,
  `Future<void> resetDemoData({String scenarioId = 'default'}) async {`
);
apiCode = apiCode.replace(
  `final response = await _client.post(
      Uri.parse('$baseUrl/api/admin/reset-demo-data'),
      headers: _authHeaders,
    );`,
  `final response = await _client.post(
      Uri.parse('$baseUrl/api/admin/reset-demo-data'),
      headers: _authHeaders,
      body: jsonEncode({'scenarioId': scenarioId}),
    );`
);
fs.writeFileSync('packages/core_erp/lib/features/auth/data/auth_api.dart', apiCode);

let providerCode = fs.readFileSync('packages/core_erp/lib/features/auth/presentation/providers/auth_provider.dart', 'utf8');
providerCode = providerCode.replace(
  `Future<bool> resetDemoData() async {`,
  `Future<bool> resetDemoData({String scenarioId = 'default'}) async {`
);
providerCode = providerCode.replace(
  `await _api.resetDemoData();`,
  `await _api.resetDemoData(scenarioId: scenarioId);`
);
fs.writeFileSync('packages/core_erp/lib/features/auth/presentation/providers/auth_provider.dart', providerCode);

console.log('Patched frontend reset demo data');
