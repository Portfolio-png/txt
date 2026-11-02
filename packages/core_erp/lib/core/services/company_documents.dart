import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'entity_photos.dart';
import 'socket_service.dart';

/// The largest document the server keeps (backend `MAX_DOCUMENT_BYTES`).
const int maxCompanyDocumentBytes = 25 * 1024 * 1024;

/// A file a company keeps under a name the user gave it — a GST certificate,
/// a drawing, a rate card. Any kind of file (backend uploaded_assets.document_title).
@immutable
class CompanyDocument {
  const CompanyDocument({
    required this.id,
    required this.title,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.uploadedAt,
    this.readUrl,
  });

  factory CompanyDocument.fromJson(Map<String, dynamic> json) => CompanyDocument(
    id: (json['id'] as num).toInt(),
    title: json['documentTitle'] as String? ?? '',
    fileName: json['fileName'] as String? ?? '',
    contentType: json['contentType'] as String? ?? '',
    sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
    uploadedAt:
        DateTime.tryParse(json['uploadedAt'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    readUrl: json['readUrl'] as String?,
  );

  final int id;
  final String title;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final DateTime uploadedAt;

  /// Good for a few minutes after the list was read; [CompanyDocumentRepository.readUrl]
  /// mints a fresh one to open it.
  final String? readUrl;

  bool get isImage => contentType.startsWith('image/');
  bool get isPdf => contentType == 'application/pdf';

  /// "PDF", "PNG", "XLSX" — from the file's own extension when it has one.
  String get kindLabel {
    final dot = fileName.lastIndexOf('.');
    if (dot > 0 && dot < fileName.length - 1) {
      return fileName.substring(dot + 1).toUpperCase();
    }
    if (isPdf) return 'PDF';
    final slash = contentType.indexOf('/');
    return slash >= 0 ? contentType.substring(slash + 1).toUpperCase() : 'File';
  }

  CompanyDocument renamed(String next) => CompanyDocument(
    id: id,
    title: next,
    fileName: fileName,
    contentType: contentType,
    sizeBytes: sizeBytes,
    uploadedAt: uploadedAt,
    readUrl: readUrl,
  );
}

/// "820 KB", "3.4 MB".
String formatDocumentSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
}

/// The server's documents of a client or a contractor. Stored through the
/// same asset routes as photos ([EntityPhotoRepository.store]).
class CompanyDocumentRepository {
  CompanyDocumentRepository({
    required this.baseUrl,
    http.Client? client,
    http.Client? uploadClient,
    this.useMockResponses = false,
  }) : _client = client ?? http.Client(),
       _store = EntityPhotoRepository(
         baseUrl: baseUrl,
         client: client,
         uploadClient: uploadClient,
       );

  final String baseUrl;
  final bool useMockResponses;
  final http.Client _client;
  final EntityPhotoRepository _store;

  final Map<String, List<CompanyDocument>> _mock = {};
  int _mockIds = 1;

  /// Newest first.
  Future<List<CompanyDocument>> list(String owner, String id) async {
    if (useMockResponses) return List.of(_mock['$owner:$id'] ?? const []);
    final payload = await _send(
      'GET',
      '/api/assets/documents?entityType=${Uri.encodeQueryComponent(owner)}'
          '&entityId=${Uri.encodeQueryComponent(id)}',
      null,
    );
    return [
      for (final row in payload['documents'] as List<dynamic>? ?? const [])
        if (row is Map<String, dynamic>) CompanyDocument.fromJson(row),
    ];
  }

  Future<CompanyDocument> upload(
    String owner,
    String id,
    XFile file,
    String title,
  ) async {
    if (useMockResponses) {
      final document = CompanyDocument(
        id: _mockIds++,
        title: title,
        fileName: file.name,
        contentType: file.mimeType ?? 'application/octet-stream',
        sizeBytes: await file.length(),
        uploadedAt: DateTime.now(),
      );
      (_mock['$owner:$id'] ??= []).insert(0, document);
      return document;
    }
    return CompanyDocument.fromJson(
      await _store.store(owner, id, file, documentTitle: title),
    );
  }

  Future<CompanyDocument> rename(int documentId, String title) async {
    if (useMockResponses) {
      for (final list in _mock.values) {
        final at = list.indexWhere((d) => d.id == documentId);
        if (at >= 0) return list[at] = list[at].renamed(title);
      }
      throw const CompanyDocumentException('Document not found.');
    }
    final payload = await _send('PATCH', '/api/assets/$documentId/title', {
      'title': title,
    });
    return CompanyDocument.fromJson(payload['document'] as Map<String, dynamic>);
  }

  Future<void> remove(int documentId) async {
    if (useMockResponses) {
      for (final list in _mock.values) {
        list.removeWhere((d) => d.id == documentId);
      }
      return;
    }
    await _send('DELETE', '/api/assets/$documentId', null);
  }

