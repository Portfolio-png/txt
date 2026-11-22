import 'package:core_erp/core/sync/workspace_namespace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the same user on two servers keeps two copies', () {
    final real = workspaceNamespace(baseUrl: 'http://127.0.0.1:18080', user: '1');
    final other = workspaceNamespace(baseUrl: 'http://127.0.0.1:19080', user: '1');
    expect(real, isNot(other));
    expect(real, '127.0.0.1_18080__1');
  });

  test('two users on one server keep two copies', () {
    expect(
      workspaceNamespace(baseUrl: 'https://erp.example.com', user: '1'),
      isNot(workspaceNamespace(baseUrl: 'https://erp.example.com', user: '17')),
    );
  });

  test('the name is one folder on any platform', () {
    for (final url in [
      'http://192.168.1.20:18080/',
      'https://erp.example.com/paper/api',
      'not a url',
      '',
    ]) {
      final name = workspaceNamespace(baseUrl: url, user: 'Asha K@factory');
      expect(name, matches(RegExp(r'^[a-z0-9._@-]+$')), reason: url);
    }
    expect(
      workspaceNamespace(baseUrl: 'http://host:18080/', user: '1'),
      workspaceNamespace(baseUrl: 'http://host:18080', user: '1'),
      reason: 'a trailing slash is the same server',
    );
  });

  test('no user is anonymous, not an empty folder', () {
    expect(workspaceNamespace(baseUrl: 'http://host', user: ' '), 'host__anonymous');
  });
}
