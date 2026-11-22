/// The folder name this device keeps one person's data from one server under:
/// the replica, the response cache and the outbox of unsent writes.
///
/// It was the user id alone. Ids are small numbers every server hands out, so
/// user 1 on one server opened user 1's copy of another: after Change server
/// the phone showed the old server's suppliers, the desktop pointed at a test
/// server offered the real one's groups (ids the test server did not have, so
/// every save was refused), and writes waiting in the outbox could have gone
/// to a server they were never made on (B64).
String workspaceNamespace({required String baseUrl, required String user}) {
  final uri = Uri.tryParse(baseUrl.trim());
  final host = (uri?.host ?? '').isEmpty ? baseUrl.trim() : uri!.host;
  final port = uri != null && uri.hasPort ? '_${uri.port}' : '';
  final path = uri == null || uri.path == '/' ? '' : uri.path;
  final who = user.trim().isEmpty ? 'anonymous' : user.trim();
  return '${_safe('$host$port$path')}__${_safe(who)}';
}

/// A name safe as one folder on every platform: Windows refuses `:` and `/`.
String _safe(String text) {
  final cleaned = text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9.@-]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return cleaned.isEmpty ? 'unknown' : cleaned;
}
