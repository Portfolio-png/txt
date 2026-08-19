import 'package:http/http.dart' as http;

typedef AuthTokenResolver = String? Function();
typedef UnauthorizedCallback = void Function();

class AuthenticatedHttpClient extends http.BaseClient {
  AuthenticatedHttpClient({
    required AuthTokenResolver tokenResolver,
    UnauthorizedCallback? onUnauthorized,
    http.Client? inner,
  }) : _tokenResolver = tokenResolver,
       _onUnauthorized = onUnauthorized,
       _inner = inner ?? http.Client();

  final AuthTokenResolver _tokenResolver;
  final UnauthorizedCallback? _onUnauthorized;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = _tokenResolver();
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    final response = await _inner.send(request);
    if ((response.statusCode == 401 || response.statusCode == 403) &&
        token != null &&
        token.isNotEmpty) {
      _onUnauthorized?.call();
    }
    return response;
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