  /// A link to the file that works for a few minutes, without signing in —
  /// what a browser or a PDF viewer is handed.
  Future<String> readUrl(int documentId) async {
    if (useMockResponses) {
      throw const CompanyDocumentException('Demo documents cannot be opened.');
    }
    final payload = await _send('POST', '/api/assets/$documentId/read-url', const {});
    final url = payload['readUrl'] as String?;
    if (url == null || url.isEmpty) {
      throw const CompanyDocumentException('The document cannot be opened.');
    }
    return url;
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers['Content-Type'] = 'application/json';
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(await _client.send(request));
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      payload = const {};
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] == false) {
      throw CompanyDocumentException(
        payload['error'] as String? ?? 'The server answered ${response.statusCode}.',
      );
    }
    return payload;
  }
}

class CompanyDocumentException implements Exception {
  const CompanyDocumentException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Every company's documents on screen, read once and kept current.
///
/// A box asks with [request] from build; a document stored anywhere else —
/// the phone, another desktop — arrives as the server's `asset_changed`,
/// which reads that company again.
class CompanyDocumentsProvider extends ChangeNotifier {
  CompanyDocumentsProvider({
    required CompanyDocumentRepository repository,
    bool listen = true,
  }) : _repository = repository,
       _listening = listen {
    if (listen) {
      SocketService.instance.on('asset_changed', _onAssetChanged);
      SocketService.instance.on('realtime:reconnected', _onReconnected);
    }
  }

  final CompanyDocumentRepository _repository;
  final bool _listening;
  final Map<String, List<CompanyDocument>> _documents = {};
  final Set<String> _loading = {};
  final Set<String> _busy = {};
  final Map<String, String> _errors = {};
  bool _disposed = false;

  CompanyDocumentRepository get repository => _repository;

  static String _key(String owner, String id) => '$owner:$id';

  /// Null until read.
  List<CompanyDocument>? documentsOf(String owner, String id) =>
      _documents[_key(owner, id)];

  /// Why the last read failed, if it did.
  String? errorOf(String owner, String id) => _errors[_key(owner, id)];

  /// True while a file is going up or a document is being changed.
  bool isBusy(String owner, String id) => _busy.contains(_key(owner, id));

  /// Reads [owner] [id]'s documents unless they are known. Cheap: call it
  /// from build.
  void request(String owner, String id) {
    final key = _key(owner, id);
    if (_documents.containsKey(key) || _loading.contains(key)) return;
    scheduleMicrotask(() => refresh(owner, id));
  }

  Future<void> refresh(String owner, String id) async {
    final key = _key(owner, id);
    if (_loading.contains(key)) return;
    _loading.add(key);
    try {
      final documents = await _repository.list(owner, id);
      if (_disposed) return;
      _documents[key] = documents;
      _errors.remove(key);
    } catch (error) {
      if (_disposed) return;
      _errors[key] = '$error';
      _documents[key] ??= const [];
    } finally {
      _loading.remove(key);
      if (!_disposed) notifyListeners();
    }
  }

  void _onAssetChanged(dynamic data) {
    if (data is! Map) return;
    final owner = '${data['entityType'] ?? ''}';
    final id = '${data['entityId'] ?? ''}';
    if (_documents.containsKey(_key(owner, id))) unawaited(refresh(owner, id));
  }

  void _onReconnected(dynamic _) {
    for (final key in _documents.keys.toList()) {
      final cut = key.indexOf(':');
      unawaited(refresh(key.substring(0, cut), key.substring(cut + 1)));
    }
  }

  /// Files [file] under [title]. Answers why not, or null when it landed.
  Future<String?> upload(String owner, String id, XFile file, String title) =>
      _change(owner, id, () async {
        final document = await _repository.upload(owner, id, file, title);
        final key = _key(owner, id);
        final current = _documents[key] ?? const [];
        _documents[key] = [
          document,
          for (final d in current)
            if (d.id != document.id) d,
        ];
      });

  Future<String?> rename(String owner, String id, CompanyDocument document, String title) =>
      _change(owner, id, () async {
        final next = await _repository.rename(document.id, title);
        final key = _key(owner, id);
        _documents[key] = [
          for (final d in _documents[key] ?? const <CompanyDocument>[])
            d.id == document.id ? d.renamed(next.title) : d,
        ];
      });

  Future<String?> remove(String owner, String id, CompanyDocument document) =>
      _change(owner, id, () async {
        await _repository.remove(document.id);
        final key = _key(owner, id);
        _documents[key] = [
          for (final d in _documents[key] ?? const <CompanyDocument>[])
            if (d.id != document.id) d,
        ];
      });

  Future<String?> _change(String owner, String id, Future<void> Function() call) async {
    final key = _key(owner, id);
    _busy.add(key);
    notifyListeners();
    try {
      await call();
      return null;
    } catch (error) {
      return '$error';
    } finally {
      _busy.remove(key);
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_listening) {
      SocketService.instance.off('asset_changed', _onAssetChanged);
      SocketService.instance.off('realtime:reconnected', _onReconnected);
    }
    super.dispose();
  }
}
