const fs = require('fs');

let apiCode = fs.readFileSync('packages/core_erp/lib/features/auth/data/auth_api.dart', 'utf8');
apiCode = apiCode.replace(
  `Future<void> reseedDemoData() async {`,
  `Future<void> reseedDemoData({String scenarioId = 'default'}) async {`
);
apiCode = apiCode.replace(
  `final response = await _client.post(
      Uri.parse('$baseUrl/api/admin/reseed-data'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );`,
  `final response = await _client.post(
      Uri.parse('$baseUrl/api/admin/reseed-data'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'scenarioId': scenarioId}),
    );`
);
fs.writeFileSync('packages/core_erp/lib/features/auth/data/auth_api.dart', apiCode);

let providerCode = fs.readFileSync('packages/core_erp/lib/features/auth/presentation/providers/auth_provider.dart', 'utf8');
providerCode = providerCode.replace(
  `Future<bool> reseedDemoData() async {`,
  `Future<bool> reseedDemoData({String scenarioId = 'default'}) async {`
);
providerCode = providerCode.replace(
  `await _api.reseedDemoData();`,
  `await _api.reseedDemoData(scenarioId: scenarioId);`
);
fs.writeFileSync('packages/core_erp/lib/features/auth/presentation/providers/auth_provider.dart', providerCode);

console.log('Patched frontend auth api');
