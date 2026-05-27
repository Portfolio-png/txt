import 'package:http/http.dart' as http;

typedef AuthTokenResolver = String? Function();

class AuthenticatedHttpClient extends http.BaseClient {
  AuthenticatedHttpClient({
    required AuthTokenResolver tokenResolver,
    http.Client? inner,
  }) : _tokenResolver = tokenResolver,
       _inner = inner ?? http.Client();

  final AuthTokenResolver _tokenResolver;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final token = _tokenResolver();
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
