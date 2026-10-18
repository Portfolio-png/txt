import 'package:http/http.dart' as http;

typedef AuthTokenResolver = String? Function();
typedef UnauthorizedCallback = void Function();

/// Which sitting the write happening now belongs to, or null. See
/// `SittingScope`.
typedef SittingResolver = String? Function();

/// The header the server reads a sitting from.
const String kSittingHeader = 'X-Paper-Sitting';

class AuthenticatedHttpClient extends http.BaseClient {
  AuthenticatedHttpClient({
    required AuthTokenResolver tokenResolver,
    UnauthorizedCallback? onUnauthorized,
    SittingResolver? sittingResolver,
    http.Client? inner,
  }) : _tokenResolver = tokenResolver,
       _onUnauthorized = onUnauthorized,
       _sittingResolver = sittingResolver,
       _inner = inner ?? http.Client();

  final AuthTokenResolver _tokenResolver;
  final UnauthorizedCallback? _onUnauthorized;
  final SittingResolver? _sittingResolver;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = _tokenResolver();
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    // Writes only. A GET changes nothing, so tagging it would put reads in a
    // record of what was done — and it would also vary the request while a
    // sitting is open, which is the one thing a conditional cache must not see.
    if (request.method != 'GET') {
      final sitting = _sittingResolver?.call();
      if (sitting != null && sitting.isNotEmpty) {
        request.headers[kSittingHeader] = sitting;
      }
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
